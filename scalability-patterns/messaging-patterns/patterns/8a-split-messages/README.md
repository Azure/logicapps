# Pattern 8a: Fan out by splitting into messages

## What it shows

One inbound message carries N order items. A splitter workflow turns it into N item
messages on a second queue. A second workflow then processes each item in its own run
through the shared `process-order` child. Compare with 8b, which handles the same load
with a For each loop in one run.

## Flow

```
Locust (Azure Load Testing) --sendMessages--> queue "orders" (1 envelope = 50 items, 4% bad)
  -> orders-splitter (stateful)
       trigger: Service Bus receiveQueueMessages (built-in), maxMessageBatchSize 10, splitOn,
                concurrency runs 10, maximumWaitingRuns 20
       Select items -> one sendMessages call to queue "items" (messageId = itemId)
  -> items-fanout (stateful)
       trigger: Service Bus receiveQueueMessages, maxMessageBatchSize 50, splitOn, no concurrency limit
       Process_order: calls shared child "process-order" (one run per item)
```

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 |
| Queues `orders`, `items` | lock 5 min, max delivery 10, 5 GB, no sessions, no duplicate detection |
| `orders-splitter` trigger | batch 10, `splitOn`, concurrency runs 10, `maximumWaitingRuns` 20 |
| `items-fanout` trigger | batch 50, `splitOn`, no concurrency setting |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load | 1 user, 0.2 envelopes/s for 5 min, `ITEMS_PER_MESSAGE` 50, `BAD_ITEM_PERCENT` 4 (10 items/s offered); 8 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1   -Pattern 8a-split-messages
.\patterns\8a-split-messages\tools\Reset-Queue.ps1 -Pattern 8a-split-messages   # clear "orders" AND "items"
.\scripts\Invoke-LoadTest.ps1  -Pattern 8a-split-messages
.\scripts\Export-Results.ps1   -Pattern 8a-split-messages -StartUtc <start> -EndUtc <after drain>
.\patterns\8a-split-messages\tools\Run-Queries.ps1 -Pattern 8a-split-messages -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1 -Pattern 8a-split-messages -Down
```

Drain the `items` queue before each run. Smoke-test leftovers in `items` were processed
during the real run and inflated the unfiltered item counts.

## Results

Run `run-20261122-105132` (westus3, WS1), load 10:54:40Z to about 10:59:40Z. Item
numbers are filtered to items sent at or after 10:51:30Z (`custom/*-filtered.json`).

| Metric | Value |
|---|---|
| Envelopes sent / items | 61 / 3,050 |
| Items processed OK / failed (bad items) | 2,924 / 126 |
| Item throughput (first send to last item done) | 8.5 items/s over 359 s |
| End-to-end latency per item (enqueue envelope to child done) | p50 37.0 s, p95 57.1 s, p99 74.7 s, max 90.1 s |
| `orders-splitter` runs | 61 (0 failed), duration p50 2.3 s, p95 2.8 s |
| `items-fanout` runs | 3,050 (2,924 ok, 126 failed), duration p50 12.8 s, p95 24.2 s, max 59.0 s |
| `process-order` child runs | 3,554 including retries (630 failed), p50 4.7 s, p95 10.2 s |
| Good items in failed runs | 0 |
| Max instances | 1 |
| Memory working set | peak 527 MB, about 400 to 500 MB under load, about 40 MB idle |
| Dead letters at end | 0 |

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. The export counts `orders-splitter` runs only; use
`custom/item-latency-filtered.json` and `custom/failure-isolation-filtered.json` for items.

### What splitting does

- Each bad item failed only its own run: 126 failed runs for 126 bad items, and no good
  item sat in a failed run. A retry or resubmit touches one item.
- Every item costs one extra Service Bus send, one receive and one run history. The
  splitter itself is cheap (2.3 s p50 for 50 items).
- Throughput was close to the offered 10 items/s on one instance, so the app never
  needed to scale out.

## Notes

- Trigger concurrency on the `items-fanout` splitOn trigger throttled the item runs in
  smoke tests. It can't be removed from a deployed workflow (`CannotDisableTriggerConcurrency`),
  so the workflow was recreated under a new name without it.
- The `items` queue has no duplicate detection because the kit's params schema has no
  option for it. The splitter sets `messageId` to the item id so it can be turned on.
