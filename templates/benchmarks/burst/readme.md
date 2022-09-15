# Instructions on how to execute these benchmarks and gather results

1. Create three Logic Apps with the three SKUs (WS1, WS2, WS3). Make sure Application Insights is enabled. Note that Application Insights incurrs a small performance penalty but it is needed to log performance metrics. These results will be slightly worse than those obtained in the blog post, which used internal metrics instead of Application Insights to gather results.
2. Create a dotnet Function App with the provided source code. The Enricher workflow will make outbound calls to it.
3. In each Logic App, create the stateful Dispatcher workflow and the stateless Enricher workflow with the provided workflow definitions.
4. Add these app settings to each of the Logic Apps
    * Enricher.Cosmos.DefaultTtl: 86400
    * Enricher.MaxMappingValidUntil: 3
    * Enricher.RetailApiUrl: \<URL to invoke your function app\>&ean=
5. Modify host.json with these settings to enable verbose logging and disable Application Insights sampling (to improve metric accuracy).
    ```
    {
    "version": "2.0",
    "extensionBundle": {
        "id": "Microsoft.Azure.Functions.ExtensionBundle.Workflows",
        "version": "[1.*, 2.0.0)"
    },
    "logging": {
        "logLevel":{
            "default": "Error"
            },
            "applicationInsights": {
                "samplingSettings": {
                    "isEnabled": false
                }
            }
        }
    }
    ```
6. Using Postman (or your favorite HTTP tool), invoke the Dispatcher workflow of each Logic App with a POST request using the following JSON request body:
    ```
    {
        "orders": [1, 2, 3]
    }
    ```
    - Make the orders array as large as the desired batch size. For example, to send a burst load of 100k messages, the array should have 100k elements.
7. Wait until all the runs finish. Then the below Application Insights queries can be used to obtain the data described in the results section of the blog post. Be sure to set the time range for the queries to correspond to the duration of the test run.

# Application Insight Queries

## Scaling
```
performanceCounters
| summarize dcount(cloud_RoleInstance) by bin(timestamp, 1m)
| render timechart
```

## Actions per minute per instance
```
customMetrics
|where name contains "Actions Completed"
|summarize sum(value) by bin(timestamp, 1m)
|render timechart
```

## Runs per minute per instance
```
customMetrics
|where name in ("Runs Completed")
|summarize sum(value) by bin(timestamp, 1m)
|render timechart
```

## Average execution delay (in seconds)
```
customMetrics
|where name == "Job Execution Delay"
|summarize avg(valueSum/valueCount) by bin(timestamp, 1m)
|render timechart
```

## CPU
```
performanceCounters
| where name == "% Processor Time"
| summarize percentile(value, 90) by bin(timestamp, 1m), cloud_RoleInstance
| render timechart
```

## Memory
```
performanceCounters
| summarize avgif(value, name=="Private Bytes") by bin(timestamp, 1m), cloud_RoleInstance
| render timechart
```

## Storage requests 
Requires trace level logging. Change the logLevel in host.json from "Error" to "Trace" to log this data.
````
traces
| where message startswith "storage operation completed"
| count
````
