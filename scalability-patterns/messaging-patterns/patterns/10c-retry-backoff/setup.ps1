<#
.SYNOPSIS
    Creates the rate-limited Cosmos DB downstream for this pattern and empties the orders queue.
.DESCRIPTION
    Run after Deploy-Pattern.ps1 and before each load test. The kit's Cosmos DB account is
    serverless, so it has no RU/s limit to hit. This script:
      1. Creates a provisioned Cosmos DB account (local auth off) in the pattern's region.
      2. Creates database 'limited' and container 'items' with a fixed 400 RU/s (from params.json).
      3. Grants Cosmos DB Built-in Data Contributor to the UAMI and to the signed-in user.
      4. Sets the cosmosLimited_endpoint app setting that connections.json uses, then restarts the app.
      5. Purges the orders queue by deleting and recreating it with the same settings.
    Use -PurgeOnly to run step 5 alone between load tests.
#>
param(
    [switch] $PurgeOnly
)

$ErrorActionPreference = 'Stop'
$patternId = Split-Path $PSScriptRoot -Leaf
$kitRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$deployment = Get-Content (Join-Path $kitRoot "results\$patternId\deployment.json") -Raw | ConvertFrom-Json
$params = Get-Content (Join-Path $PSScriptRoot 'params.json') -Raw | ConvertFrom-Json
$resourceGroup = $deployment.resourceGroup
$limited = $params.cosmosLimited

if (-not $PurgeOnly) {
    $suffix = ($deployment.storageAccountName -replace '[^a-z0-9]', '')
    $suffix = $suffix.Substring([Math]::Max(0, $suffix.Length - 12))
    $account = "cosl$suffix"
    $existing = az cosmosdb show -g $resourceGroup -n $account -o json 2>$null | ConvertFrom-Json
    if (-not $existing) {
        Write-Host "Creating provisioned Cosmos DB account $account in $($params.location) (several minutes)."
        az cosmosdb create -g $resourceGroup -n $account --locations regionName=$($params.location) failoverPriority=0 isZoneRedundant=false `
            --default-consistency-level Session --disable-local-auth true --output none
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Cosmos DB account $account." }
        $existing = az cosmosdb show -g $resourceGroup -n $account -o json | ConvertFrom-Json
    }

    az cosmosdb sql database create -g $resourceGroup -a $account -n $limited.databaseId --output none 2>$null
    $container = az cosmosdb sql container show -g $resourceGroup -a $account -d $limited.databaseId -n $limited.containerId -o json 2>$null | ConvertFrom-Json
    if (-not $container) {
        Write-Host "Creating container $($limited.containerId) at $($limited.throughputRUs) RU/s."
        az cosmosdb sql container create -g $resourceGroup -a $account -d $limited.databaseId -n $limited.containerId `
            -p $limited.partitionKeyPath --throughput $limited.throughputRUs --output none
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create the limited container.' }
    }
    else {
        az cosmosdb sql container throughput update -g $resourceGroup -a $account -d $limited.databaseId -n $limited.containerId `
            --throughput $limited.throughputRUs --output none
    }

    $roleId = "$($existing.id)/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
    $principals = @(
        (az identity show --ids $deployment.identityId --query principalId -o tsv),
        (az ad signed-in-user show --query id -o tsv)
    )
    $assigned = az cosmosdb sql role assignment list -g $resourceGroup -a $account --query '[].principalId' -o json | ConvertFrom-Json
    foreach ($principal in $principals) {
        if ($principal -and $assigned -notcontains $principal) {
            Write-Host "Granting Cosmos DB Built-in Data Contributor to $principal."
            az cosmosdb sql role assignment create -g $resourceGroup -a $account --role-definition-id $roleId `
                --principal-id $principal --scope '/' --output none
        }
    }

    $endpoint = $existing.documentEndpoint
    Write-Host "Setting cosmosLimited_endpoint=$endpoint on $($deployment.logicAppName)."
    az functionapp config appsettings set -g $resourceGroup -n $deployment.logicAppName --settings "cosmosLimited_endpoint=$endpoint" --output none
    if ($LASTEXITCODE -ne 0) { throw 'Failed to set the cosmosLimited_endpoint app setting.' }
    az functionapp restart -g $resourceGroup -n $deployment.logicAppName --output none
}

$queue = $params.queues | Where-Object { $_.name -eq $params.loadTest.queueName }
Write-Host "Purging queue $($queue.name) (delete and recreate)."
az servicebus queue delete -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name --output none
az servicebus queue create -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name `
    --lock-duration $queue.lockDuration --max-delivery-count $queue.maxDeliveryCount --max-size $queue.maxSizeInMegabytes --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to recreate queue $($queue.name)." }
Write-Host 'Done.'
