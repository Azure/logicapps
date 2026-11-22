# Pattern 5b: Large messages inline (Service Bus Premium)

## What it shows

How a Logic Apps Standard app handles 1-5 MB order payloads sent directly in the message on a
Service Bus Premium queue with a 10 MB maximum message size. Compare it with
[5a](../5a-claim-check/README.md), which sends the same payloads through a blob claim check.

## Flow

```
Locust (Azure Load Testing) --sendMessages, one 1/2.5/5 MB message--> queue "orders" (Premium, 10 MB max)
  -> orders-premium-large (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn,
                maxMessageBatchSize 10, no trigger concurrency limit
       Process_order: calls child "process-order" with the order header (lines array emptied)
            Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 2, `maximumElasticWorkerCount` 20 |
| Service Bus | Premium, 1 MU; queue `orders` lock 5 min, max delivery 10, 5 GB, `maxMessageSizeInKilobytes` 10240 |
| Trigger | `maxMessageBatchSize` 10, `splitOn`, no `runtimeConfiguration.concurrency` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 10`, `prefetchCount = 0` |
| Load | 2 users x 1 engine x 1 message x 1/s = 2 msg/s for 10 min (1,200 messages), 10 min drain |
| Payloads | rotate 1,024 / 2,560 / 5,120 KB (`PAYLOAD_SIZES_KB`) |

The kit Bicep has no setting for the maximum message size, so `setup.ps1` recreates the
`orders` queue with `az servicebus queue create --max-message-size-in-kilobytes 10240`.

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 5b-premium-large
.\patterns\5b-premium-large\setup.ps1    # raises the queue maximum message size, purges the queue
.\scripts\Invoke-LoadTest.ps1    -Pattern 5b-premium-large
.\scripts\Export-Results.ps1     -Pattern 5b-premium-large
.\scripts\Set-PatternScale.ps1   -Pattern 5b-premium-large -Down
az servicebus namespace delete -g rg-msgpat-5b-premium-large -n <namespace>   # Premium bills hourly
```

The Premium namespace for the run was deleted after export. Run `Deploy-Pattern.ps1` and
`setup.ps1` again to recreate it.

## Results

Run `run-20261122-082900`: westus3, WS1, 2 msg/s for 10 min, then a 10 min drain. Export:
`results/5b-premium-large/run-20261122-082900/` (`summary.json`, CSVs, `throughput.png`,
`run-latency.png`, `e2e-latency.png`, `queue-backlog.png`, `instances.png`, `failures.png`).

| Metric | Value |
|---|---|
| Messages sent | 1,202 |
| Messages completed by the broker | 313 (860 still active at 08:59) |
| Peak `orders` backlog | 996 |
| Parent runs started / ended | 205 / 155 (all ended runs succeeded) |
| Run duration | p50 8.9 s, p95 842 s |
| End-to-end latency | p50 259 s, p95 1,065 s |
| Child runs ended | 155, p50 3.1 s, p95 23.3 s |
| Instances | 2 throughout |
| Memory working set (max per 5 min) | 0.9-1.7 GB until 08:30, then 2.65-2.72 GB |
| Failures | 0 failed actions, 0 dead letters, no size or memory errors |

The sample did not drain; `drainSeconds` (1,167) is from the first send to the last run end.

### Why

- Runs ended steadily (155 by 08:51) but at well under 2 msg/s, so the backlog grew. Once
  memory reached about 2.7 GB the run duration rose from seconds to minutes.
- No run hit a size limit. The Service Bus built-in trigger has no size check of its own
  (`ServiceBusWorkflowMessage.cs` builds the body without a limit), so the queue's
  `maxMessageSizeInKilobytes` is the only limit.
- Compared with 5a, 5b ended more than twice as many runs with lower latency, because there is
  no second read of the payload. Both reached the same memory plateau.

## Notes

- The `results` queue keeps the default Premium 1,024 KB limit.
- Smoke run `run-20261122-080948`: 129 runs succeeded, run p50 6.7 s, p95 12.0 s, end-to-end
  p50 226 s, p95 427 s. One run failed on `createArray()` before the fix to `json('[]')`.
- Cost: Premium 1 MU is about $0.93 an hour (about $677 a month), whatever the load.
- Queries: `queries/runs-by-workflow.kql`, `queries/actions-by-workflow.kql`,
  `queries/host-restarts.kql`, `queries/size-memory-errors.kql`, plus the kit queries in
  `scripts/queries/`.
