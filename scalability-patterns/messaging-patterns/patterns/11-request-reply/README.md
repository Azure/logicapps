# Pattern 11: Request-reply over Service Bus

## What it shows

A caller sends an HTTP request and waits for the reply, while the work goes through Service
Bus. The page shows how client latency, throughput and errors change as the request rate
rises, and at which rate the tail latency and errors start to grow.

## Flow

```
Locust (Azure Load Testing) --HTTP POST to listCallbackUrl--> rr-front (stateless)
  rr-front: Request trigger
     Request_id   = guid()
     Send_request -> queue "requests"  (messageId = correlationId = Request_id,
                                        replyTo "replies", replyToSession = Request_id)
     Get_reply    <- session queue "replies", sessionId = Request_id, 1 message
     Complete_reply, Response 200 (or 504 when no reply arrives)

  rr-back (stateful): Service Bus receiveQueueMessages on "requests", splitOn
     Process_order: shared child workflow "process-order"
     Send_reply  -> queue "replies", sessionId = replyToSessionId ?? correlationId ?? messageId
```

The built-in Service Bus trigger does not return `replyToSessionId`, so rr-back falls back to
`correlationId`. rr-front sets `correlationId` to the request id, so the reply lands in the
session that rr-front waits on. A send to the session queue without a session id fails with
BadRequest; rr-front then times out and returns 504 after about 30 s.

Stateless workflows reject `splitOn`, so the back end is stateful. The front end must be
stateless so the Response comes back on the open HTTP connection without run-history writes.

The locustfile checks that the reply body carries the same request id that it sent, and counts
a mismatch as a correlation error.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 2, `maximumElasticWorkerCount` 20 |
| Queue `requests` | lock 5 min, max delivery 10, no sessions |
| Queue `replies` | sessions, lock 1 min, max delivery 5, reply TTL 5 min |
| rr-back trigger | `maxMessageBatchSize` 100, `splitOn` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load | 1 engine, stages of 120 s at 5, 10, 20, 40, 60, 80, 120 users, no think time |

`CALLBACK_URL` is filled in at run time from the `listCallbackUrl` API. Never commit it; it
contains a SAS signature.

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 11-request-reply
.\scripts\Invoke-LoadTest.ps1    -Pattern 11-request-reply
.\scripts\Export-Results.ps1     -Pattern 11-request-reply
.\scripts\Set-PatternScale.ps1   -Pattern 11-request-reply -Down
```

The queries in `queries\*.kql` give the front-end status codes, run durations for both
workflows, action durations and instance counts. Export-Results does not run them; run them
against the Application Insights resource.

## Results

Run `run-20261122-103515`, westus3, WS1, 10:38–10:52 UTC. Files are in
`results/11-request-reply/`: client charts (`client-latency-rps.png`, `client-errors.png`),
server charts (`run-duration.png`, `instances.png`), KQL output in `run1-kql/`, and the
Export-Results output in `run-20261122-103515/`.

Client side, 120 s per stage:

| Users | Requests | Req/s | p50 ms | p95 ms | p99 ms | Errors |
|---|---|---|---|---|---|---|
| 5 | 584 | 4.9 | 615 | 1,088 | 1,230 | 0 |
| 10 | 988 | 8.2 | 332 | 1,456 | 8,789 | 0 |
| 20 | 2,120 | 17.7 | 334 | 773 | 6,896 | 0 |
| 40 | 2,834 | 23.6 | 367 | 2,877 | 16,659 | 0 |
| 60 | 2,979 | 24.8 | 369 | 5,107 | 11,469 | 0 |
| 80 | 3,835 | 32.0 | 317 | 594 | 947 | 0 |
| 120 | 3,693 | 30.8 | 388 | 17,864 | 230,010 | 44 × 500, 1 × 502 |
| All | 17,033 | | 348 | 4,771 | 24,427 | 45 (0.26%) |

No HTTP 504s and no correlation errors.

Server side:

| Workflow | Runs | p50 ms | p95 ms | p99 ms | Max ms |
|---|---|---|---|---|---|
| rr-front | 16,988 ok, 1 failed | 327 | 4,533 | 17,477 | 207,880 |
| rr-back | 17,142 | 112 | 488 | 1,194 | 9,901 |
| process-order | 17,142 | 30 | 159 | 691 | 6,115 |

Instances grew from 2 to 14–15. The queue backlog never passed 4 messages, and no message was
dead-lettered.

### Knee

The median stays at about 330–390 ms at every rate. The tail starts to rise at about 24 req/s
(40 users), mainly while the plan scales out. Throughput stops at about 31–34 req/s: going
from 80 to 120 users adds no throughput, and some requests wait about 230 s, the platform
limit, and fail with 500 or 502.

### Findings

- The back end is not the bottleneck: rr-back p99 is 1.2 s. The slow part is `Get_reply`,
  where the front end waits for the session. Its p50 is 170–560 ms, but p99 reaches 34 s and
  the maximum is 87 s.
- Tail spikes match scale-out steps. Keep enough always-ready instances for the expected rate.
- Set the `Get_reply` wait and the front-end timeout shorter than the caller's timeout, so the
  caller gets a clear 504 instead of a 500 or 502 at the platform limit.
- A cold first call takes about 8.6 s.
