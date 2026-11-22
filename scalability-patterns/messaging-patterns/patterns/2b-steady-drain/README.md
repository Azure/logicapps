# Pattern 2b: Drain a burst at a steady rate

## What it shows

How to absorb a sudden spike of orders in a Service Bus queue and drain it at a flat,
capped rate that protects a downstream system (here Cosmos DB). Pattern 2a sends the
same burst and drains it as fast as the app allows.

## Flow

```
Locust (Azure Load Testing, BurstShape) --sendMessages--> queue "orders"
  -> orders-steady-drain (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn off,
                maxMessageBatchSize 50, concurrency runs 2, maximumWaitingRuns 10
       For_each_message over @triggerBody(), concurrency 10
            Process_order: calls shared stateless child workflow "process-order"
                Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

Each run receives up to 50 messages, and at most 2 runs are active. At most 20 child
calls, and so 20 Cosmos upserts, are in flight at any time. Messages that are not yet
received stay in the queue, so the backlog stays visible in Service Bus.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 1 (fixed at one instance) |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 50, `splitOn` off, `runtimeConfiguration.concurrency.runs` 2, `maximumWaitingRuns` 10 |
| For each | `runtimeConfiguration.concurrency.repetitions` 10 |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 50`, `prefetchCount = 0` |
| `hostSettings`, `extraAppSettings` | none |
| Load (same as 2a) | 60 s baseline (1 user, 5 messages/s), 120 s burst (5 users x 50 messages x 1 batch/s = 250 msg/s), 60 s quiet; 1 engine; 10 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 2b-steady-drain
.\scripts\Invoke-LoadTest.ps1    -Pattern 2b-steady-drain          # burst shape from params.json
.\scripts\Export-Results.ps1     -Pattern 2b-steady-drain -StartUtc <start> -EndUtc <after drain>
.\patterns\2b-steady-drain\tools\Run-Queries.ps1 -Pattern 2b-steady-drain -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1   -Pattern 2b-steady-drain -Down
.\patterns\2b-steady-drain\tools\Reset-Queue.ps1 -Pattern 2b-steady-drain
```

The drain takes about an hour, far longer than the 10 min `drainMinutes`. Wait until
the last `Upsert_order` appears in App Insights, then export with an `-EndUtc` after it.

## Results

Run `run-20261122-075444` (westus3, WS1), window 07:54Z to 09:00Z:

| Metric | Value |
|---|---|
| Messages sent | 30,500 (load ended 08:05:28Z) |
| Parent runs | 629 (0 failed), about 48 messages each |
| Orders processed (`Process_order`, upserts) | 30,500 (0 failed) |
| Drain time | 3,522 s (58.7 min) from first send; 51.1 min after the load ended |
| Cosmos upserts | mean 8.66/s, stdev 1.47 (10 s buckets), peak 12/s |
| Upserts per minute, steady state (07:59Z to 08:55Z) | mean 527, stdev 32, min 415, max 610 |
| Parent runs/s | mean 0.20, stdev 0.03, CV 0.15, peak 0.4 |
| Parent run duration | p50 10.9 s, p95 12.0 s, p99 12.8 s |
| End-to-end latency (enqueue to run end) | p50 1,695 s, p95 3,175 s, p99 3,308 s |
| Action p50 / p95 | `Process_order` 635 ms / 1,058 ms; `Enrich_order` 132 / 511 ms; `Upsert_order` 114 / 424 ms; `Transform_order` 21 / 225 ms |
| Peak `orders` backlog | 28,850 messages |
| Max instances | 1 |
| Failed actions, exceptions, dead letters, skipped triggers | 0 |

The export's `runsCompleted`, `avgMessagesPerSecond` label and `peakRunsPerSecond`
count parent runs. Use `custom/downstream-upserts-per-second.json` for orders.

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Custom query output: `custom/*.json`.

### What the cap does

- Cosmos saw a flat 500 to 540 upserts per minute for the whole hour. 2a, with no cap,
  hit peaks of 28 upserts/s.
- Actions stayed fast: `Process_order` p50 was 0.64 s, against 11.9 s in 2a. The cap
  keeps the app out of contention.
- The rate is set by the cap, not by the app. Two runs of 50 messages each took about
  11 s, so throughput was about 9 orders/s. To drain faster, raise the trigger
  concurrency, the batch size or the For each concurrency.
- The backlog drained from Service Bus at the processing rate. Queue depth is a fair
  progress measure here, unlike in 2a.

## Notes

- No trigger runs were skipped (`skipped-triggers.kql` returned no rows). When both
  runs are busy, the Service Bus trigger stops receiving; the messages wait in the queue.
- Removing trigger concurrency from a workflow that has used it makes the workflow stop
  taking messages (`CannotDisableTriggerConcurrency`). Deploy under a new workflow name.
- The export counts only `measurement.workflowName` (the parent). Child action timings
  come from `action-durations.json`.
