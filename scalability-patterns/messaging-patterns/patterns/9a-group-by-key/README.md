# Pattern 9a: Fan-in, group by key with Service Bus sessions

## What it shows

How a Logic Apps Standard workflow collects all messages that share a key (all line items of
one order) with a session-enabled Service Bus queue, and what the session settings cost in
throughput. The session id is the order id, so one run receives the lines of one order
together. The workflow writes one part document per line to Cosmos; `check-groups.py` then
rebuilds each order from Cosmos and counts missing and duplicate lines.

The workflow `orders-group-literal` is the stateful design from the docs page (session
polling trigger, Until loop that gets messages from the session, complete, close session).
It was smoke-tested only; see Notes.

## Flow

```
Locust (Azure Load Testing) --sendMessages, one batch of 10 lines per order, sessionId = orderId-->
  queue "orders" (sessions)
  -> orders-group-by-key (stateless)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity),
                isSessionsEnabled true, maxMessageBatchSize 50, no splitOn
       For_each_line (concurrency 20):
            Write_part (Cosmos upsert, pk = orderId, one doc per line with
                        lineNo, lineCount, messageId, deliveryCount, runId, sentAtUtc, processedAtUtc)
```

Each line message carries `orderId`, `lineNo` (1..10), `lineCount` (10) and the order's send
time `sentAtUtc`. The trigger completes the batch after a successful run and abandons it after
a failed run. An order is complete when Cosmos holds exactly one document for each of its
10 line numbers.

## Settings

| Setting | Value |
|---|---|
| Region | westus3 |
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 (`params.json`) |
| Service Bus | Standard; queue `orders`: sessions on, lock 5 min, max delivery 5, 5 GB |
| Trigger | `receiveQueueMessages`, `isSessionsEnabled` true, `maxMessageBatchSize` 50 |
| host.json | `extensions.serviceBus`: `maxMessageBatchSize` 50, `prefetchCount` 0, `maxConcurrentSessions` 32, `sessionIdleTimeout` 00:00:05 |
| Override during the run | From 11:10:36Z, app setting `AzureFunctionsJobHost__extensions__serviceBus__sessionIdleTimeout` = `00:00:01` (removed at closeout) |
| Load | 20 users x 1 order (10 lines) x 0.25/s = 50 msg/s (5 orders/s) for 10 min |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 9a-group-by-key
.\patterns\9a-group-by-key\tools\Reset-Queue.ps1 -Pattern 9a-group-by-key
.\scripts\Invoke-LoadTest.ps1    -Pattern 9a-group-by-key
.\scripts\Export-Results.ps1     -Pattern 9a-group-by-key -RunId <runId> -StartUtc <start> -EndUtc <end>
.\patterns\9a-group-by-key\tools\Run-Queries.ps1 -Pattern 9a-group-by-key -RunId <runId> -StartUtc <start> -EndUtc <end>
& "C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe" .\patterns\9a-group-by-key\tools\check-groups.py <cosmosEndpoint> <start> <end> groups.json
.\scripts\Set-PatternScale.ps1   -Pattern 9a-group-by-key -Down
```

`check-groups.py` selects orders by `sentAtUtc`, groups the part documents by `orderId` and
reports, per order, missing and duplicate line numbers, the number of runs that wrote it,
and the latency from the order's send time to its last part write. `tools\send-orders.py`
sends a few orders by hand for smoke tests.

## Results

Run `run-20261122-103449`: load 10:34:49Z to 10:44:49Z, measured until 11:19Z.

| Metric | Value |
|---|---|
| Messages sent | 30,200 (3,020 orders), 0 send errors |
| Runs succeeded / failed | 325 / 0 in the export window (10:34 to 11:06) |
| Run duration p50 / p95 / p99 | 102 / 116 / 152 ms |
| Max instances | 1 |
| Peak queue backlog | 28,980; DLQ 0 |
| Memory working set | max 311 MB, average 114 MB |
| Orders checked in Cosmos (sends 10:34 to 11:07, read at 11:20) | 731 orders, 7,310 lines |
| Missing / duplicate lines | 0 / 0; every order written by exactly one run |
| Aggregated throughput | 2.97 msg/s (first part 10:37:56, last 11:18:54) |
| Latency first send to group written, p50 / p95 / max | 1,835 / 2,279 / 2,315 s (queue wait dominates) |
| Backlog drain, `sessionIdleTimeout` 5 s | about 120 msg/min (2 msg/s), 10:50 to 11:11 |
| Backlog drain, `sessionIdleTimeout` 1 s | about 500 msg/min (8.4 msg/s), 11:13 to 11:18 |

About 22,470 messages were still in the queue at 11:19:45Z. `Reset-Queue.ps1` recreated the
queue and dropped them; the completeness check covers only the orders that were processed.

Findings:

- Grouping is correct: no missing or duplicate lines in any processed order, and each order
  arrived in a single run, because a session batch holds all lines of the order.
- Throughput is set by the session settings, not by the work. A run takes about 100 ms, but
  after each order the receiver waits `sessionIdleTimeout` for more messages in that session
  before it releases the session. With 5 s and 10 lines per order the app drains about
  2 msg/s; with 1 s, about 8.4 msg/s. With short sessions, set `sessionIdleTimeout` low and
  `maxConcurrentSessions` high.
- The app stayed on one instance with a 29,000-message backlog. Logic Apps Standard scales on
  its own job queue, not on Service Bus backlog.
- Group latency here is queue wait: the producer sent 50 msg/s and the consumer drained 2 to
  8 msg/s.

Charts: `results\9a-group-by-key\run-20261122-103449\*.png`. Group reports: `groups.json`
(sends 10:34 to 10:51) and `groups-all-1120.json` (sends 10:34 to 11:07). Backlog per minute
with the idle timeout in force: `idle-timeout-backlog.csv`. The kit's end-to-end latency and
msg/s fields in `summary.json` are wrong for this pattern; use the group reports.

## Queries

App Insights queries in `queries\` (Run-Queries.ps1 fills in the parameters; filled copies
are in the run folder under `queries\`):

- `timeline-per-minute.kql`: runs, Cosmos writes and instances per minute.
- `messages-per-run.kql`: messages per run (batch size actually received).
- `runs-per-second.kql`: run starts per second.
- `actions-by-status.kql`: action counts by status.

## Notes

- The docs-literal workflow `orders-group-literal` failed at its first session operation
  with HTTP 400 `VNetPrivatePortsNotConfigured`: "Using this service provider action in
  stateful workflows requires VNet integration and the site configuration
  vnetPrivatePortsCount to be set to a value greater than or equal to 2." Evidence:
  `literal-smoke-error.json` and `literal-smoke-actions.json`. The built-in session
  operations in a stateful workflow need VNet integration and private ports. The measured
  workflow uses the session trigger instead, which needs neither.
- Do not set `splitOn` on a session trigger; a stateless workflow rejects it.
- Keep `maxMessageBatchSize` at 100 or less in a stateless workflow (For each limit).
- Each order fits in one batch here (10 lines, batch 50). If an order can exceed the batch
  size or arrive over time, store the parts outside the run (as this sample does in Cosmos)
  and assemble the group when the count reaches `lineCount`.
