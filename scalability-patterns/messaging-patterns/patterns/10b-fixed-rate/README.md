# Pattern 10b: Pull from the queue at a fixed rate

## What it shows

How to pace calls to a slow target with a Recurrence trigger that pulls a fixed batch
from Service Bus each interval. The target is a Cosmos DB container with 400 RU/s.
Patterns 10a (cap concurrency) and 10c (retry with backoff) send the same load.

## Flow

```
Locust (Azure Load Testing) --sendMessages--> queue "orders"
  -> orders-fixed-rate (stateful)
       trigger: Recurrence every 5 s, concurrency runs 1, maximumWaitingRuns 1
       Get_messages: getMessagesFromQueueV2, maxMessages 200 (peek-lock)
       For_each_message, concurrency 50:
            Upsert_limited: Cosmos DB CreateOrUpdateDocument into limited/items (400 RU/s)
            Complete_message on success; Abandon_message on failure or timeout
```

The nominal rate is 200 messages per 5 s, or 40 messages/s. One run is active at a
time, so a run that takes longer than 5 s delays the next pull.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 |
| Queue `orders` | Standard, lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | Recurrence, `frequency` Second, `interval` 5, concurrency runs 1, `maximumWaitingRuns` 1 |
| Receive | `getMessagesFromQueueV2`, `maxMessages` 200 |
| For each | `runtimeConfiguration.concurrency.repetitions` 50 |
| Action | `Upsert_limited`, default retry policy, document padded with `range(0, 400)` (about 87 RU per write) |
| Cosmos DB | database `limited`, container `items`, 400 RU/s dedicated, partition key `/pk` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 50`, `prefetchCount = 0` (trigger settings, unused here) |
| `hostSettings`, `extraAppSettings` | none |
| Load (same for 10a, 10b and 10c) | 1 user x 10 messages x 1 batch/s = 10 msg/s for 3 min (1,810 messages), 1 engine, 25 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 10b-fixed-rate
.\scripts\Invoke-LoadTest.ps1    -Pattern 10b-fixed-rate
.\scripts\Export-Results.ps1     -Pattern 10b-fixed-rate -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\patterns\10b-fixed-rate\tools\Run-Queries.ps1 -Pattern 10b-fixed-rate -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1   -Pattern 10b-fixed-rate -Down
.\patterns\10b-fixed-rate\tools\Reset-Queue.ps1 -Pattern 10b-fixed-rate
```

The Recurrence trigger runs every 5 s even when the queue is empty. Stop the app
(`-Down`) after the export.

## Results

Run `run-20261122-113943` (westus3, WS1), window 11:40Z to 12:05Z:

| Metric | Value |
|---|---|
| Messages sent / completed | 1,810 / 1,810 |
| Runs that pulled messages | 20 batch runs; p50 33.2 s, p95 68.4 s, p99 77.1 s |
| Drain time | 612 s |
| Successful writes | mean 3.0/s, peak 10/s, best minute 216 |
| Cosmos responses | 12,116 x 429 (peak 1,440 per minute), 1,810 x 201 |
| Retries per message | mean 0.41, max 3; 0 redeliveries |
| `Upsert_limited` | p50 1,277 ms, p95 27,158 ms |
| End-to-end latency (send to write) | p50 230 s, p95 409 s, p99 432 s, max 439 s |
| Peak `orders` backlog | 1,182 messages |
| Max instances | 1 |
| Memory | plan max 56%, working set 231 MB |
| Failed actions, dead letters | 0 |

The export's run counts are runs, not messages; it also counts the empty Recurrence
runs. Use `custom/upsert-throughput.json` and `custom/e2e-latency.json` for messages.

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Custom query output: `custom/*.json`.

### What the fixed rate does

- It drained fastest of the three (612 s) with the best end-to-end latency (p50 230 s).
- The real rate was set by the target, not by the schedule. The nominal 40 msg/s was
  about 9 times the container's limit of about 4.6 writes/s, so each batch ran 33 to
  77 s and later pulls waited. The interval only gives an exact rate when one batch
  finishes inside one interval.
- Because 50 writes ran at once, Cosmos returned 12.1K 429s. The default retry policy
  absorbed them (0.41 retries per message) but slowed the slowest writes to 27 s.
- To get an exact rate, set `maxMessages` x calls per message <= limit x interval, and
  keep For each concurrency low enough that one batch fits in one interval.

## Notes

- Each write cost about 87 RU (160K RU for 1,810 writes), so the ceiling was about
  4.6 writes/s, or about 276 per minute.
- The lock duration (5 min) was longer than the slowest batch (77 s), so no lock
  expired and no message was delivered twice.
- Messages are settled with `completeQueueMessageV2` / `abandonQueueMessageV2` inside
  the run, so a failed write goes back to the queue. Settling a trigger message from a
  stateful workflow needs VNet integration (else `VNetPrivatePortsNotConfigured`);
  this design uses the receive action instead.
- The run used one instance. The plan did not scale out.
