# Pattern 1a: Maximum throughput, steady high load

## What it shows

How many orders a Logic Apps Standard app can take from a Service Bus queue each second
under a constant, high send rate. It also shows how the elastic plan scales out and
whether the queue backlog stays flat or grows.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 10--> queue "orders"
  -> orders-max-throughput-v2 (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn per message,
                maxMessageBatchSize 100, no trigger concurrency limit
       Process_order: calls shared child workflow "process-order"
            Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

The trigger auto-completes messages. The parent action `Process_order` sets the tracked
properties `messageId`, `enqueuedTimeUtc`, `sentAtUtc` and `pattern`, which the end-to-end
latency query uses.

The workflow is named `orders-max-throughput-v2` because the runtime does not let you remove a
trigger concurrency setting from an existing workflow (`CannotDisableTriggerConcurrency`). The
old workflow stopped taking messages after the change. A new workflow name avoids this.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 2, `maximumElasticWorkerCount` 20 |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 100, `splitOn`, no `runtimeConfiguration.concurrency` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load | 20 users x 1 engine x 10 messages x 1 batch/s = 200 msg/s for 10 min, 10 min drain |

Changes from the pilot: the trigger concurrency limit (100 runs, `maximumWaitingRuns` 100) is
gone, and the plan keeps at least 2 instances instead of 1.
## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 1a-max-throughput
.\scripts\Invoke-LoadTest.ps1    -Pattern 1a-max-throughput            # defaults from params.json
.\scripts\Export-Results.ps1     -Pattern 1a-max-throughput            # KQL + metrics + charts
.\scripts\Set-PatternScale.ps1   -Pattern 1a-max-throughput -Down
```

For a short check, run
`.\scripts\Invoke-LoadTest.ps1 -Pattern 1a-max-throughput -DurationMinutes 5 -Users 5 -DrainMinutes 4`
(50 msg/s).

## Results

See `results/1a-max-throughput/<runId>/summary.json` and the PNG charts beside it
(`throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`, `instances.png`,
`failures.png`).

### Large-scale runs

These runs show how far one app scales. They used a larger setup than `params.json`:

| Setting | Value |
|---|---|
| Plan | WS3, 10 always-ready instances, maximum 100, runtime scale monitoring on |
| Storage | 4 accounts (`Runtime.ScaleUnitsCount` 4) |
| Service Bus | Premium, 4 messaging units, lock 1 min |
| Cosmos DB | autoscale up to 80,000 RU/s, indexing only the queried paths |
| Trigger | batch 100 with `splitOn`, child workflow `process-order` |
| Load | about 1 KB JSON orders from 16 processes: 200 msg/s warm-up, 2,000 msg/s for 15 min, then 3,000 and 4,000 msg/s |

| Send rate | Result |
|---|---|
| 200 msg/s | Held; p95 0.3 s end to end |
| 2,000 msg/s | Held on 50-60 instances; p50 0.3 s, p95 5.4 s, p99 16.2 s (last 10 min) |
| 3,000 msg/s | About 2,550 msg/s processed; p95 311 s |
| 4,000 msg/s | About 2,200 msg/s and falling |

- Storage set the limit. The main storage account reached about 40,000 transactions a second
  and throttled; the scale-unit accounts did not. Each message cost about 18 storage
  transactions.
- Service Bus CPU peaked at 18%. Cosmos DB returned no 429 errors.
- 88 of 6.06 million messages were lost and about 1.7% ran twice. An earlier run with Cosmos
  capped at 30,000 RU/s lost about 581,000 messages: the trigger had already completed them on
  the queue when the child failed.

### Small sample runs

These runs used `params.json`: westus3, WS1, 200 msg/s target for 10 min, then a 10 min drain.
They had no runtime scale monitoring, so the app stayed at its minimum instance count. Don't
read them as capacity.

| Metric | Pilot `run-20261122-070617` | Tuned `run-20261122-081110` |
|---|---|---|
| Trigger concurrency | 100 runs, 100 waiting | none |
| Minimum instances | 1 | 2 |
| Messages sent | 120,120 | 120,200 |
| Parent runs completed in the window | 3,830 | about 25,000 (08:14-08:37) |
| Completed runs per second | 2.89 average, 3.33 peak | 17-20 steady, 20.1 peak |
| Run duration | p50 1.0 s, p95 2.1 s | p50 241 s, p95 699 s, p99 936 s |
| End-to-end latency | p50 656 s, p95 1,267 s | p50 683 s, p95 1,403 s |
| Peak `orders` backlog | 118,390 | 75,043 |
| Max instances | 1 | 2 (the minimum; no scale-out) |
| Failures | 0 | 4 Cosmos `RequestTimeout` in the child, 0 dead letters |

The summary's 9.25 runs/s average divides by the whole export window, which includes idle
time. Per-minute counts from App Insights show 1,000-1,200 completed runs a minute (17-20/s)
from 08:14 to 08:37 on 2 instances. This is the sustained ceiling for WS1 x 2 with a child call
per message: 200 msg/s is not reachable with this configuration.

### What changed and what did not

- Removing the concurrency limit let the trigger start runs at 25-50 per second, so the app
  took messages off the queue 6-7 times faster than the pilot. The backlog peaked at 75K
  instead of 118K.
- Runs started faster than they finished (starts 1,500-3,000 a minute, ends 700-1,200). The
  extra runs waited inside the app, so run duration rose from 1 s to minutes. Run duration
  here measures waiting, not work.
- The app never added a third instance. Without runtime scale monitoring it doesn't scale on
  Service Bus backlog. The large-scale runs turned it on and set a maximum instance count, and
  scaled to 50-60 instances.
- Each message costs 2 runs (parent and child) and about 5 actions. Moving the child's actions
  into the parent, or using a stateless parent without `splitOn`, removes one run per message.

## Notes

- You cannot remove `runtimeConfiguration.concurrency` from a trigger once a workflow has used
  it. Deploy under a new workflow name, as this sample does.
- Keep `maxMessageBatchSize` at 100 or less. The first smoke run (`run-20261122-061357`) had
  no batch limit: the trigger read 1000 messages from the backlog, failed the `splitOn` limit and
  abandoned them, so only 20 of 15050 messages ran and 600 went to the dead-letter queue.
- Do not set `clientTrackingId` from the trigger body on a `splitOn` trigger. The runtime
  abandons the whole batch with no run history. Use tracked properties instead.
- The child workflow is stateless, so it has no run history; its actions still appear in
  App Insights.
