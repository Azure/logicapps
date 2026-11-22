# Pattern 3a: Scheduled drop, finish before a deadline

## What it shows

A large batch of orders lands on the queue at once (a nightly or periodic drop) and must
be processed before a deadline. The sample scales up front to finish as fast as it can:
five prewarmed instances, a burst limit of 20, and trigger concurrency off so the host
can pull work as fast as each instance allows. The benchmark window is scaled down to a
10-minute deadline.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 10, all within 1 minute--> queue "orders"
  -> orders-deadline (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn per message,
                maxMessageBatchSize 100, concurrency off
       Process_order: calls shared child workflow "process-order"
            Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

The trigger auto-completes messages. `Process_order` sets the tracked properties
`messageId`, `enqueuedTimeUtc`, `sentAtUtc` and `pattern` for the latency queries.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 5 (prewarmed), maximum burst 20 |
| Service Bus | Standard (see Notes) |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 100, concurrency off |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| App settings | `Runtime.Trigger.MaximumRunConcurrency` 400, `Runtime.Trigger.MaximumWaitingRuns` 1000 |
| Load | 10 users x 10 messages x 0.5 batch/s = 50 msg/s for 1 min = 3,000 messages, then 10 min drain |
| Deadline | 10 minutes after the first send |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 3a-deadline
.\patterns\3a-deadline\tools\Reset-Queue.ps1 -Pattern 3a-deadline
.\scripts\Invoke-LoadTest.ps1    -Pattern 3a-deadline
.\scripts\Export-Results.ps1     -Pattern 3a-deadline
.\patterns\3a-deadline\tools/Run-Queries.ps1 -Pattern 3a-deadline -StartUtc <start> -EndUtc <end> -RunId <runId>
.\scripts\Set-PatternScale.ps1   -Pattern 3a-deadline -Down
```

`tools/Run-Queries.ps1` runs the queries in `queries\` (completion time against the
deadline, instance-minutes, peak downstream rate, per-minute timeline) because
`Export-Results.ps1` runs only the shared queries.

## Results

Run `run-20261122-080425` (West US 3). Service Bus counted 3,100 incoming messages,
sent from 08:07:19.6Z to 08:08:19.0Z. That is 100 more than the 3,000-message plan, most
likely because Locust sent one extra batch per user. 3b also received 3,100, so the
samples still compare directly.

| Metric | Value |
|---|---|
| Runs succeeded / failed / dead-lettered | 3,100 / 0 / 0 |
| Completion (first send to last run end) | 5.32 min (319 s), against a 10-minute deadline |
| Throughput | average 9.72 runs/s; runs per minute 345, 588, 553, 494, 619, 501 |
| Run duration p50 / p95 / p99 | 65.4 s / 129 s / 140 s |
| End-to-end latency p50 / p95 / p99 / max | 140 s / 257 s / 270 s / 280 s |
| Instances with telemetry (`dcount(cloud_RoleInstance)`) | 1 (6 instance-minutes); the plan still billed the minimum of 5 |
| Downstream Cosmos DB upserts | mean 9.69 calls/s, stdev 4.54, peak 20.3 calls/s (10 s buckets) |
| Peak queue backlog (active messages) | 1,200 |

Charts in [`results/3a-deadline/run-20261122-080425`](../../results/3a-deadline/run-20261122-080425):
`throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Pattern query output is in its `custom\` folder.

The drop finished well inside the deadline, but only one instance did the work. The 5
prewarmed instances did not share trigger work, and the scaler did not add instances. The
queue emptied long before the work finished, because splitOn completes each message when
its run is created. The rest of the backlog sat in the workflow job queue, which made run
durations long (p50 65 s). Measure completion from run ends in App Insights, not from
queue depth.

## Notes

- The page suggests Premium Service Bus for large drops. This sample uses Standard, because
  3,000 small messages stay well below Standard limits and 3b uses Standard too, so the two
  samples differ only in the Logic Apps settings. Use Premium for drops of hundreds of
  thousands of messages or large payloads.
- `minimumElasticInstanceCount` is the only prewarm control the kit sets. For a real
  scheduled drop, raise it shortly before the drop (for example from a scheduled job) and
  lower it afterwards; prewarmed instances bill while idle.
- The `Workflows.ScaleUnitsCount` app setting (more storage partitions for the job queue)
  was not used: each scale unit needs its own
  `CloudStorageAccount.Workflows.ScaleUnitsDataStorage.CUxx.ConnectionString` setting, and
  the kit deploys one key-based storage account.
