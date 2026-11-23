# Pattern implementations

This page shows how each sample implements its messaging pattern. Each row comes from the sample's `workflow.json` files.

Most samples call the shared child workflow [`process-order`](shared/logicapp/process-order/workflow.json) through a **Workflow** action. The child workflow runs a Liquid transform, calls a C# custom code function, upserts the result to Azure Cosmos DB, and returns a response.

## Implementation by variant

| Variant | Sample | Trigger | Workflow type | Key settings | Main actions |
|---|---|---|---|---|---|
| 1a Maximum throughput | [1a-max-throughput](patterns/1a-max-throughput) | Service Bus receive messages | Stateful | `splitOn`, no concurrency limit | Child workflow |
| 1b Lowest cost | [1b-low-cost](patterns/1b-low-cost) | Service Bus receive messages (batch) | Stateful | No `splitOn` | For each → child workflow |
| 2a Drain a spike fast | [2a-drain-fast](patterns/2a-drain-fast) | Service Bus receive messages | Stateful | `splitOn`, scale out | Child workflow (stateless) |
| 2b Absorb and drain steadily | [2b-steady-drain](patterns/2b-steady-drain) | Service Bus receive messages (batch) | Stateful | Concurrency = 2, no `splitOn` | For each → child workflow |
| 3a Finish by a deadline | [3a-deadline](patterns/3a-deadline) | Service Bus receive messages | Stateful | `splitOn`, more minimum instances | Child workflow |
| 3b Spread over a window | [3b-spread-window](patterns/3b-spread-window) | Service Bus receive messages | Stateful | `splitOn`; the sender sets scheduled enqueue times | Child workflow |
| 4 Trickle | [4-trickle](patterns/4-trickle) | Service Bus receive messages | Stateful and stateless versions | Stateful: `splitOn`. Stateless: batch | Child workflow (For each in the stateless version) |
| 5a Claim check | [5a-claim-check](patterns/5a-claim-check) | Service Bus receive messages | Stateful | `splitOn` | Read blob → child workflow → delete blob |
| 5b Large messages | [5b-premium-large](patterns/5b-premium-large) | Service Bus receive messages (Premium) | Stateful | `splitOn` | Child workflow |
| 6a Strict order | [6a-strict-order](patterns/6a-strict-order) | Service Bus receive messages (batch); the reference version uses a session trigger | Stateless | Sequential For each | Cosmos DB upsert; the session version also closes the session |
| 6b Latest state wins | [6b-latest-wins](patterns/6b-latest-wins) | Service Bus receive messages (batch) | Stateless | Version check in Until and If | Cosmos DB read → compare → upsert |
| 7 Long-running work | [7-long-running](patterns/7-long-running) | Service Bus receive messages | Stateful; a stateless peek-lock version for comparison | Settle on receive; the comparison version renews the lock | Wait → child workflow. Comparison: HTTP, renew lock, complete or abandon |
| 8a Fan out to messages | [8a-split-messages](patterns/8a-split-messages) | Service Bus receive messages | Stateful | `splitOn`, concurrency = 10 | Select → send messages; a second workflow processes each item |
| 8b Fan out in one run | [8b-loop-in-run](patterns/8b-loop-in-run) | Service Bus receive messages | Stateful | `splitOn`, concurrency = 10, For each parallelism limit | For each |
| 9a Fan in by key | [9a-group-by-key](patterns/9a-group-by-key) | Service Bus session trigger | Stateful | One run per session; Until collects the group | Select → Cosmos DB upsert → close session |
| 9b Fan in by time window | [9b-time-window](patterns/9b-time-window) | Recurrence | Stateful | Concurrency = 1; Until loop for the window | Receive in a loop → aggregate |
| 10a Limit concurrency | [10a-cap-concurrency](patterns/10a-cap-concurrency) | Service Bus receive messages | Stateful | `splitOn`, concurrency = 10 | Cosmos DB upsert |
| 10b Fixed rate | [10b-fixed-rate](patterns/10b-fixed-rate) | Recurrence | Stateful | Concurrency = 1 | Get messages → For each → upsert → complete or abandon |
| 10c Retry with backoff | [10c-retry-backoff](patterns/10c-retry-backoff) | Service Bus receive messages | Stateful | `splitOn`, concurrency = 100, exponential retry policy | Cosmos DB upsert |
| 11 Request-reply | [11-request-reply](patterns/11-request-reply) | Front: HTTP Request. Back: Service Bus | Front: stateless. Back: stateful | The session ID links each reply to its request | Front: send → wait for session reply → Response. Back: child workflow → send reply |
| 12a Priority with separate apps | [12a-separate-apps](patterns/12a-separate-apps) | Service Bus receive messages, one queue per app | Stateful | `splitOn`; each app scales on its own | Child workflow |
| 12b Priority in one app | [12b-per-workflow-caps](patterns/12b-per-workflow-caps) | Service Bus receive messages | Stateful | High: no limit. Low: concurrency = 20. An unlimited low-priority workflow is included for comparison | Child workflow |

## Main settings

Most patterns differ in four settings:

| Setting | Options |
|---|---|
| How the trigger reads messages | One run per message (`splitOn`) or one run per batch |
| Trigger concurrency | No limit, or a fixed number of runs |
| Workflow type | Stateful or stateless |
| Trigger type | Service Bus, Service Bus session, or Recurrence |
