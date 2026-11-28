# Pattern 6a: Strict order per key with Service Bus sessions

## What it shows

How a Logic Apps Standard workflow processes messages in order per key with a
session-enabled Service Bus queue, and what that order costs in throughput. Each key is a
session. Each run handles one batch from one session, writes the messages to Cosmos one at a
time, and records when it processed each one. A checker then counts ordering violations per key.

## Which workflow to use

The recommended design is `reference\orders-strict-order-session`. It uses the session trigger
**On new messages from queue session** (`onNewMessagesFromQueueSession`), a sequential For each,
and the session actions to complete or dead-letter each message and close the session.

The session actions must run on the instance that holds the session. The app routes them there
over its private ports, so the app needs VNet integration and `vnetPrivatePortsCount` set to 2 or
more. Without them, the actions fail with HTTP 400 `VNetPrivatePortsNotConfigured`.

The test app had no VNet integration, so the measured workflow, `orders-strict-order-fn`, uses the
**When messages are available in a queue** (`receiveQueueMessages`) trigger on the session queue
instead. That trigger settles each batch itself, so the workflow has no settle or close actions.
The results below come from this workflow.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 5, sessionId = key--> queue "orders" (sessions)
  -> orders-strict-order-fn (stateless)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity),
                isSessionsEnabled true, maxMessageBatchSize 50, no splitOn
       For_each_message_in_order (concurrency 1 = sequential):
            Upsert_order (Cosmos, id "<key>-<seq>", pk "<key>", processedAtUtc = utcNow())
```

Each message carries `key`, `seq` (1, 2, 3, ... per key) and `sentAtUtc`. Locust sends the
messages for a key from one user, so the queue receives them in sequence order. The trigger
completes the batch after the run; a failed run abandons it, and the session moves on only
when the batch is settled.

## Settings

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 (`params.json`) |
| Queue `orders` | sessions on, lock 1 min, max delivery 5, 5 GB |
| Trigger | `receiveQueueMessages`, `isSessionsEnabled` true, `maxMessageBatchSize` 50 |
| host.json | `extensions.serviceBus`: `maxMessageBatchSize` 50, `prefetchCount` 0 |
| Load | 20 users x 5 messages x 1 batch/s = 100 msg/s for 5 min over 100 keys (session ids) |

Run 2 also set `maxConcurrentSessions` to 32 in host.json. It made no difference, because the
trigger receives batches and that setting limits only single-message handling, so the sample
no longer sets it. The session trigger in `reference\` polls on its recurrence and reads only
`maxMessageBatchSize` from host.json.

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 6a-strict-order
az webapp restart ...            # restart after a code-only deploy, or the listener may not start
.\patterns\6a-strict-order\tools\Reset-Queue.ps1 -Pattern 6a-strict-order
.\scripts\Invoke-LoadTest.ps1    -Pattern 6a-strict-order
.\scripts\Export-Results.ps1     -Pattern 6a-strict-order -RunId <runId> -StartUtc <start> -EndUtc <end>
.\patterns\6a-strict-order\tools\Run-Queries.ps1 -Pattern 6a-strict-order -RunId <runId> -StartUtc <start> -EndUtc <end>
& "C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe" .\patterns\6a-strict-order\tools\check-ordering.py <cosmosEndpoint> <start> <end> ordering.json
.\scripts\Set-PatternScale.ps1   -Pattern 6a-strict-order -Down
```

`check-ordering.py` adds `.tools\pylib` and `.tools\pylib-cosmos` to `sys.path` itself,
because the Azure CLI Python ignores `PYTHONPATH`. For each key it sorts the Cosmos documents by
`processedAtUtc` and counts sequence inversions, gaps and redelivered messages.

## Results

Same load for both runs: about 30,090 messages at 100 msg/s for 5 minutes, 100 keys.

| Metric | Run 1 (`run-20261122-085556`) | Run 2 (`run-20261122-093052`) |
|---|---|---|
| Messages sent | 30,090 | 30,085 |
| Peak queue backlog | 29,789 | 28,681 |
| Runs succeeded / failed | 984 / 0 | 860 / 0 |
| Throughput, whole window | 21.65 msg/s | 20.49 msg/s |
| Throughput, steady state | about 27 msg/s | about 27 msg/s |
| Run duration p50 / p95 | 789 / 974 ms | 783 / 1,011 ms |
| End-to-end latency p50 / p95 | 689 / 1,210 s | 597 / 1,040 s |
| Max instances | 1 | 1 |
| Drain (first send to last run end) | 1,390 s | 1,202 s (window closed; 5,905 left and purged) |
| Ordering violations | 0 | 0 inversions, 0 gaps, 0 redelivered |

Findings:

- Order held: zero ordering violations across all 100 keys in both runs.
- Setting `maxConcurrentSessions` did not change throughput. With one instance the cost is the
  sequential Cosmos upserts (about 15 ms each) plus the per-run overhead, so the app tops out
  near 27 msg/s.
- The app never scaled past one instance, though the queue held about 29,000 messages.
  To scale out on Service Bus backlog, the app needs a maximum instance count and runtime scale
  monitoring turned on. This test app had neither. Sessions then spread across instances.
- Throughput is capped per key: one key is never processed by two runs at once. With few hot
  keys, the run time per batch sets the ceiling for that key.

Charts: `results\6a-strict-order\run-*\*.png`. Ordering reports:
`results\6a-strict-order\ordering-run-*.json`.

## Queries

App Insights queries in `queries\` (Run-Queries.ps1 fills in the parameters):

- `timeline-per-minute.kql`: runs, Cosmos upserts and instances per minute.
- `messages-per-run.kql`: messages per run (batch size actually received).
- `runs-per-second.kql`: run starts per second.
- `actions-by-status.kql`: action counts by status.

The kit queries in `scripts\queries\` give throughput, run duration, end-to-end latency and
instance counts.

## Notes

- Do not set `splitOn` on a session trigger. A stateless workflow rejects `splitOn`, and the
  runtime rejects `splitOn` together with Service Bus consumer actions (400 PropertyNotAllowed).
- Keep `maxMessageBatchSize` at 100 or less in a stateless workflow. A stateless For each
  allows 100 items by default; a larger batch fails the run and dead-letters the messages
  (see 6b).
- `reference\orders-strict-order-session` needs VNet integration and private ports. See
  [Which workflow to use](#which-workflow-to-use).
