<#
.SYNOPSIS
Deploys the urgent Logic App for pattern 12a on its own plan. Run it after Deploy-Pattern.ps1.
.DESCRIPTION
The kit deploys one Logic App per pattern. This script adds a second app, la-<base>-hi on plan
asp-<base>-hi, with the kit's logicapp.bicep module. It reuses the storage account, identity,
Service Bus, Cosmos DB and Application Insights from the kit deployment, then zip-deploys the
shared logic app content plus app-high\ (orders-high). The settings come from params.json highApp.
-Down scales the urgent app to 1 worker and stops it; -Up starts it again. Scale the bulk app
with scripts\Set-PatternScale.ps1.
.EXAMPLE
./patterns/12a-separate-apps/setup.ps1
#>
param(
    [string]$Pattern = '12a-separate-apps',
    [switch]$SkipInfra,
    [switch]$Down,
    [switch]$Up
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\scripts\Common.ps1')
$kitRoot = Get-KitRoot
$params = Get-PatternParams $Pattern
$outputs = Get-DeploymentOutputs $Pattern
$rg = $outputs.resourceGroup
$highApp = "$($outputs.logicAppName)-hi"
$highPlan = "$($outputs.planName)-hi"
$settings = $params.highApp

if ($Down -or $Up) {
    $maxBurst = if ($Down) { 1 } else { $settings.maximumElasticWorkerCount }
    Invoke-Az resource update -g $rg -n $highPlan --resource-type Microsoft.Web/serverfarms `
        --set "properties.maximumElasticWorkerCount=$maxBurst" -o none
    if ($Down) { Invoke-Az logicapp stop -g $rg -n $highApp -o none }
    else { Invoke-Az logicapp start -g $rg -n $highApp -o none }
    Write-Host "$highApp $(if ($Down) { 'stopped' } else { 'started' }), plan $highPlan max burst $maxBurst."
    return
}

$stagingRoot = Join-Path $kitRoot ".staging\$Pattern-hi"
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

if (-not $SkipInfra) {
    # NOTE: Each app needs its own content share; the kit's storage module creates only the main app's.
    Invoke-Az storage share-rm create -g $rg --storage-account $outputs.storageAccountName -n $highApp -o none
    $connectionString = Invoke-Az resource show -g $rg -n $outputs.appInsightsName `
        --resource-type Microsoft.Insights/components --query properties.ConnectionString -o tsv
    $location = (Invoke-Az group show -n $rg --query location -o tsv)
    $parameterFile = Join-Path $stagingRoot 'hi.parameters.json'
    [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{
            name = @{ value = $highApp }
            planName = @{ value = $highPlan }
            location = @{ value = $location }
            tags = @{ value = @{ purpose = 'logicapps-messaging-benchmark'; pattern = $Pattern; role = 'urgent' } }
            planSku = @{ value = $settings.planSku }
            maximumElasticWorkerCount = @{ value = $settings.maximumElasticWorkerCount }
            minimumElasticInstanceCount = @{ value = $settings.minimumElasticInstanceCount }
            functionsRuntimeScaleMonitoringEnabled = @{ value = $false }
            identityId = @{ value = $outputs.identityId }
            identityClientId = @{ value = $outputs.identityClientId }
            storageAccountName = @{ value = $outputs.storageAccountName }
            contentShareName = @{ value = $highApp }
            appInsightsConnectionString = @{ value = "$connectionString" }
            serviceBusFqdn = @{ value = $outputs.serviceBusFqdn }
            cosmosEndpoint = @{ value = $outputs.cosmosEndpoint }
            extraAppSettings = @{ value = @{} }
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $parameterFile -Encoding utf8NoBOM
    Write-Host "Deploying $highApp on $highPlan..."
    Invoke-Az deployment group create -g $rg -n "msgpat-$Pattern-hi" `
        --template-file (Join-Path $kitRoot 'infra\modules\logicapp.bicep') --parameters "@$parameterFile" -o none
}

# Same staging as Deploy-Pattern.ps1: shared logic app, the urgent workflows, then the merged host.json.
$appDir = Join-Path $stagingRoot 'app'
if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item -Path (Join-Path $kitRoot 'shared\logicapp\*') -Destination $appDir -Recurse -Force
Get-ChildItem (Join-Path $PSScriptRoot 'app-high') -Directory | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $appDir $_.Name) -Recurse -Force
}

function Merge-Hashtable([hashtable]$Target, [hashtable]$Source) {
    foreach ($key in $Source.Keys) {
        if ($Target[$key] -is [hashtable] -and $Source[$key] -is [hashtable]) { Merge-Hashtable $Target[$key] $Source[$key] }
        else { $Target[$key] = $Source[$key] }
    }
}
$hostFile = Join-Path $appDir 'host.json'
$hostJson = Get-Content $hostFile -Raw | ConvertFrom-Json -AsHashtable
Merge-Hashtable $hostJson (Get-Content (Join-Path $PSScriptRoot 'host.json') -Raw | ConvertFrom-Json -AsHashtable)
$hostJson | ConvertTo-Json -Depth 20 | Set-Content -Path $hostFile -Encoding utf8NoBOM

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipFile = Join-Path $stagingRoot 'app.zip'
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($appDir, $zipFile)
Write-Host "Zip deploying $zipFile to $highApp..."
Invoke-Az logicapp deployment source config-zip -g $rg -n $highApp --src $zipFile -o none
Get-ChildItem $appDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'workflow.json') } | ForEach-Object { "  $($_.Name)" }
