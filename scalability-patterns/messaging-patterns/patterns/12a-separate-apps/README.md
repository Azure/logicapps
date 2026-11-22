# Pattern 12a: Mixed priority, separate Logic Apps

## What it shows

Urgent and bulk messages arrive at the same time. Each priority has its own queue, and each
queue has its own Logic App on its own plan. A large bulk burst can use all of the bulk app's
CPU, but it cannot take capacity from the urgent app.

## Flow

```
Locust (Azure Load Testing)
  1 user  -> queue "orders-high", 2 messages/s for 10 min
  5 users -> queue "orders-low",  12,000 messages in batches of 50, 180 s after the start

la-<base>-hi  (plan asp-<base>-hi, WS1, max 5)
  orders-high (stateful): Service Bus receiveQueueMessages, splitOn, no concurrency cap
     Process_order: shared child workflow "process-order"

la-<base>     (plan asp-<base>,    WS1, max 10)
  orders-low  (stateful): Service Bus receiveQueueMessages, splitOn, no concurrency cap
     Process_order: shared child workflow "process-order"
```

Both apps share the storage account, managed identity, Service Bus namespace, Cosmos DB and
Application Insights. Queries split the two apps by `cloud_RoleName`.

## Design choices

- A queue per priority, not one topic with filters. The load test sends to each queue
  directly, and each app listens to one queue.
- The workflows are stateful. Stateless workflows reject `splitOn` and
  `runtimeConfiguration`, so the docs suggestion of "stateless, splitOn and high concurrency"
  for the bulk app cannot be deployed.
- No concurrency cap on either app, because isolation already protects the urgent work.

## Settings

| Setting | Value |
|---|---|
| Bulk plan (`params.json`) | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 10 |
| Urgent plan (`params.json` `highApp`) | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 5 |
| Queues `orders-high`, `orders-low` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Triggers | `maxMessageBatchSize` 100, `splitOn` |
| host.json (both apps) | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load (`loadTest.env`) | `HIGH_USERS` 1, `LOW_USERS` 5, `LOW_BATCH_SIZE` 50, `BURST_START_SEC` 180, `BURST_MESSAGES` 12000 |

## Run

The kit deploys one Logic App per pattern. `setup.ps1` adds the urgent app and its plan with
the kit's `logicapp.bicep` module, creates the content file share that the module needs, and
zip-deploys `app-high\`.

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1                      -Pattern 12a-separate-apps
.\patterns\12a-separate-apps\setup.ps1
.\patterns\12a-separate-apps\tools\Reset-Queue.ps1
.\scripts\Invoke-LoadTest.ps1                     -Pattern 12a-separate-apps
.\patterns\12a-separate-apps\tools\Run-Queries.ps1 -Pattern 12a-separate-apps -RunId <id> -StartUtc <start> -EndUtc <end>
.\patterns\12a-separate-apps\tools\Get-Metrics.ps1 -Pattern 12a-separate-apps -StartUtc <start> -EndUtc <end>
.\scripts\Export-Results.ps1                      -Pattern 12a-separate-apps -RunId <id> -StartUtc <start> -EndUtc <end>
.\scripts\Set-PatternScale.ps1                    -Pattern 12a-separate-apps -Down
.\patterns\12a-separate-apps\setup.ps1 -Down
```

Set the query window to end after the bulk queue drains; the bulk runs finish about 19
minutes after the burst. Export-Results covers only `orders-high`; the queries in
`queries\*.kql` cover both workflows.

## Results

Run `run-20261122-111159` (RunId `separate`), westus3, 11:12–11:36 UTC. The burst was sent
from 11:17:48 to 11:17:57. Files are in `results/12a-separate-apps/separate/`: charts
(`throughput.png`, `e2e-latency.png`, `run-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`) and query output in `custom/`.

Urgent end-to-end latency (send to child workflow end), 1,202 messages, none failed:

| Phase | Messages | p50 ms | p95 ms | p99 ms | Max ms |
|---|---|---|---|---|---|
| Before burst | 362 | 1,551 | 2,095 | 2,201 | 2,233 |
| During burst and drain | 840 | 1,651 | 2,110 | 2,189 | 2,273 |

Bulk drain: 12,000 messages, sent in 11 s, last run finished at 11:36:23, so the drain took
1,115 s (10.8 msg/s). Bulk end-to-end p50 664 s, p95 1,072 s.

| Resource | Instances | Instance-minutes | Memory avg / max | CPU avg / max |
|---|---|---|---|---|
| Urgent app and plan | 1 | 11 | 53 / 151 MB (plan 51% / 55%) | 5.8% / 16% |
| Bulk app and plan | 1 | 20 | 289 / 643 MB (plan 58% / 66%) | 67% / 99% |
| Total | 2 | 31 | | |

### Findings

- Isolation works: urgent p95 moved from 2,095 to 2,110 ms and the maximum from 2,233 to
  2,273 ms while the bulk plan ran at 99% CPU.
- The bulk plan did not scale out. It stayed on 1 instance at full CPU for the whole drain.
  To drain faster, raise `minimumElasticInstanceCount` on the bulk plan before a known burst.
- Two plans cost at least two always-ready instances. When the urgent rate is low, the urgent
  plan stays nearly idle (6% CPU).
