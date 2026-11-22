# Pattern 12b: Mixed priority, one Logic App with per-workflow caps

## What it shows

Urgent and bulk messages arrive at the same time. Each priority has its own queue, and both
workflows run in one Logic App. A trigger concurrency cap on the bulk workflow keeps a bulk
burst from taking the host's capacity, so urgent latency stays flat. Without the cap, the
burst starves the urgent workflow.

## Flow

```
Locust (Azure Load Testing)
  1 user  -> queue "orders-high", 2 messages/s for 10 min
  5 users -> queue "orders-low",  12,000 messages in batches of 50, 180 s after the start

la-<base>  (plan asp-<base>, WS1, min 1, max 20)
  orders-high      (stateful): Service Bus receiveQueueMessages, splitOn, no cap
  orders-low       (stateful): same trigger on "orders-low", concurrency runs = 20  (default)
  orders-low-nocap (stateful): same trigger on "orders-low", no cap                 (baseline)
     each calls the shared child workflow "process-order"
```

Only one of `orders-low` and `orders-low-nocap` is enabled at a time. `tools\Set-Variant.ps1`
switches them with the `Workflows.<name>.FlowState` app settings.

## Design choices

- A queue per priority, not one topic with filters.
- The workflows are stateful. Stateless workflows reject `splitOn` and
  `runtimeConfiguration`, so "stateless, splitOn and high concurrency" cannot be deployed.
- The baseline is a separate workflow. You cannot remove trigger concurrency from a deployed
  workflow, so the uncapped variant needs its own workflow.
- Cap 20 runs. This is enough for 2.8 bulk messages/s on one WS1 instance and leaves CPU for
  the urgent workflow.

## Settings

| Setting | Value |
|---|---|
| Plan (`params.json`) | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 |
| Queues `orders-high`, `orders-low` | lock 5 min, max delivery 10, no sessions |
| Triggers | `maxMessageBatchSize` 100, `splitOn`; `orders-low` `runtimeConfiguration.concurrency.runs` 20 |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load (`loadTest.env`) | `HIGH_USERS` 1, `LOW_USERS` 5, `LOW_BATCH_SIZE` 50, `BURST_START_SEC` 180, `BURST_MESSAGES` 12000 |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1                            -Pattern 12b-per-workflow-caps
.\patterns\12b-per-workflow-caps\tools\Set-Variant.ps1  -Pattern 12b-per-workflow-caps -Variant capped   # or nocap
.\patterns\12b-per-workflow-caps\tools\Reset-Queue.ps1
.\scripts\Invoke-LoadTest.ps1                           -Pattern 12b-per-workflow-caps
.\patterns\12b-per-workflow-caps\tools\Run-Queries.ps1  -Pattern 12b-per-workflow-caps -RunId <id> -StartUtc <start> -EndUtc <end>
.\patterns\12b-per-workflow-caps\tools\Get-Metrics.ps1  -Pattern 12b-per-workflow-caps -RunId <id> -StartUtc <start> -EndUtc <end>
.\scripts\Export-Results.ps1                            -Pattern 12b-per-workflow-caps -RunId <id> -StartUtc <start> -EndUtc <end>
.\scripts\Set-PatternScale.ps1                          -Pattern 12b-per-workflow-caps -Down
```

For the baseline, set `measurement.lowWorkflowName` in `params.json` to `orders-low-nocap`.

Points to watch:

- `Set-Variant` changes app settings, which restarts the host. Wait until the host is back
  (about 10 minutes in one run, with a gap in Application Insights) before you start a test.
- Set `StartUtc` to the load test start. The queries keep only messages sent after it, so
  leftover messages from an earlier run do not mix in. Export-Results has no such filter, and
  its `summary.json` can include older messages.
- End the window after the bulk drain: about 70 minutes after the burst with the cap, about
  20 minutes without it. An empty queue does not mean the runs are done; the host still
  holds the run backlog.
- Export-Results covers only `orders-high`; `queries\*.kql` cover both workflows.

## Results

Files are in `results/12b-per-workflow-caps/<RunId>/`: charts (`throughput.png`,
`e2e-latency.png`, `run-latency.png`, `queue-backlog.png`, `instances.png`, `failures.png`)
and query output in `custom/`.

### Capped (RunId `capped`, run `run-20261122-103953`)

Burst sent at 10:45:39 UTC; last bulk run finished at 11:56:04.

| Phase | Messages | p50 ms | p95 ms | p99 ms | Max ms |
|---|---|---|---|---|---|
| Urgent, before burst | 362 | 1,615 | 2,088 | 2,232 | 2,312 |
| Urgent, during burst and drain | 840 | 1,532 | 2,128 | 2,849 | 3,212 |

Bulk drain: 12,000 messages in 4,225 s (2.8 msg/s). Bulk end-to-end p50 2,083 s, p95 4,005 s.

### Uncapped baseline (RunId `nocap2`, run `run-20261122-122649`)

Test start 12:26:49 UTC; burst sent 12:32:41 to 12:32:52; last bulk run finished at 12:52:02.

| Phase | Messages | p50 ms | p95 ms | p99 ms | Max ms |
|---|---|---|---|---|---|
| Urgent, before burst | 362 | 1,693 | 2,119 | 2,470 | 2,663 |
| Urgent, during burst and drain | 840 | 511,464 | 861,204 | 908,181 | 935,386 |

Bulk drain: 12,000 messages in 1,161 s (10.3 msg/s). Bulk end-to-end p50 641 s, p95 1,114 s.
The orders-low queue was empty by 12:38:42, but the runs finished 13 minutes later.

RunId `nocap` is not valid: the host restarted after `Set-Variant` during the test.

### Resources (test start to drain end)

| Variant | Instances | Instance-minutes | App memory avg / max | Plan CPU avg / max | Plan memory avg / max |
|---|---|---|---|---|---|
| Capped | 1 | 75 | 153 / 231 MB | 23.5% / 87% | 52% / 56% |
| Uncapped | 1 | 27 | 421 / 731 MB | 83.7% / 100% | 60% / 68% |

### Findings

- The cap protects urgent work: urgent p95 moved from 2,088 to 2,128 ms during the burst.
- Without the cap, the burst starves urgent work in the same app: urgent p50 rose from 1.7 s
  to 511 s, and the maximum to 15.6 minutes, while CPU ran at 100%.
- The plan did not scale out in either variant. With the cap, CPU stays low enough that the
  scaler never adds an instance, so the drain takes 70 minutes and 75 instance-minutes. A
  plan maximum above 1 does not help a capped workflow.
- The cost of the cap is drain time. Raise the cap, or split the bulk work into its own app
  (pattern 12a: 19-minute drain, 31 instance-minutes for two apps, flat urgent latency).
