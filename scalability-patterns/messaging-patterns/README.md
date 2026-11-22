# Logic Apps Standard + Service Bus benchmark kit

This kit deploys a Logic Apps Standard app, a Service Bus namespace, Cosmos DB, App Insights
and Azure Load Testing into one resource group per pattern. It drives load with Locust, then
exports results and charts. The shared code stays the same for every pattern. Each pattern is
defined only by the files in `patterns/<id>/`.

## Layout

| Path | Contents |
|---|---|
| `infra/main.bicep`, `infra/modules/` | Plan + Logic App (user-assigned identity), Service Bus (queues, topics, subscriptions, `results` queue), Log Analytics + App Insights, Cosmos DB serverless (`msgpat`/`items`, `/pk`), storage, identity and role assignments, Azure Load Testing. |
| `shared/logicapp/` | Base app: `host.json`, `connections.json` (Service Bus + Cosmos with managed identity), child workflow `process-order`, `Artifacts/Maps/order.liquid`, custom code output in `lib/custom/` (built on first deploy). |
| `shared/customcode/` | Source for the net8 custom code function `OrderEnricher`. |
| `patterns/<id>/` | One folder per pattern: `params.json`, `workflows/`, `loadtest/`, `README.md`, optional `host.json`, `connections.json` and `Artifacts/`. |
| `scripts/` | Deploy, load test, export, scale and chart scripts; `queries/*.kql` (see `scripts/queries/README.md`). |
| `results/<id>/` | `deployment.json`, `last-run.json` and one folder per run with CSV, JSON and PNG output. |

## Prerequisites

- PowerShell 7, Azure CLI with the `load`, `logicapp` and `application-insights` extensions, Bicep.
- `az login` to the target subscription. You need rights to create resource groups and role assignments.
- Python 3 for charts and local sends. The scripts use the Azure CLI's Python unless `MSGPAT_PYTHON` is set.
  Install packages into the kit once:
  `& "C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe" -m pip install --upgrade --target .tools\pylib matplotlib azure-servicebus azure-identity`
- .NET 8 SDK. `Deploy-Pattern.ps1` builds the custom code on first use with `dotnet build shared\customcode\OrderEnricher -c Release`,
  which copies the assemblies into `shared/logicapp/lib/custom/`.

Put the Azure CLI on PATH in each new shell. `scripts/Common.ps1` also does this:
`$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"`

## Run loop

```powershell
.\scripts\Deploy-Pattern.ps1   -Pattern <id> [-Location westus3] [-SkipInfra] [-SkipCode] [-SkipWhatIf]
.\scripts\Invoke-LoadTest.ps1  -Pattern <id> [-DurationMinutes n] [-Users n] [-EngineInstances n] [-BatchSize n] [-BatchesPerUserPerSecond n] [-DrainMinutes n] [-NoWait]
.\scripts\Export-Results.ps1   -Pattern <id> [-RunId run-...] [-StartUtc ... -EndUtc ...] [-SkipCharts]
python .\scripts\New-Charts.py results\<id>\<runId>       # Export-Results already runs this
.\scripts\Set-PatternScale.ps1 -Pattern <id> -Down        # or -Up; never deletes the resource group
```

1. **Deploy** builds `infra/main.bicep` and runs what-if, then deploys into `rg-msgpat-<id>`.
   If the region has no capacity, it retries in `fallbackLocation`. It builds the app from
   `shared/logicapp` plus the pattern's workflows and artifacts, merges `host.json` and
   `connections.json`, and zip deploys. It writes `results/<id>/deployment.json`.
2. **Invoke-LoadTest** copies `patterns/<id>/loadtest/` to `.staging/`, fills the tokens, and
   creates or updates the Azure Load Testing test `msgpat-<id>`. It starts a run, waits for it
   to finish, then waits `drainMinutes`. It writes `results/<id>/last-run.json`.
3. **Export-Results** runs every query in `scripts/queries/` for the run window (start to load
   end + drain, plus 3 minutes for ingestion). It reads Service Bus metrics, then writes CSV,
   JSON, `summary.json` and charts to `results/<id>/<runId>/`.
4. **Set-PatternScale -Down** sets minimum instances and maximum burst to 1 and stops the app.
   `-Up` restores the values from `params.json`.

Charts: `throughput.png` (runs/min), `run-latency.png` and `e2e-latency.png` (p50/p95/p99),
`queue-backlog.png` (Service Bus active/incoming/completed), `instances.png`, `failures.png`.

## Measurement

The kit measures through App Insights telemetry v2, not the `results` queue. The queue exists
for patterns that need a reply channel. Each run's end event gives run duration and status.
The entry workflow's processing action must set these tracked properties:

```json
"trackedProperties": {
  "messageId": "@{triggerBody()?['messageId']}",
  "enqueuedTimeUtc": "@{triggerBody()?['enqueuedTimeUtc']}",
  "sentAtUtc": "@{triggerBody()?['contentData']?['sentAtUtc']}",
  "pattern": "<id>"
}
```

The Locust script stamps `sentAtUtc` in each message, so end-to-end latency is from send to the
end of that action.

## Adding a pattern (contract)

Create `patterns/<id>/` (`<id>` is lowercase, digits and hyphens, e.g. `2b-sessions`). Do not
edit `infra/`, `shared/` or `scripts/`.

| File | Required | Purpose |
|---|---|---|
| `params.json` | yes | Infra and run settings (schema below). |
| `workflows/<name>/workflow.json` | yes | One folder per workflow. Call the child with `"type": "Workflow"`, `"host": {"workflow": {"id": "process-order"}}`, body `{messageId, pattern, order}`. |
| `loadtest/loadtest.yaml` | yes | Copy from 1a; keep the `__TOKEN__` placeholders. |
| `loadtest/locustfile.py`, `locust.conf`, `requirements.txt` | yes | Copy from 1a. The locustfile reads `SB_QUEUE` or `SB_TOPIC`, `SESSION_COUNT`, `BATCH_SIZE`, `BATCHES_PER_USER_PER_SECOND`. Change it only for a new send shape. |
| `README.md` | yes | What it shows, flow, settings, how to run, results. |
| `host.json` | no | Deep-merged over `shared/logicapp/host.json`. |
| `connections.json` | no | Deep-merged over the shared connections (for example, an extra connection). |
| `Artifacts/` | no | Extra maps or schemas, copied into the app. |

Rules:

- Use the built-in Service Bus operations (`receiveQueueMessages`, `receiveTopicMessages`,
  `peekLockQueueMessages`, `sendMessage`, `sendMessages`, `completeMessage`, ...) with connection
  `serviceBus`. Do not mix them with the V2 managed or other Service Bus connector in one app.
- Set tracked properties as above, not `clientTrackingId` from the trigger body on `splitOn`.
- If the pattern has more than one workflow, set `measurement.workflowName` to the entry workflow.

### `params.json` schema

```jsonc
{
  "location": "westus3",                 // primary region
  "fallbackLocation": "swedencentral",   // used on capacity or quota failure
  "planSku": "WS1",                      // WS1 | WS2 | WS3
  "maximumElasticWorkerCount": 20,       // max burst
  "minimumElasticInstanceCount": 1,
  "functionsRuntimeScaleMonitoringEnabled": false, // true only when storage is VNET-restricted
  "serviceBusSku": "Standard",           // Standard | Premium
  "serviceBusPremiumCapacity": 1,        // Premium only
  "queues": [{ "name": "orders", "lockDuration": "PT1M", "maxDeliveryCount": 10,
               "maxSizeInMegabytes": 5120, "requiresSession": false,
               "deadLetteringOnMessageExpiration": false, "enablePartitioning": false }],
  "topics": [{ "name": "events", "maxSizeInMegabytes": 5120,
               "subscriptions": [{ "name": "all", "requiresSession": false, "lockDuration": "PT1M",
                                   "maxDeliveryCount": 10, "sqlFilter": "region = 'west'" }] }],
  "extraAppSettings": { "MY_SETTING": "value" },
  "hostSettings": { "Runtime.Trigger.MaximumWaitingRuns": "200" },   // into extensions.workflow.Settings
  "loadTest": { "queueName": "orders",   // for a topic, omit queueName and set env.SB_TOPIC
                "engineInstances": 1, "users": 20, "spawnRate": 20, "batchSize": 10,
                "batchesPerUserPerSecond": 1, "durationMinutes": 10,
                "env": { "SESSION_COUNT": "0" } },   // extra Locust env vars: SB_TOPIC, SESSION_COUNT, ...
  "drainMinutes": 10,
  "measurement": { "workflowName": "<entry workflow>" }
}
```

Target rate = `users x engineInstances x batchSize x batchesPerUserPerSecond` messages per second.
A `results` queue is always created. App settings always include `serviceBus_fullyQualifiedNamespace`,
`cosmos_endpoint`, `UAMI_RESOURCE_ID` and `UAMI_CLIENT_ID`.

## Verified runtime facts

- `FUNCTIONS_WORKER_RUNTIME=dotnet` and `LOGIC_APPS_CUSTOMCODE_DOTNETVERSION=net8` for net8 custom code.
  Layout: `lib/custom/net8/*.dll` plus `lib/custom/<FunctionName>/function.json`.
- Custom code `ILogger` output lands in `traces` with category `Function.<FunctionName>.User`.
- Trigger `splitOn` with run concurrency is allowed. The concurrency limit is 100 runs, and with
  concurrency on, one trigger batch may split into at most 100 runs.
- The built-in Service Bus trigger (`receiveQueueMessages`) completes messages itself. Its batch
  size comes from the trigger input `maxMessageBatchSize`, then host.json
  `extensions.serviceBus.maxMessageBatchSize`, then the default 20. A backlog can return up to
  1000 messages, so set `maxMessageBatchSize` to 100 or less when you use `splitOn` with concurrency.

## Known issues

- Azure Load Testing spends about 3.5 minutes provisioning before it sends load.
- In `loadtest.yaml`, list `locust.conf` only as `properties.userPropertyFile`. Listing it also in
  `configurationFiles` fails with `InvalidFileName`.
- `pip install --target` into an existing folder needs `--upgrade`.
- `ScaleControllerLogs` "Failed to initialize scale monitoring" exceptions are harmless.
- The plan scales on the Logic Apps job queue, not on the Service Bus backlog. Trigger
  concurrency and `maximumWaitingRuns` cap how much work reaches the job queue, so a capped
  trigger can stay on one instance while the backlog grows. See pattern 1a's results.
- App Insights data arrives 2 to 5 minutes late; export after the drain.
- A trigger batch larger than the `splitOn` limit fails the trigger. The trigger abandons the
  messages, and after `maxDeliveryCount` they go to the dead-letter queue. The reason appears
  only in the Kudu host log (`LogFiles/Application/Functions/Host`), not in App Insights.
- `clientTrackingId` from the trigger body combined with `splitOn` fails the same way. Use tracked properties.
- Stateless child workflows keep no run history. Their run events still reach App Insights, so
  filter run queries by workflow name or counts double.
- A Standard Service Bus send batch is limited to 256 KB. `Send-TestMessages.py` splits batches
  that exceed it; keep Locust batches under the limit.
- `az monitor app-insights query --analytics-query` mishandles multi-line KQL. The scripts post
  the `.kql` files through `az rest`, which keeps line breaks; for ad hoc runs, use the portal or
  put the query on one line.
