# Pattern 7: Long-running work per message

Docs page: `load-pattern-07-long-running.md`.

## What it shows

Each message starts about three minutes of work. The sample compares two ways to keep the
message from being lost or delivered twice while that work runs:

1. **Settle early (recommended).** A Stateful workflow with a `splitOn` Service Bus trigger takes
   the message from `orders-early` and settles it at once. The run then owns the work: it waits
   three minutes and calls `Process_order`. Run history in storage is the durable record.
2. **Hold the lock.** A Stateless workflow takes a batch of up to 20 messages from `orders-lock`
   in peek-lock mode. For each message it makes four 40-second HTTP calls to a Stateful
   `slow-downstream` workflow and renews the lock after each call. It then completes the message,
   or abandons it on failure. The queue lock is one minute, so the run must renew it.

## Flow

```text
Settle early (long-running-settle-early, Stateful)
  orders-early --splitOn trigger (message settled)--> Wait 3 min --> Process_order

Hold the lock (long-running-peeklock-stateless, Stateless)
  orders-lock --peek-lock batch (<=20)--> For_each (concurrency 20)
     4 x [ HTTP POST slow-downstream (Wait 40 s) --> Renew_lock ]
     --> Process_order --> Complete_message  (Abandon_message on failure)
```

## Settings (`params.json`)

| Setting | Value | Why |
|---|---|---|
| Plan | WS1, min 1, max 20 workers | Shared kit default. |
| Service Bus | Standard | Lock duration up to 5 minutes. |
| `orders-early` | lock PT5M, max delivery 10 | Lock only matters until the trigger settles it. |
| `orders-lock` | lock PT1M, max delivery 10 | Forces the run to renew the lock. |
| `host.json` | `maxMessageBatchSize` 20, `prefetchCount` 0, `maxAutoLockRenewalDuration` 00:05:00 | No prefetch, so messages do not sit locked in a buffer. |
| `loadTest` | `orders-early`, 2 msgs x 1/s for 5 min | Run 1. Run 2 used `orders-lock`, 1 msg x 1/s for 3 min. |
| `drainMinutes` | 8 | Long runs need time to finish. |
| `measurement.workflowName` | `long-running-settle-early` | Workflow that `Export-Results.ps1` reads. |

`Invoke-LoadTest.ps1` has no queue switch. To repeat run 2, set `loadTest.queueName` to
`orders-lock`, `batchSize` 1, `durationMinutes` 3 and `measurement.workflowName` to
`long-running-peeklock-stateless`, then restore the values.

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 7-long-running
.\scripts\Invoke-LoadTest.ps1    -Pattern 7-long-running            # defaults from params.json
.\scripts\Export-Results.ps1     -Pattern 7-long-running -RunId <runId>
.\patterns\7-long-running\Measure-Run.ps1 -RunId <runId> -StartUtc <start> -EndUtc <end>
.\scripts\Set-PatternScale.ps1   -Pattern 7-long-running -Down
```

`Measure-Run.ps1` runs the queries in `queries\` (action status, in-flight runs, delivery count,
end-to-end latency by workflow, instances) and pulls memory and dead-letter metrics into
`results\7-long-running\<runId>\pattern7\`.

## Results

Both runs: westus3, WS1, Service Bus Standard. Charts are in `results/7-long-running/<runId>/`.

| Metric | Run 1: settle early | Run 2: hold the lock |
|---|---|---|
| Run id | `run-20261122-105441` | `run-20261122-111837` |
| Load | 2 msg/s, 5 min (602 msgs) | 1 msg/s, 3 min (181 msgs) |
| Runs | 602 succeeded, 0 failed | 10 batch runs, 181 messages, all succeeded |
| Run duration p50 / p99 | 181.9 s / 182.0 s | 177.0 s / 186.6 s |
| End-to-end p50 / p95 / p99 | 182.5 s / 183.0 s / 183.1 s | 443.6 s / 527.8 s / 540.8 s |
| Peak runs in flight | 364 | 5 runs (up to 100 locked messages) |
| Peak queue backlog | 0 | 180 |
| Redelivered (deliveryCount > 1) | 0 | 0 |
| Lock renewals | n/a | 724, all succeeded |
| Dead letters | 0 | 0 |
| Max instances | 2 | 5 |
| Max worker memory | about 317 MB | about 327 MB |

- Settling early let the app accept 2 msg/s while 364 runs waited at once on two workers. The
  queue never backed up, and end-to-end latency was the three-minute wait plus about one second.
- Holding the lock also lost nothing: no lock was lost, no message came back, and 724 renewals
  succeeded. But each Stateless run held its batch for about three minutes, so throughput fell
  to about 0.26 msg/s. Messages waited up to seven minutes in the queue before a run took them.
- The broker `CompletedMessages` metric showed 141 of 181 at export time. `Complete_message`
  succeeded 181 times and the queue was empty afterwards, so the metric lagged.

## Notes

- **Stateful peek-lock needs VNet private ports.** A Stateful workflow that completes or renews
  a peek-lock message fails with `VNetPrivatePortsNotConfigured` unless the app has VNet
  integration with `vnetPrivatePortsCount` of 2 or more (`ServiceProviderActionJob.cs`).
  Without it the lock lapsed and the message came back about once a minute (delivery count 6).
  That is why the hold-the-lock design here is Stateless.
- **Stateless runs stop at 5 minutes** (`Runtime.FlowRunTimeout` in `Flow.Web.Edge`
  `AppSettings.xml`). Stateful runs can last 90 days. A Stateless run cannot hold a lock for
  longer than 5 minutes however often it renews it.
- **Stateless workflows reject `Wait`** (`WorkflowRunActionTypeUnsupported`), and the
  built-in Workflow action from a Stateless parent to a Stateful child returns 202 at once.
  The sample calls the child's callback URL over HTTP so that the call blocks.
- **HTTP calls time out at 3 min 45 s** (`HttpOperation.RequestTimeout`). Raise it for slower
  calls, or use the async 202 polling or webhook pattern.
- A workflow cannot change from Stateful to Stateless in place (`InvalidFlowKind`). Use a new name.
- `maxAutoLockRenewalDuration` comes from the WebJobs Service Bus extension, not from Logic Apps
  code. It covers only the time the host holds the lock. The explicit `Renew_lock` action calls
  `RenewMessageLockAsync` in `ServiceBusServiceOperationsProvider.cs`.
