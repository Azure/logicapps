# 4-trickle: low, sporadic load

Load pattern 04. Traffic is low and irregular: one message every 1 to 30 seconds, with one idle
gap of several minutes. Throughput is not the concern here. The questions are:

- What latency does a single message see?
- What does the first message after an idle gap cost?
- How do stateful and stateless processing compare?
- What does always-ready (minimum instances) 1 on WS1 buy you?

## Design

- One Logic Apps Standard app with two workflows, each reading its own queue:
  - `trickle-stateful` reads `trickle-stateful`. It uses a `splitOn` Service Bus trigger and
    calls the shared `process-order` child.
  - `trickle-stateless` reads `trickle-stateless`. It is a stateless workflow. Stateless
    workflows reject `splitOn` (`PropertyNotAllowed`), so a `Foreach` loops over the trigger
    batch and calls `process-order` for each message.
- Both workflows set the tracked properties `messageId`, `enqueuedTimeUtc`, `sentAtUtc` and
  `pattern`.
- Each Locust task sends one message to each queue, then waits 1 to 30 seconds at random.
  Starting 240 seconds into the run, it sends nothing for 360 seconds.
- The built-in Service Bus trigger uses the Functions `serviceBusTrigger` binding, which is a
  long-receive listener. It has no polling interval
  (`ServiceBusServiceOperationsTriggerProvider.cs`).

## Settings

| Setting | Value |
|---|---|
| Region | westus3 |
| Plan | WS1, maximum burst 3, always-ready (minimum elastic instances) 1 |
| Service Bus | Standard, queues `trickle-stateful` and `trickle-stateless` |
| host.json | `maxMessageBatchSize` 10, `prefetchCount` 0 |
| Load | 1 Locust user, 15 minutes, `MIN_WAIT` 1, `MAX_WAIT` 30, `IDLE_GAP_START` 240, `IDLE_GAP` 360 |
| Drain | 3 minutes |

WS1 will not accept always-ready 0. ARM rejects the change with: "The desired
MinimumElasticInstanceCount (0) ... must be greater than zero" (ExtendedCode 01033).

## How to run

```powershell
.\scripts\Deploy-Pattern.ps1 -Pattern 4-trickle
.\scripts\Invoke-LoadTest.ps1 -Pattern 4-trickle
.\scripts\Export-Results.ps1 -Pattern 4-trickle
.\patterns\4-trickle\tools\Get-TrickleMetrics.ps1 -RunId <run-id> -StartUtc <start> -EndUtc <end>
.\scripts\Set-PatternScale.ps1 -Pattern 4-trickle -Down
```

- After a code-only redeploy, restart the app. In this run, the stateless listener did not
  start until the app was restarted.
- `Export-Results.ps1` reports only `measurement.workflowName` (stateful).
- `Get-TrickleMetrics.ps1` runs the queries in `queries\` for both workflows. It writes CSV and
  JSON files and `trickle-latency.png` to `results\4-trickle\<run-id>\custom`.

## Results (run-20261122-080600)

- 34 messages per queue (68 in total), about 0.04 messages per second per queue.
- The gap before the first message after idle was 375 seconds.
- All 68 runs succeeded and no messages were dead-lettered.
- The queue backlog never rose above 0, and the app ran on 1 instance throughout.

End-to-end latency is from send to run finish. "Steady" counts only messages sent 120 seconds
or less after the previous send.

| Workflow | p50 | p95 | max | steady p95 | After 375 s idle | First message after deploy |
|---|---|---|---|---|---|---|
| Stateful | 160 ms | 269 ms | 7836 ms | 195 ms | 232 ms | about 7.8 s |
| Stateless | 108 ms | 165 ms | 7846 ms | 126 ms | 165 ms | about 7.8 s |

Run duration (p50 / p95 / max):

- Stateful: 78 / 131 / 5635 ms.
- Stateless: 59 / 78 / 6350 ms.

## Findings

- With always-ready 1, a message that arrives after 6 idle minutes is processed almost as fast
  as a steady-state message: 232 ms against a 159 ms p50. The trigger does not poll, so it adds
  no polling delay.
- The only slow message was the first one after a deploy or restart, at about 7.8 seconds.
  Send a warm-up message after each deployment.
- For low volume, stateless is about 50 ms faster at p50 and about 70 ms faster at p95. It has
  no run history. A stateless workflow needs a `Foreach` instead of `splitOn`.
- On WS1 you cannot set always-ready to 0, so expect to pay for one instance at all times.
