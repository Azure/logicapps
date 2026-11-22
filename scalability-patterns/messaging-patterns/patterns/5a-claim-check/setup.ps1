<#
.SYNOPSIS
    Finishes the 5a-claim-check deployment and empties the orders queue.
.DESCRIPTION
    Run after Deploy-Pattern.ps1 and before each load test. The kit's Bicep does not set a
    blob endpoint app setting or a lifecycle rule, and it has no queue purge, so this script:
      1. Sets the blob_endpoint app setting that connections.json uses, then restarts the app.
      2. Writes the storage account name into params.json (loadTest.env.BLOB_ACCOUNT).
      3. Checks that the claims container exists and that the UAMI (used by both the app and
         the Azure Load Testing engine) has Storage Blob Data Contributor on the account.
      4. Adds a lifecycle rule that deletes claim blobs older than one day, as a backstop for
         runs that fail before the Delete_blob action.
      5. Purges the orders queue by deleting and recreating it with the same settings.
    Use -PurgeOnly to run step 5 alone between load tests.
#>
param(
    [switch] $PurgeOnly
)

$ErrorActionPreference = 'Stop'
$patternId = '5a-claim-check'
$kitRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$deployment = Get-Content (Join-Path $kitRoot "results\$patternId\deployment.json") -Raw | ConvertFrom-Json
$paramsPath = Join-Path $PSScriptRoot 'params.json'
$params = Get-Content $paramsPath -Raw | ConvertFrom-Json
$resourceGroup = $deployment.resourceGroup
$account = $deployment.storageAccountName

if (-not $PurgeOnly) {
    $endpoint = "https://$account.blob.core.windows.net/"
    Write-Host "Setting blob_endpoint=$endpoint on $($deployment.logicAppName)."
    az functionapp config appsettings set -g $resourceGroup -n $deployment.logicAppName --settings "blob_endpoint=$endpoint" --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to set the blob_endpoint app setting." }
    az functionapp restart -g $resourceGroup -n $deployment.logicAppName --output none

    $params.loadTest.env.BLOB_ACCOUNT = $account
    $params | ConvertTo-Json -Depth 20 | Set-Content $paramsPath
    Write-Host "Wrote BLOB_ACCOUNT=$account to params.json."

    $storageId = az storage account show -g $resourceGroup -n $account --query id -o tsv
    $container = az storage container-rm show --storage-account $account -g $resourceGroup -n $params.loadTest.env.BLOB_CONTAINER -o json 2>$null | ConvertFrom-Json
    if (-not $container) {
        Write-Host "Creating container $($params.loadTest.env.BLOB_CONTAINER)."
        az storage container-rm create --storage-account $account -g $resourceGroup -n $params.loadTest.env.BLOB_CONTAINER --output none
    }

    $principalId = az identity show --ids $deployment.identityId --query principalId -o tsv
    $roles = az role assignment list --assignee $principalId --scope $storageId -o json | ConvertFrom-Json
    if (-not ($roles | Where-Object { $_.roleDefinitionName -eq 'Storage Blob Data Contributor' })) {
        Write-Host 'Granting Storage Blob Data Contributor to the UAMI.'
        az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Storage Blob Data Contributor' --scope $storageId --output none
    }
    else {
        Write-Host 'The UAMI already has Storage Blob Data Contributor (app and load test engine share it).'
    }

    $policyPath = Join-Path $PSScriptRoot 'lifecycle-policy.json'
    @{
        rules = @(@{
            enabled = $true
            name = 'delete-stale-claims'
            type = 'Lifecycle'
            definition = @{
                filters = @{ blobTypes = @('blockBlob'); prefixMatch = @("$($params.loadTest.env.BLOB_CONTAINER)/") }
                actions = @{ baseBlob = @{ delete = @{ daysAfterModificationGreaterThan = 1 } } }
            }
        })
    } | ConvertTo-Json -Depth 10 | Set-Content $policyPath
    az storage account management-policy create --account-name $account -g $resourceGroup --policy "@$policyPath" --output none
    Remove-Item $policyPath
    Write-Host 'Added lifecycle rule delete-stale-claims (1 day).'
}

$queue = $params.queues | Where-Object { $_.name -eq $params.loadTest.queueName }
Write-Host "Purging queue $($queue.name) (delete and recreate)."
az servicebus queue delete -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name --output none
az servicebus queue create -g $resourceGroup --namespace-name $deployment.serviceBusNamespace -n $queue.name `
    --lock-duration $queue.lockDuration --max-delivery-count $queue.maxDeliveryCount --max-size $queue.maxSizeInMegabytes --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to recreate queue $($queue.name)." }
Write-Host 'Done.'
