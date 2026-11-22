# Pattern 5a: Large messages with a claim check (Service Bus Standard)

## What it shows

How a Logic Apps Standard app handles 1-5 MB order payloads when the sender stores the
payload in Blob Storage and puts only a small reference on a Service Bus Standard queue
(256 KB message limit). Compare it with [5b](../5b-premium-large/README.md), which sends the
same payloads inline on Service Bus Premium.

## Flow

```
Locust (Azure Load Testing, UAMI)
  1. uploads a 1, 2.5 or 5 MB JSON order to container "claims" (Blob Storage, managed identity)
  2. sends a small message {container, blobName, sentAtUtc, payloadKb} to queue "orders"
  -> orders-claim-check (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), splitOn,
                maxMessageBatchSize 10, no trigger concurrency limit
       Read_blob:     built-in AzureBlob readBlob (UAMI) - reads the whole blob into the run
       Process_order: calls child "process-order" with the order header (lines array emptied)
            Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
       Delete_blob:   built-in AzureBlob deleteBlob
```

A lifecycle rule (`delete-stale-claims`, 1 day) removes blobs that a failed run left behind.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 2, `maximumElasticWorkerCount` 20 |
| Service Bus | Standard; queue `orders` lock 5 min, max delivery 10, 5 GB, 256 KB max message |
| Trigger | `maxMessageBatchSize` 10, `splitOn`, no `runtimeConfiguration.concurrency` |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 10`, `prefetchCount = 0` |
| Storage | the app's storage account, container `claims`, Storage Blob Data Contributor for the UAMI |
| Load | 2 users x 1 engine x 1 message x 1/s = 2 msg/s for 10 min (1,200 messages), 10 min drain |
| Payloads | rotate 1,024 / 2,560 / 5,120 KB (`PAYLOAD_SIZES_KB`) |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 5a-claim-check
.\patterns\5a-claim-check\setup.ps1      # app setting blob_endpoint, container, RBAC, lifecycle rule, queue purge
.\scripts\Invoke-LoadTest.ps1    -Pattern 5a-claim-check
.\scripts\Export-Results.ps1     -Pattern 5a-claim-check
.\scripts\Set-PatternScale.ps1   -Pattern 5a-claim-check -Down
```

Run `setup.ps1` after every deployment. `setup.ps1 -PurgeOnly` only empties the queue. The
UAMI is shared by the app and the Azure Load Testing engine, so one role assignment covers
both the upload and the read.

## Results

Run `run-20261122-082901`: westus3, WS1, 2 msg/s for 10 min, then a 10 min drain. Export:
`results/5a-claim-check/run-20261122-082901/` (`summary.json`, CSVs, `throughput.png`,
`run-latency.png`, `e2e-latency.png`, `queue-backlog.png`, `instances.png`, `failures.png`).

| Metric | Value |
|---|---|
| Messages sent | 1,200 |
| Messages completed by the broker | 706 (304 still active at the end) |
| Peak `orders` backlog | 752 |
| Parent runs started / ended | 251 / 64 (all ended runs succeeded) |
| Run duration | p50 375 s, p95 1,083 s |
| End-to-end latency | p50 920 s, p95 1,163 s (64 runs) |
| Read_blob | 82 calls, p50 4.9 s, p95 26.6 s |
| Child runs ended | 59, p50 4.2 s, p95 23.8 s |
| Instances | 2, then 1 from 08:40 |
| Memory working set (max per 5 min) | 2.5-2.77 GB from 08:10, on a WS1 (about 3.5 GB) |
| Failures | 0 failed actions, 0 dead letters, no size or memory errors |

The export window starts at 08:12, so it also holds the smoke run. Its `drainSeconds` (1,230)
is from the first send to the last run end, not a true drain time: the sample did not drain.
Custom queries in `queries/` give the per-workflow numbers above.

### Why

- No run ended after 08:32:44 even though runs kept starting until 08:50. The app held about
  2.7 GB from the first minutes of the load and one instance stopped sending telemetry at
  08:47. The trigger took 10 messages at a time with no concurrency limit, and each run read a
  1-5 MB blob into a stateful run, which stores the action outputs. Memory, not Service Bus,
  was the limit.
- The claim check kept the queue small and sent no message near a size limit, but it did not
  remove the work: the workflow still loaded the full payload. To benefit, pass the blob
  reference to the child (or stream it to its destination) instead of the content.
- The blob calls themselves were cheap (Delete_blob p50 0.4 s). The p95 of about 27-29 s on
  each blob action came from the busy host, not from Storage.

## Notes

- Smoke run `run-20261122-080927` failed on `createArray()` with no arguments. Use
  `json('[]')` for an empty array.
- During the smoke run the host restarted twice (08:16:49 and 08:19:09) with memory near
  2.7 GB.
- The built-in AzureBlob `readBlob` buffers the whole blob in memory
  (`AzureBlobServiceOperationProvider.cs`); its 200 MB limit applies only to extract-archive.
- `setup.ps1` sets the `blob_endpoint` app setting because the kit Bicep does not.
- Queries: `queries/runs-by-workflow.kql`, `queries/actions-by-workflow.kql`,
  `queries/host-restarts.kql`, `queries/size-memory-errors.kql`, plus the kit queries in
  `scripts/queries/`.
