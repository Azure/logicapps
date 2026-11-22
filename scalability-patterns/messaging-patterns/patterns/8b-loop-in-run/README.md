# Pattern 8b: Fan out inside one run

## What it shows

The same inbound message as 8a (N order items), but one run processes all N items with
a For each loop that calls the shared `process-order` child.

## Flow

```
Locust (Azure Load Testing) --sendMessages--> queue "orders" (1 envelope = 50 items, 4% bad)
  -> orders-loop (stateful)
       trigger: Service Bus receiveQueueMessages (built-in), maxMessageBatchSize 10, splitOn,
                concurrency runs 10, maximumWaitingRuns 20
       For_each_item over the envelope's items, concurrency 20
            Process_order: calls shared child "process-order"
```

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 20 |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | batch 10, `splitOn`, concurrency runs 10, `maximumWaitingRuns` 20 |
| For each | `runtimeConfiguration.concurrency.repetitions` 20 |
| Load (same as 8a) | 1 user, 0.2 envelopes/s for 5 min, `ITEMS_PER_MESSAGE` 50, `BAD_ITEM_PERCENT` 4; 8 min drain |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1   -Pattern 8b-loop-in-run
.\scripts\Invoke-LoadTest.ps1  -Pattern 8b-loop-in-run
.\scripts\Export-Results.ps1   -Pattern 8b-loop-in-run -StartUtc <start> -EndUtc <after drain>
.\patterns\8b-loop-in-run\tools\Run-Queries.ps1 -Pattern 8b-loop-in-run -RunId <runId> -StartUtc <start> -EndUtc <after drain>
.\scripts\Set-PatternScale.ps1 -Pattern 8b-loop-in-run -Down
```

## Results

Run `run-20261122-105136` (westus3, WS1), load 10:54:42Z to about 10:59:42Z.

| Metric | Value |
|---|---|
| Envelopes sent / items | 61 / 3,050 |
| Items processed OK / failed (bad items) | 2,919 / 131 |
| Item throughput (first send to last item done) | 7.74 items/s over 394 s |
| End-to-end latency per item | p50 52.0 s, p95 80.2 s, p99 96.0 s, max 137 s |
| `orders-loop` runs | 61 (4 succeeded, 57 failed), duration p50 52.5 s, p95 68.2 s, p99 88.8 s |
| `process-order` child runs | 3,574 including retries, p50 3.1 s, p95 8.2 s, max 18.8 s |
| Good items in failed runs | 2,713 |
| Max instances | 1 |
| Memory working set | peak 453 MB, about 300 to 450 MB under load, about 45 MB idle |
| Peak `orders` backlog / dead letters at end | 6 / 0 |

Charts: `throughput.png`, `run-latency.png`, `e2e-latency.png`, `queue-backlog.png`,
`instances.png`, `failures.png`. Custom query output: `custom/*.json`.

### What the loop does

- One bad item fails the whole run. 57 of 61 runs failed, and 2,713 good items sat in
  failed runs. Their upserts had already happened, so a resubmit of the run reprocesses
  them; the child must be idempotent.
- An item waits for its whole envelope: per-item latency (52 s p50) tracks the run
  duration, against 37 s in 8a.
- Fewer moving parts: no second queue and 61 parent runs instead of 3,111.

## Notes

- A Stateless workflow can't host this design with the Service Bus trigger as written:
  Stateless workflows reject `splitOn` and trigger `runtimeConfiguration`, and a
  Stateless For each is limited to 100 items.
- Keep the run shorter than the message lock (5 min here). The run p99 was 89 s.
