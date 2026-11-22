# Pattern 6b: Latest wins per key without sessions

## What it shows

How to keep only the newest version of each key when messages are processed in parallel and
may arrive out of order. The queue has no sessions. Each message reads the key's current
document, compares sequence numbers, and replaces the document with an ETag (`If-Match`) only
when its sequence number is newer. Stale updates are skipped, and a lost ETag race retries.

It uses the same keys and load as pattern 6a (`..\6a-strict-order`), so the two samples
compare the cost of strict order with the cost of latest-wins.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 5--> queue "orders" (no sessions)
  -> orders-latest-wins-fn (stateless)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity),
                maxMessageBatchSize 50, no splitOn
       For_each_message (concurrency 50):
            Arrived (utcNow)
            Apply_if_newer (Until outcome != "retry", max 10 tries, 2 min):
                 Read_latest  (Cosmos doc "latest-<key>")
                   404 -> Create_latest (create only; 409 = another message won -> retry)
                   found -> Is_newer: seq > stored seq ?
                              yes -> Replace_latest (upsert with If-Match = stored _etag;
                                                     412 = changed since read -> retry)
                              no  -> outcome "stale" (skip)
            Write_arrival (doc "arr-<key>-<seq>": arrival time, outcome, attempts)
```

Failed `Read_latest` (404), `Create_latest` (409) and `Replace_latest` (412) actions are
expected and handled; the runs still succeed.

## Settings

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 (`params.json`) |
| Queue `orders` | no sessions, lock 1 min, max delivery 5, 5 GB |
| Trigger | `receiveQueueMessages`, `isSessionsEnabled` false, `maxMessageBatchSize` 50 |
| For each | concurrency 50 |
| host.json | `extensions.serviceBus.maxMessageBatchSize` 50 |
| Load | 20 users x 5 messages x 1 batch/s = 100 msg/s for 5 min over 100 keys |

Run 2 set the batch size to 250 in both the trigger and host.json. The files are back at 50
(see Results).

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 6b-latest-wins     # then restart the app
.\patterns\6b-latest-wins\tools\Reset-Queue.ps1 -Pattern 6b-latest-wins
.\scripts\Invoke-LoadTest.ps1    -Pattern 6b-latest-wins
.\scripts\Export-Results.ps1     -Pattern 6b-latest-wins -RunId <runId> -StartUtc <start> -EndUtc <end>
.\patterns\6b-latest-wins\tools\Run-Queries.ps1 -Pattern 6b-latest-wins -RunId <runId> -StartUtc <start> -EndUtc <end>
& "C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe" .\patterns\6b-latest-wins\tools\check-latest.py <cosmosEndpoint> <start> <end> latest.json
.\scripts\Set-PatternScale.ps1   -Pattern 6b-latest-wins -Down
```

`check-latest.py` reads the arrival documents in the window and reports out-of-order arrivals
(a message whose `seq` is lower than one already processed for its key), stale writes skipped,
ETag retries, and whether each `latest-<key>` document holds the highest `seq` processed for
that key.

## Results

| Metric | Run 1: batch 50 (`run-20261122-091756`) | Run 2: batch 250 (`run-20261122-095600`) |
|---|---|---|
| Messages sent | 30,010 | 30,085 |
| Messages processed | 9,870 in 198 runs | 195 |
| Runs succeeded / failed | 198 / 0 | 6 / 602 |
| Run duration p50 / p95 | 6.7 / 7.5 s | 0.12 / 0.33 s (mostly failures) |
| Throughput | about 7-10 msg/s | none sustained |
| Max instances | 1 | 1 |
| Out-of-order arrivals | 44 | 1 |
| Stale writes skipped | 45 | 1 |
| ETag retries | 85 (max 2 attempts) | 0 |
| `latest` documents not at max seq | 0 of 100 | 0 |
| Left over | 20,190 purged at the end | 29,890 dead-lettered |

Findings:

- Latest-wins held: every key's `latest` document had the highest sequence number processed,
  and the 45 stale updates were skipped instead of overwriting newer data.
- Out-of-order arrival is rare at this load (44 of 9,870) because the queue keeps send order
  and one run's For each mostly works on different keys. It still happens, so the conditional
  write is needed.
- This design was slower than strict order (6a: about 27 msg/s). Each message costs a read,
  a compare and a conditional write, plus ETag retries when parallel branches hit the same key.
  The ordering method is not the limit; the per-message Cosmos work and one instance are.
- The app never scaled past one instance.
- **Batch 250 failed.** A stateless For each allows 100 items by default. Every run with more
  than 100 messages failed `For_each_message`, the trigger abandoned the batch, and after 5
  deliveries Service Bus dead-lettered 29,890 messages. Keep the batch at 100 or less, or raise
  the limit with the `Runtime.Backend.Stateless.FlowDefaultForeachItemsLimit` host setting or
  `runtimeConfiguration.collections.maximumItemCount` on the For each.

Charts: `results\6b-latest-wins\run-*\*.png`. Checker output:
`results\6b-latest-wins\latest-run-*.json`. Run 2 failure details:
`results\6b-latest-wins\run-20261122-095600\failure-details.json`.

## Queries

App Insights queries in `queries\` (Run-Queries.ps1 fills in the parameters):

- `timeline-per-minute.kql`: runs, Cosmos writes and instances per minute.
- `messages-per-run.kql`: messages per run.
- `runs-per-second.kql`: run starts per second.
- `actions-by-status.kql`: action counts by status, including the expected 404, 409 and 412.

## Notes

- The Cosmos `CreateOrUpdateDocument` operation applies `If-Match` only when `isUpsert` is
  true, so `Replace_latest` uses upsert with the ETag.
- The trigger completes messages after the run whatever the actions did, so a failed branch
  is not retried by Service Bus. Only a failed run (as in run 2) abandons the batch.
- Do not use `splitOn` here: stateless workflows reject it.
