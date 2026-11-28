param(
    [Parameter(Mandatory)] [string]$OutDir,
    [Parameter(Mandatory)] [int]$Pairs,
    [Parameter(Mandatory)] [int]$Limit,
    [string]$Pattern = 'batch-sustained-rate',
    [int]$ScaleUnits = 6,
    # Folder with connections.json, Artifacts and lib from a deployed batch pattern app.
    [Parameter(Mandatory)] [string]$SourceApp
)
$ErrorActionPreference = 'Stop'
$src = $SourceApp
if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory $OutDir | Out-Null
Copy-Item (Join-Path $src 'connections.json') $OutDir
Copy-Item (Join-Path $src 'Artifacts') $OutDir -Recurse
Copy-Item (Join-Path $src 'lib') $OutDir -Recurse

function Save([string]$name, $obj) {
    $dir = Join-Path $OutDir $name
    New-Item -ItemType Directory $dir -Force | Out-Null
    $obj | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $dir 'workflow.json') -Encoding utf8
}

$hostJson = [ordered]@{
    version = '2.0'
    extensionBundle = [ordered]@{ id = 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'; version = '[1.*, 2.0.0)' }
    logging = [ordered]@{
        logLevel = [ordered]@{ default = 'Warning'; 'Workflow.Operations.Runs' = 'Information' }
        applicationInsights = [ordered]@{ samplingSettings = [ordered]@{ isEnabled = $true; maxTelemetryItemsPerSecond = 20 } }
    }
    extensions = [ordered]@{
        serviceBus = [ordered]@{ maxMessageBatchSize = 100; prefetchCount = 0 }
        workflow = [ordered]@{
            Settings = [ordered]@{
                'Runtime.ScaleUnitsCount' = "$ScaleUnits"
                'Jobs.NumPartitionsInJobTriggersQueue' = '8'
                'Runtime.Trigger.MaximumRunConcurrency' = '10000'
                'Runtime.FlowRunEngine.MaximumConcurrentSplitOnItemLimit' = '1000'
                'Runtime.ServiceProviders.FunctionTriggers.DynamicListenerEnableDisableInterval' = '00:00:01'
                'Runtime.ServiceProviders.FunctionTriggers.SplitonTriggerDisableDynamicListenerInterval' = '00:00:01'
                'Runtime.FlowTriggerDispatchingJob.MessageProcessingConcurrencyLimit' = '32'
                'Runtime.FlowTriggerDispatchingJob.MaximumTriggerDispatchSize' = '32'
                'JobResourceGovernance.WorkerPulsationsThrottling.MinimumProcessorTimeUtilization' = '55'
                'JobResourceGovernance.WorkerPulsationsThrottling.MaximumProcessorTimeUtilization' = '75'
                'Runtime.ApplicationInsightTelemetryVersion' = 'v2'
                'Runtime.BatchConfiguration.MinimumRecurrenceInterval' = '00:00:01'
                'Runtime.BatchConfiguration.AllowMessageCountInRecurrence' = 'true'
                'Runtime.FlowBatchTriggerReleaseJob.ExecutionInterval' = '00:00:00.100'
                'Runtime.FlowBatchTriggerPushJob.ExecutionInterval' = '00:00:01'
                'Runtime.FlowBatchTriggerPushJob.DisableSafetyLimitsRelease' = 'true'
            }
        }
    }
}
$hostJson | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $OutDir 'host.json') -Encoding utf8

$schema = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
for ($i = 1; $i -le $Pairs; $i++) {
    $suffix = if ($i -eq 1) { '' } else { "-$i" }
    $receiver = "orders-receiver$suffix"
    Save "orders-ingress$suffix" ([ordered]@{
        definition = [ordered]@{
            '$schema' = $schema; contentVersion = '1.0.0.0'
            triggers = [ordered]@{
                When_messages_are_available_in_orders = [ordered]@{
                    type = 'ServiceProvider'
                    inputs = [ordered]@{
                        parameters = [ordered]@{ queueName = 'orders'; isSessionsEnabled = $false; maxMessageBatchSize = 100 }
                        serviceProviderConfiguration = [ordered]@{ connectionName = 'serviceBus'; operationId = 'receiveQueueMessages'; serviceProviderId = '/serviceProviders/serviceBus' }
                    }
                    splitOn = "@triggerOutputs()?['body']"
                }
            }
            actions = [ordered]@{
                Send_to_batch = [ordered]@{
                    type = 'SendToBatch'
                    inputs = [ordered]@{
                        host = [ordered]@{ workflow = [ordered]@{ id = $receiver }; triggerName = 'Batch_messages' }
                        batchName = 'orders'; partitionName = 'default'
                        messageId = "@triggerBody()?['messageId']"
                        content = '@triggerBody()'
                    }
                    runAfter = @{}
                }
            }
            outputs = @{}
        }
        kind = 'Stateful'
    })
    Save $receiver ([ordered]@{
        definition = [ordered]@{
            '$schema' = $schema; contentVersion = '1.0.0.0'
            triggers = [ordered]@{
                Batch_messages = [ordered]@{
                    type = 'Batch'
                    inputs = [ordered]@{
                        mode = 'Inline'
                        configurations = [ordered]@{
                            orders = [ordered]@{ releaseCriteria = [ordered]@{ recurrence = [ordered]@{ frequency = 'Second'; interval = 1; messageCountLimit = $Limit } } }
                        }
                    }
                }
            }
            actions = [ordered]@{
                Tag_items = [ordered]@{
                    type = 'Select'
                    inputs = [ordered]@{
                        from = "@triggerBody()?['items']"
                        select = [ordered]@{
                            content = "@item()?['content']"
                            releaseId = "@{workflow()?['run']?['name']}"
                            receiver = $receiver
                        }
                    }
                    runAfter = @{}
                }
                Process_batch = [ordered]@{
                    type = 'Workflow'
                    inputs = [ordered]@{
                        host = [ordered]@{ workflow = [ordered]@{ id = 'process-batch-item' } }
                        body = [ordered]@{ items = "@body('Tag_items')" }
                        retryPolicy = [ordered]@{ type = 'none' }
                    }
                    operationOptions = 'DisableAsyncPattern'
                    runAfter = [ordered]@{ Tag_items = @('Succeeded') }
                }
            }
            outputs = @{}
        }
        kind = 'Stateful'
    })
}

Save 'process-batch-item' ([ordered]@{
    definition = [ordered]@{
        '$schema' = $schema; contentVersion = '1.0.0.0'
        triggers = [ordered]@{
            When_a_batch_arrives = [ordered]@{ type = 'Request'; kind = 'Http'; inputs = @{}; splitOn = "@triggerBody()?['items']" }
        }
        actions = [ordered]@{
            Process_order = [ordered]@{
                type = 'Workflow'
                inputs = [ordered]@{
                    host = [ordered]@{ workflow = [ordered]@{ id = 'process-order' } }
                    body = [ordered]@{
                        messageId = "@{triggerBody()?['content']?['messageId']}"
                        pattern = $Pattern
                        releaseId = "@{triggerBody()?['releaseId']}"
                        receiver = "@{triggerBody()?['receiver']}"
                        order = "@triggerBody()?['content']?['contentData']"
                    }
                }
                trackedProperties = [ordered]@{
                    messageId = "@{triggerBody()?['content']?['messageId']}"
                    enqueuedTimeUtc = "@{triggerBody()?['content']?['enqueuedTimeUtc']}"
                    sentAtUtc = "@{triggerBody()?['content']?['contentData']?['sentAtUtc']}"
                    releaseId = "@{triggerBody()?['releaseId']}"
                    pattern = $Pattern
                }
                runAfter = @{}
            }
        }
        outputs = @{}
    }
    kind = 'Stateful'
})

$po = Get-Content (Join-Path $src 'process-order\workflow.json') -Raw | ConvertFrom-Json
$po.definition.actions.Upsert_order.inputs.parameters.item = "@setProperty(setProperty(setProperty(setProperty(setProperty(setProperty(body('Transform_order'), 'id', guid()), 'messageId', triggerBody()?['messageId']), 'releaseId', triggerBody()?['releaseId']), 'receiver', triggerBody()?['receiver']), 'enrichment', body('Enrich_order')), 'processedAtUtc', utcNow())"
$po.definition.triggers.manual.inputs.schema.properties | Add-Member releaseId ([ordered]@{ type = 'string' }) -Force
$po.definition.triggers.manual.inputs.schema.properties | Add-Member receiver ([ordered]@{ type = 'string' }) -Force
Save 'process-order' $po

$zip = "$OutDir.zip"
if (Test-Path $zip) { Remove-Item $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $zip)
"built $zip pairs=$Pairs limit=$Limit"
