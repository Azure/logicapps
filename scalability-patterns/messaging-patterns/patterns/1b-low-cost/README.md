# Pattern 1b: Lowest cost, steady load

## What it shows

How to handle a steady Service Bus load with as few workflow runs as possible. One run takes a
batch of up to 100 messages instead of one run per message. It reports runs per message,
actions per message and instance-minutes, which show cost efficiency on a Workflow Standard
plan, where you pay per instance.

## Flow

```
Locust (Azure Load Testing) --sendMessages, batches of 10--> queue "orders"
  -> orders-low-cost (stateful)
       trigger: Service Bus receiveQueueMessages (built-in, managed identity), no splitOn,
                maxMessageBatchSize 100 (one run per batch)
       For_each_message (concurrency 20)
            Process_order: calls shared child workflow "process-order"
                 Liquid transform -> C# custom code (OrderEnricher) -> Cosmos DB upsert -> Response
```

Logic Apps Standard has no batch trigger, so the sample turns `splitOn` off and lets one run
receive the whole batch. The trigger auto-completes the messages when the run starts.

## Settings (`params.json`)

| Setting | Value |
|---|---|
| Plan | WS1, `minimumElasticInstanceCount` 1, `maximumElasticWorkerCount` 3 |
| Queue `orders` | lock 5 min, max delivery 10, 5 GB, no sessions |
| Trigger | `maxMessageBatchSize` 100, no `splitOn`, no trigger concurrency limit |
| For each | concurrency 20 |
| host.json | `extensions.serviceBus.maxMessageBatchSize = 100`, `prefetchCount = 0` |
| Load | 5 users x 1 engine x 10 messages x 1 batch/s = 50 msg/s for 10 min, 5 min drain |
| Measurement | `measurement.workflowName = orders-low-cost` |

## Run

```powershell
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
.\scripts\Deploy-Pattern.ps1     -Pattern 1b-low-cost
.\scripts\Invoke-LoadTest.ps1    -Pattern 1b-low-cost
.\scripts\Export-Results.ps1     -Pattern 1b-low-cost
.\scripts\Set-PatternScale.ps1   -Pattern 1b-low-cost -Down
```

The efficiency queries in `queries\` cover both the parent and the child workflow. Run them in
the App Insights Logs blade with the time range of the run.

| Query | Shows |
|---|---|
| `queries\efficiency.kql` | runs, actions and messages per workflow; runs and actions per message |
| `queries\instance-minutes.kql` | instance-minutes during the run |
| `queries\messages-per-minute.kql` | orders processed per minute (child runs) |

## Results

Run `run-20261122-081111` (westus3, WS1, 50 msg/s for 10 min, then a 5 min drain):

| Metric | Value |
|---|---|
| Messages sent | 30,040 |
| Peak `orders` backlog | 15,667 |
| Messages processed | 6-10 per second on 1 instance |
| Parent run duration | p50 850 s, p95 1,213 s |
| End-to-end latency | p50 744 s, p95 1,153 s |
| Max instances | 1 |
| Failures, dead letters | 0 |
| Parent runs per message | about 0.005 (1 run per 100 messages) |
| Runs per message, parent and child | about 1.008 |
| Actions per message | about 5.03 (1.01 parent, 4.02 child) |
| Instance-minutes | 21 for 21 minutes (08:11-08:31Z, 8,686 messages processed) |

The batch removes almost all parent runs. The child call still costs one run per message, so
the total stays near 1 run per message. Inline the child's actions in the `For each` to bring
runs per message close to 0.01.

### Messages leave the queue before they are processed

The trigger auto-completes each batch and starts a new run as soon as it can. 302 parent runs
started, but only 50 had finished by the drain, so about 250 runs held about 19,500 messages
inside the app. The queue showed 0 messages while most of the work was still waiting. The last
run ended at 08:38:36Z, about 13 minutes after the load stopped.

This has two effects:

- Queue depth does not show the backlog, and the scale controller did not add a second
  instance.
- If you stop the app, these messages stay in paused stateful runs, not in the queue.

To keep work in the queue until the app can process it, do one of these:

1. Set trigger concurrency (for example 5-10 runs). Set it before the first deploy: you cannot
   remove it later without renaming the workflow.
2. Raise the `For each` concurrency so each run finishes sooner.
3. Use peek-lock and complete each message after it is processed.
4. Run the processing actions inline instead of calling the child workflow.
