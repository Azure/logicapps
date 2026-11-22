# Application Insights queries

`Export-Results.ps1` runs every `*.kql` file in this folder against the pattern's
Application Insights resource. It writes `<name>.csv` and `<name>.json` to `results/<id>/<runId>/`.

Each query starts with three tokens:

| Token | Meaning |
|---|---|
| `{{startUtc}}` | Start of the measured window (load test start, UTC ISO 8601). |
| `{{endUtc}}` | End of the window (load end + drain time). |
| `{{workflowName}}` | The measured parent workflow, from `params.json` `measurement.workflowName` or the pattern's only workflow. |

To run a query in the portal (Application Insights > Logs), replace the tokens with literal
values, for example `datetime(2026-11-22T06:13:00Z)` and `"orders-max-throughput"`.

The queries need App Insights telemetry v2 (`Runtime.ApplicationInsightTelemetryVersion: v2`
in host.json) and sampling disabled. The shared host.json sets both.

| Query | Returns |
|---|---|
| `summary.kql` | One row: runs completed/succeeded/failed, average and peak msg/s, run and end-to-end p50/p95/p99, max instances, drain time. |
| `runs-per-minute.kql` | Completed runs and failures per minute (throughput). |
| `run-duration-percentiles.kql` | Run duration p50/p95/p99 per minute. |
| `end-to-end-latency.kql` | Send-to-finish latency p50/p95/p99 per minute, from the `sentAtUtc` tracked property. |
| `action-durations.kql` | Per-action count and p50/p95/p99 duration, grouped by workflow, action and `apiName`. |
| `instances-per-minute.kql` | Distinct `cloud_RoleInstance` per minute (Logic App instance count). |
| `failures.kql` | Failed actions and exceptions per minute. |
| `failure-details.kql` | Top failure messages and codes. |
| `custom-code-logs.kql` | Custom code `ILogger` traces (category `Function.<FunctionName>.User`). |

## Telemetry shapes (v2)

| Signal | Table | Filter |
|---|---|---|
| Run start/end | `traces` | `customDimensions.Category == "Workflow.Operations.Runs"`, `customDimensions.EventName` `WorkflowRunStart` / `WorkflowRunEnd`. Duration is `prop__durationInMilliseconds` on the end event; status is `parse_json(tostring(customDimensions.prop__properties)).status`. |
| Actions | `requests` | `customDimensions.Category == "Workflow.Operations.Actions"`; `actionType`, `apiName` (`serviceBus`, `AzureCosmosDB`), `trackedProperties`. `operation_Id` is the run id. |
| Triggers | `requests` | `customDimensions.Category == "Workflow.Operations.Triggers"`; ignore `resultCode == "0"` (polls that found nothing). |
| Custom code logs | `traces` | `customDimensions.Category == "Function.<FunctionName>.User"`. |

Service Bus metrics (ActiveMessages, IncomingMessages, CompleteMessage, DeadletteredMessages) come
from Azure Monitor, not App Insights. `Export-Results.ps1` reads them with `az monitor metrics list`
and writes `servicebus-metrics.csv`.
