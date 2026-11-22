# Pattern 2a: Drain a burst as fast as possible

## What it shows

How fast a Logic Apps Standard app clears a sudden spike of orders from a Service Bus
queue when nothing caps the trigger. The trigger splits each batch into one run per
message, so the backlog moves into the app's job queue, which is meant to drive
scale-out. Pattern 2b sends the same burst and drains it at a fixed rate instead.

## Flow

```
Locust (Azure Load Testing, BurstShape) --sendMessages--> queue "orders"
  -> orders-drain-fast (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn per message,
                maxMessageBatchSize 100, no runtimeConfiguration.concurrency
       Process_order: calls shared stateless child workflow "process-order"
            Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

The parent action `Process_order` sets the tracked properties `messageId`,
`enqueuedTimeUtc`, `sentAtUtc` and `pattern`, which the end-to-end latency query uses.
The child is stateless, so the call is synchronous and has no run history of its own.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20, prewarmed count not set (platform default), runtime scale monitoring off |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 100, `splitOn` on, no concurrency setting |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| `hostSettings`, `extraAppSettings` | none |
| Load (same as 2b) | 60 s baseline (1 user, 5 messages/s), 120 s burst (5 users x 50 messages x 1 batch/s = 250 msg/s), 60 s quiet; 1 engine; 10 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 2a-drain-fast
.\scripts\Invoke-LoadTest.ps1    -Pattern 2a-drain-fast            # burst shape from params.json
.\scripts\Export-Results.ps1     -Pattern 2a-drain-fast -StartUtc <start> -EndUtc <after drain>
.\patterns\2a-drain-fast\tools\Run-Queries.ps1 -Pattern 2a-drain-fast -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1   -Pattern 2a-drain-fast -Down
.\patterns\2a-drain-fast\tools\Reset-Queue.ps1 -Pattern 2a-drain-fast
```

The drain takes far longer than the 10 min `drainMinutes`. Wait until the last
`Upsert_order` appears in App Insights, then export with an `-EndUtc` after it.
`Run-Queries.ps1` runs the KQL files in `queries/` and writes JSON to
`results/2a-drain-fast/<runId>/custom`.

## Results

Run `run-20261122-075446` (westus3, WS1), window 07:54Z to 08:48Z:

| Metric | Value |
|---|---|
| Messages sent | 30,500 (load ended 08:05:23Z) |
| Workflow runs completed | 30,500 (0 failed) |
| Drain time | 2,782 s (46.4 min) from first send; 38.6 min after the load ended |
| Average throughput | 10.97 runs/s (peak 23.7/s over 10 s; export peak 16.5/s per minute) |
| Flatness of runs/s | stdev 4.69, CV 0.43, p10 5/s, p90 18/s |
| Cosmos upserts | mean 11.0/s, stdev 5.1, peak 28.1/s |
| Run duration | p50 611 s, p95 1,088 s, p99 1,536 s |
| End-to-end latency (enqueue to run end) | p50 1,523 s, p95 2,517 s, p99 2,591 s |
| Action p50 / p95 | `Process_order` 11.9 s / 29.0 s; `Upsert_order` 1.7 s / 10.1 s |
| Peak `orders` backlog | 24,450 messages |
| Max instances | 1 |
| Failed actions, exceptions, dead letters, skipped triggers | 0 |

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Custom query output: `custom/*.json`.

### Why it did not drain faster

- The app never scaled past one instance, although `maximumElasticWorkerCount` is 20 and
  the job queue held about 20,000 waiting runs. Runtime scale monitoring was off, so the
  platform scaler did not add workers. Raise `minimumElasticInstanceCount` if the drain
  needs more instances; do not rely on scale-out.
- `splitOn` completes each Service Bus message when it creates the run. The queue
  emptied in minutes, but the work then waited in the storage job queue. Queue depth is
  therefore not a measure of progress; count run ends in App Insights instead.
- With 20,000 runs in flight on one instance, every action slowed down: `Process_order`
  p50 was 11.9 s, against 0.65 s in pattern 2b. Contention cancelled most of the gain
  from not capping the trigger. This run drained only about 25% faster than 2b.

## Notes

- Removing trigger concurrency from a workflow that has used it makes the workflow stop
  taking messages (`CannotDisableTriggerConcurrency`). Deploy under a new workflow name.
- With concurrency on, `splitOn` accepts at most 100 items per batch; keep
  `maxMessageBatchSize` at 100 or less.
- The export counts only `measurement.workflowName` (the parent). Child action timings
  come from `action-durations.json`.

