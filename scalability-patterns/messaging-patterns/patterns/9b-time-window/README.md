# Pattern 9b: Fan-in over a fixed time window

## What it shows

How a Logic Apps Standard workflow collects the messages that arrive in a fixed time window
and writes them as one aggregate, using the docs "timed receive" design: a Recurrence trigger
that drains a plain Service Bus queue with peek-lock receive. The workflow writes one Cosmos
document per window that lists every item id; `check-windows.py` then counts missing and
duplicate items across all windows.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 10, itemId = <tag>-<user>-<seq>-->
  queue "items" (no sessions, lock 5 min)
  -> items-time-window (stateful)
       trigger: Recurrence every 1 minute, concurrency 1
       Until (count == 0, or 30 calls, or 40 s elapsed):
            Get_messages (V2 built-in, peek-lock, maxMessages 100)
            append the messages to the window
       Write_window (Cosmos upsert, one doc per window with every itemId, sentAtUtc, lockToken)
       Complete_each (concurrency 50): Complete_message (lock token)
```

The workflow completes the messages only after the window document is written. If the run
fails before the completes, the locks expire and Service Bus redelivers the messages into a
later window. One window holds at most 30 x 100 = 3,000 items.

## Settings

| Setting | Value |
|---|---|
| Region | westus3 |
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 (`params.json`) |
| Service Bus | Standard; queue `items`: sessions off, lock 5 min, max delivery 5, 5 GB |
| Trigger | Recurrence, 1 minute, `runtimeConfiguration.concurrency.runs` 1 |
| Receive | V2 `Get messages from a queue`, peek-lock, 100 per call; Until stops at 0 messages, 30 calls or 40 s |
| Complete | For each, concurrency 50, one `Complete the message` per lock token |
| host.json | `extensions.serviceBus`: `maxMessageBatchSize` 100, `prefetchCount` 0, `tryTimeout` 00:00:05 |
| trackedProperties | `pattern` only (see Notes) |
| Load | 10 users x 10 messages x 0.2/s = 20 msg/s for 10 min |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 9b-time-window
.\patterns\9b-time-window\tools\Reset-Queue.ps1 -Pattern 9b-time-window
.\scripts\Invoke-LoadTest.ps1    -Pattern 9b-time-window
.\scripts\Export-Results.ps1     -Pattern 9b-time-window -RunId <runId> -StartUtc <start> -EndUtc <end>
.\patterns\9b-time-window\tools\Run-Queries.ps1 -Pattern 9b-time-window -RunId <runId> -StartUtc <start> -EndUtc <end>
& "C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe" .\patterns\9b-time-window\tools\check-windows.py <cosmosEndpoint> <start> <end> windows.json --expected <sent>
.\scripts\Set-PatternScale.ps1   -Pattern 9b-time-window -Down
```

`tools\send-items.py` sends a few items by hand for smoke tests.

## Results

Run `run-20261122-111719`: load 11:17:23Z to 11:32:35Z, queue empty at 11:39Z, measured
until 11:43Z.

| Metric | Value |
|---|---|
| Messages sent / completed | 12,100 / 12,100, 0 send errors |
| Runs succeeded / failed | 12 / 0; 0 failed actions |
| Windows with items | 5 (mean 2,420 items, max 3,000 = the cap) |
| Missing / gap / duplicate / redelivered items | 0 / 0 / 0 / 0 |
| Aggregated throughput | 13.22 items/s (first write 11:21:39Z, last 11:36:54Z) |
| Latency item send to window write, p50 / p95 / max | 193.7 / 431.6 / 461.6 s |
| Latency first item of window to write, p50 / max | 263.7 / 461.6 s |
| Run duration p50 / p95 / max | 32.3 / 223.7 / 223.7 s |
| Full window runs | 137 to 224 s; empty runs about 32 s |
| Max instances | 1 |
| Peak queue backlog | 5,607 at 11:31; DLQ 0 |
| Memory working set | max 781 MB, average 238 MB |
| Action durations | Get_messages p50 32 ms, p95 30 s (long poll on empty queue); Complete_message (12,100 calls) p50 546 ms, p95 1,217 ms; Write_window p50 459 ms, p95 2,634 ms |

Findings:

- Every item landed in exactly one window. Complete after the write and keep the lock
  duration longer than the time to build and write a window.
- The window cap and the per-message completes set throughput, not the trigger. A full
  window of 3,000 items took about 220 s, almost all of it in 3,000 single completes at
  concurrency 50. With trigger concurrency 1, the next recurrence waits for that run, so
  "every minute" became every 4 minutes and the backlog grew to 5,607. At 20 msg/s input
  the sample drained about 13 msg/s.
- Output lag is therefore not one window. p95 lag from send to write was 432 s. Size the
  cap above the arrival rate per window, raise the complete concurrency, or use receive
  and delete if at-least-once settlement is not needed.
- An empty window still costs a run of about 32 s because the last
  `Get messages` call long-polls for 30 s before it returns 0.
- The app stayed on one instance; a Recurrence workflow does not scale with queue backlog.

Charts: `results\9b-time-window\run-20261122-111719\*.png`. Window report: `windows.json`.
`summary.json` reports the peak backlog as 18,100 because the 11:17 metric bucket still
held messages from the failed run below before the purge; the real peak was 5,607. Its msg/s
and end-to-end latency fields are wrong for this pattern; use `windows.json`.

## Queries

App Insights queries in `queries\` (Run-Queries.ps1 fills in the parameters; filled copies
are in the run folder under `queries\`, results under `custom\`):

- `01-action-outcomes.kql`: action counts by name and status.
- `02-window-run-duration.kql`: window run count, failures and duration percentiles.
- `03-per-minute-settles.kql`: receive calls, completes and window writes per minute.
- `04-instances-per-minute.kql`: instances per minute.

## Notes

- The first run `run-20261122-105220` used trackedProperties that read message fields. The
  property evaluation failed after `Write_window`, so the run failed before its completes.
  The locks expired and Service Bus redelivered the messages into later windows: 2,900
  missing and 15,090 duplicate items (`windows-failed-tracked.json`). Anything that can fail
  after the write and before the completes produces duplicates; make the window write
  idempotent per item, or dedupe downstream.
- The Logic Apps Standard built-in Service Bus connector has no batch trigger; this sample
  uses Recurrence plus peek-lock receive.
- Sliding windows were not tested.
