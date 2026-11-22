<#
.SYNOPSIS
    Raises the 5b-premium-large queue maximum message size and empties the queue.
.DESCRIPTION
    Run after Deploy-Pattern.ps1 and before each load test. The kit's servicebus.bicep has no
    maxMessageSizeInKilobytes setting, so every deployment resets the queue to the Premium
    default of 1,024 KB. This script purges the orders queue by deleting and recreating it
    with the same settings plus maxMessageSizeInKilobytes from params.json (default 10,240 KB).
    Premium namespaces allow up to 102,400 KB.
#>
$ErrorActionPreference = 'Stop'
$patternId = '5b-premium-large'
$kitRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$deployment = Get-Content (Join-Path $kitRoot "results\$patternId\deployment.json") -Raw | ConvertFrom-Json
$params = Get-Content (Join-Path $PSScriptRoot 'params.json') -Raw | ConvertFrom-Json
$resourceGroup = $deployment.resourceGroup
$maxKb = if ($params.maxMessageSizeInKilobytes) { $params.maxMessageSizeInKilobytes } else { 10240 }

$queue = $params.queues | Where-Object { $_.name -eq $params.loadTest.queueName }
Write-Host "Purging queue $($queue.name) (delete and recreate) with max message size $maxKb KB."
az servicebus queue delete -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name --output none
az servicebus queue create -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name `
    --lock-duration $queue.lockDuration --max-delivery-count $queue.maxDeliveryCount --max-size $queue.maxSizeInMegabytes `
    --max-message-size $maxKb --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to recreate queue $($queue.name)." }
$actual = az servicebus queue show -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name -o json | ConvertFrom-Json
Write-Host "Queue $($queue.name): maxMessageSizeInKilobytes=$($actual.maxMessageSizeInKilobytes)."
