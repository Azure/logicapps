# Pattern 3b: Scheduled drop, spread across a window

## What it shows

The same 3,000-order drop as 3a, but with no tight deadline. Instead of draining the
drop as fast as possible, the producer sets `ScheduledEnqueueTimeUtc` on each message so
Service Bus releases the drop evenly across a window. The app then runs on one or two
instances at a low, even rate, and the downstream Cosmos DB container sees a flat load
instead of a spike. The window is scaled down to 10 minutes.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 10, all within 1 minute,
                              ScheduledEnqueueTimeUtc spread over 10 minutes--> queue "orders"
  -> orders-spread-window-v2 (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn per message,
                maxMessageBatchSize 20, no trigger concurrency limit
       Process_order: calls shared child workflow "process-order"
            Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

The locustfile maps each message's send offset `t` (0-60 s) to a release time
`window start + t x (600 / 60)`, and also writes that time into the message body as
`scheduledForUtc`. `Process_order` tracks it, so `queries\schedule-lag.kql` can show how far
each run finished after its scheduled release.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, minimum 1 instance, maximum burst 2 |
| Service Bus | Standard |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions, default TTL (longer than the window) |
| Trigger | `maxMessageBatchSize` 20, no `runtimeConfiguration.concurrency` block |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load | 10 users x 10 messages x 0.5 batch/s = 50 msg/s for 1 min = 3,000 messages |
| Locust env | `SPREAD_WINDOW_SECONDS` 600, `SEND_SECONDS` 60, so about 5 msg/s are released |
| Drain | 11 minutes |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 3b-spread-window
.\patterns\3b-spread-window\tools\Reset-Queue.ps1 -Pattern 3b-spread-window
.\scripts\Invoke-LoadTest.ps1    -Pattern 3b-spread-window
.\scripts\Export-Results.ps1     -Pattern 3b-spread-window
.\patterns\3b-spread-window\tools/Run-Queries.ps1 -Pattern 3b-spread-window -StartUtc <start> -EndUtc <end> -RunId <runId>
.\scripts\Set-PatternScale.ps1   -Pattern 3b-spread-window -Down
```

## Results

Run `run-20261122-090029` (West US 3). Service Bus counted 3,100 incoming messages, sent
from 09:03:34Z to 09:04:34Z (100 over plan, the same as 3a). Their scheduled release times spread
over 10 minutes.

| Metric | Value |
|---|---|
| Runs succeeded / failed / dead-lettered | 3,100 / 0 / 0 |
| Completion (first send to last run end) | 10.08 min, against a target of 1 minute of sending plus a 10-minute window |
| Throughput | average 5.12 runs/s; every full minute 297-302 runs (4.95-5.03 runs/s) |
| Schedule lag (run end minus scheduled release) | p50 about 0.3 s each minute; p95 under 1 s; max 6.4 s in the last minute |
| Run duration p50 / p95 / p99 | 0.13 s / 0.31 s / 3.1 s |
| End-to-end latency (send to run end) p50 / p95 / p99 | 280 s / 530 s / 545 s, which is the planned schedule delay |
| Instances with telemetry | 1 (11 instance-minutes) |
| Downstream Cosmos DB upserts | mean 5.17 calls/s, stdev 0.97, peak 11.4 calls/s (10 s buckets) |
| Peak queue backlog (active messages) | 4 |

Charts in [`results/3b-spread-window/run-20261122-090029`](../../results/3b-spread-window/run-20261122-090029):
`throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Pattern query output is in its `custom\` folder.

Compared with 3a, the same drop took twice as long and used about twice the instance-minutes
(11 against 6 active, but 3a billed 5 prewarmed instances). Downstream load fell from
mean 9.7 and peak 20.3 calls/s to a flat 5.2 calls/s with a stdev of 1, and each run
took milliseconds instead of a minute.

## Notes

- The page allows two ways to spread a drop: scheduled enqueue, or a timed pull with a
  Recurrence trigger. This sample uses scheduled enqueue, because the release rate is then
  set by the producer and the app needs no extra state.
- Scheduled messages count against the queue size and are not visible to receivers until
  their release time. Keep the queue's message TTL longer than the window.
- Scheduled enqueue sets the pace, and the 2-instance plan cap limits the worst-case drain
  rate. The sample has no trigger concurrency limit. In the smoke run, a limit of 20 runs
  with `maximumWaitingRuns` 20 made the trigger pull 20 messages about every 30 seconds
  (about 0.67 runs/s), which is below the 5 msg/s release rate, so a backlog grew.
- Removing that limit from the original `orders-spread-window` workflow made the trigger
  stop receiving without an error (`CannotDisableTriggerConcurrency`): 3,100 messages sat in
  the queue for 40 minutes. A restart did not help. Once a workflow has used trigger
  concurrency, deploy the change under a new workflow name, as this sample does with
  `orders-spread-window-v2`.