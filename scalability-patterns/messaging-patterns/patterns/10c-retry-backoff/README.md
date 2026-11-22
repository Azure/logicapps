# Pattern 10c: Retry with backoff against a rate-limited downstream

## What it shows

What happens when the workflow does not throttle at all and an exponential retry
policy absorbs the target's 429 responses. The target is a Cosmos DB container with
400 RU/s. Patterns 10a (cap concurrency) and 10b (fixed-rate pull) send the same load.

## Flow

```
Locust (Azure Load Testing) --sendMessages--> queue "orders"
  -> orders-retry-backoff (stateful)
       trigger: Service Bus receiveQueueMessages (built-in), maxMessageBatchSize 100,
                splitOn on, concurrency runs 100, maximumWaitingRuns 200
       Upsert_limited: Cosmos DB CreateOrUpdateDocument into limited/items (400 RU/s),
                       retry exponential, count 6, interval 5 s, min 5 s, max 1 min
```

Up to 100 writes are in flight, far above what the container accepts.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 |
| Queue `orders` | Standard, lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 100, `splitOn` on, `runtimeConfiguration.concurrency.runs` 100, `maximumWaitingRuns` 200 |
| Action retry policy | `exponential`, `count` 6, `interval` PT5S, `minimumInterval` PT5S, `maximumInterval` PT1M |
| Action | `Upsert_limited`, document padded with `range(0, 400)` (about 87 RU per write) |
| Cosmos DB | database `limited`, container `items`, 400 RU/s dedicated, partition key `/pk` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| `hostSettings`, `extraAppSettings` | none |
| Load (same for 10a, 10b and 10c) | 1 user x 10 messages x 1 batch/s = 10 msg/s for 3 min (1,810 messages), 1 engine, 25 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 10c-retry-backoff
.\scripts\Invoke-LoadTest.ps1    -Pattern 10c-retry-backoff
.\scripts\Export-Results.ps1     -Pattern 10c-retry-backoff -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\patterns\10c-retry-backoff\tools\Run-Queries.ps1 -Pattern 10c-retry-backoff -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1   -Pattern 10c-retry-backoff -Down
.\patterns\10c-retry-backoff\tools\Reset-Queue.ps1 -Pattern 10c-retry-backoff
```

## Results

Run `run-20261122-115751` (westus3, WS1), window 11:57Z to 12:12Z:

| Metric | Value |
|---|---|
| Messages sent / runs | 1,810 / 1,810 (all succeeded) |
| Drain time | 650 s (first send 12:00:38.8Z, last run end 12:11:28.7Z) |
| Successful writes | mean 2.8/s, peak 10/s, best minute 192 |
| Cosmos responses | 19,655 x 429 (peak 2,314 per minute), 1,747 x 201 (metric; the app logged 1,810 successful writes) |
| Retries per message (action retries) | 1,096 of 1,810 messages retried; mean 0.83, max 2; 0 redeliveries; 0 gave up |
| Run duration | p50 10.8 s, p95 24.3 s, p99 25.6 s, max 26.1 s |
| `Upsert_limited` | p50 10.2 s, p95 24.1 s, max 25.5 s |
| End-to-end latency (send to run end) | p50 237 s, p95 444 s, p99 462 s, max 472 s |
| Peak `orders` backlog | 1,130 messages |
| Max instances | 1 |
| Memory | plan max 53%, working set 186 MB |
| Failed actions, exceptions, dead letters | 0 |

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Custom query output: `custom/*.json`.

### What retry with backoff does

- Every message finished, and throughput (2.8 writes/s) was close to 10b's. The retry
  budget (6 tries, up to 1 min apart) was enough at this load.
- The target paid for it: 19.7K 429s, 5 times as many as 10a and more than 10 times
  the number of successful writes. Use this design only when the target tolerates
  throttled calls and the throttling is short.
- Retries showed up as slow actions, not failures: `Upsert_limited` p50 was 10.2 s,
  against 0.35 s in 10a. Cosmos SDK retries inside the action hid most 429s; the
  workflow retry policy fired at most twice per message.
- Trigger concurrency of 100 did not add throughput. The container, not the app, set
  the rate.

## Notes

- Each write cost about 87 RU (158K RU for 1,810 writes), so the ceiling was about
  4.6 writes/s, or about 276 per minute.
- The trigger uses `splitOn`, which completes each message when the run starts. A run
  that runs out of retries loses the message: it does not go back to the queue or the
  dead-letter queue. The docs page's "abandon the message" step needs a peek-lock
  receive action (as in 10b) or a VNet-integrated app that can settle trigger messages.
- The Cosmos `TotalRequests` metric showed 1,747 x 201 against 1,810 successful
  actions. The metric is sampled per minute; trust the action count.
- The run used one instance. The plan did not scale out.
