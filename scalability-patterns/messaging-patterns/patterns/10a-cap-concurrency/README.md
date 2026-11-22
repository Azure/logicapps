# Pattern 10a: Cap concurrency to a rate-limited downstream

## What it shows

How to stay under the limit of a slow target by capping how many runs call it at once.
The target is a Cosmos DB container with 400 RU/s, so throttling (HTTP 429) is real.
Patterns 10b (fixed-rate pull) and 10c (retry with backoff) send the same load to the
same kind of container.

## Flow

```
Locust (Azure Load Testing) --sendMessages--> queue "orders"
  -> orders-cap-concurrency (stateful)
       trigger: Service Bus receiveQueueMessages (built-in), maxMessageBatchSize 50,
                splitOn on, concurrency runs 10, maximumWaitingRuns 20
       Upsert_limited: Cosmos DB CreateOrUpdateDocument into limited/items (400 RU/s),
                       default retry policy
```

At most 10 runs, and so 10 Cosmos writes, are in flight on the instance. The trigger
stops receiving when the cap is reached; the backlog stays in Service Bus.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 |
| Queue `orders` | Standard, lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 50, `splitOn` on, `runtimeConfiguration.concurrency.runs` 10, `maximumWaitingRuns` 20 |
| Action | `Upsert_limited`, default retry policy, document padded with `range(0, 400)` (about 87 RU per write) |
| Cosmos DB | database `limited`, container `items`, 400 RU/s dedicated, partition key `/pk` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 50`, `prefetchCount = 0` |
| `hostSettings`, `extraAppSettings` | none |
| Load (same for 10a, 10b and 10c) | 1 user x 10 messages x 1 batch/s = 10 msg/s for 3 min (1,810 messages), 1 engine, 25 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 10a-cap-concurrency
.\scripts\Invoke-LoadTest.ps1    -Pattern 10a-cap-concurrency
.\scripts\Export-Results.ps1     -Pattern 10a-cap-concurrency -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\patterns\10a-cap-concurrency\tools\Run-Queries.ps1 -Pattern 10a-cap-concurrency -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1   -Pattern 10a-cap-concurrency -Down
.\patterns\10a-cap-concurrency\tools\Reset-Queue.ps1 -Pattern 10a-cap-concurrency
```

Pass `Run-Queries.ps1` as a literal path. Copy `queries\*.kql` into the result folder;
the export does not.

## Results

Run `run-20261122-113944` (westus3, WS1), window 11:40Z to 12:05Z:

| Metric | Value |
|---|---|
| Messages sent / runs | 1,810 / 1,810 (all succeeded) |
| Drain time | 1,273 s (first send 11:42:28Z, last run end 12:03:41Z) |
| Successful writes | mean 1.4/s, peak 10/s, best minute 100 |
| Cosmos responses | 3,752 x 429 (peak 239 per minute), 1,810 x 201, 1 x 200 |
| Retries per message | mean 0.01, max 1 (18 messages); 0 redeliveries |
| Run duration | p50 1.2 s, p95 2.3 s, p99 4.1 s, max 10.8 s |
| `Upsert_limited` | p50 348 ms, p95 1,527 ms |
| End-to-end latency (send to run end) | p50 551 s, p95 1,059 s, p99 1,091 s, max 1,093 s |
| Peak `orders` backlog | 1,550 messages |
| Max instances | 1 |
| Memory | plan max 54%, working set 190 MB |
| Failed actions, exceptions, dead letters | 0 |

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Custom query output: `custom/*.json`;
Cosmos status codes in `custom/cosmos-status.json`, memory in `custom/memory.json`.

### What the cap does

- It gave the fewest 429s of the three samples (3.7K against 12.1K for 10b and 19.7K
  for 10c), and fast writes (p50 0.35 s).
- It also gave the lowest throughput. Ten writes in flight averaged 1.4 writes/s, well
  under the container's limit of about 4.6 writes/s. Drain time and end-to-end latency
  were twice those of 10b and 10c.
- A concurrency cap limits calls in flight, not calls per second. 10 parallel writes
  can still burst above 400 RU in one second, so some 429s remain. Size the cap from
  the target's latency: limit per second x call duration.
- The backlog stayed in Service Bus, as the docs page advises.

## Notes

- Each write cost about 87 RU (157K RU for 1,810 writes), so the container's ceiling
  was about 4.6 writes/s, or about 276 per minute.
- `splitOn` auto-completes each message when the run starts. A failed run would lose
  the message; it would not go back to the queue or the dead-letter queue. That is why
  dead letters are 0 by design.
- The run used one instance. The plan allows 20 instances but did not scale out.
- Stateless workflows reject `splitOn` and trigger `runtimeConfiguration`, so the
  docs page's "Stateless or stateful" choice does not hold with this design.
- The Cosmos metric is sampled; compare its 201 count with the action count.
