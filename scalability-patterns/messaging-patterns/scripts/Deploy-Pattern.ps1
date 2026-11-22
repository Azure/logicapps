<#
.SYNOPSIS
Deploys the shared infrastructure and the workflows for one benchmark pattern.

.DESCRIPTION
Creates resource group rg-msgpat-<Pattern>, deploys infra/main.bicep with the Bicep parameters
found in patterns/<Pattern>/params.json, and zip-deploys shared/logicapp plus the pattern's
workflows. Keys in params.json that main.bicep does not declare are ignored by the Bicep step.
If the primary region fails for quota or capacity reasons, the script retries in
params.fallbackLocation and records the region used in results/<Pattern>/deployment.json.

.EXAMPLE
./Deploy-Pattern.ps1 -Pattern 1a-max-throughput
./Deploy-Pattern.ps1 -Pattern 1a-max-throughput -SkipInfra     # redeploy workflows only
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Pattern,
    [string]$Location,
    [switch]$SkipInfra,
    [switch]$SkipCode,
    [switch]$SkipWhatIf
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$kitRoot = Get-KitRoot
$patternDir = Get-PatternDir $Pattern
$params = Get-PatternParams $Pattern
$resultsDir = Get-ResultsDir $Pattern
$resourceGroup = Get-ResourceGroupName $Pattern
$deploymentName = "msgpat-$Pattern"
$stagingRoot = Join-Path $kitRoot ".staging\$Pattern"

if (-not $Location) { $Location = if ($params.location) { $params.location } else { 'westus3' } }
$fallbackLocation = $params.fallbackLocation

function Test-CapacityError([string]$Message) {
    $Message -match 'quota|capacity|SkuNotAvailable|LocationNotAvailableForResourceType|NoRegisteredProviderFound|not available in (the )?location|RegionDoesNotAllowProvisioning|ServiceUnavailable'
}

function Invoke-InfraDeployment([string]$TargetLocation) {
    New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
    $templateFile = Join-Path $stagingRoot 'main.json'
    Invoke-Az bicep build --file (Join-Path $kitRoot 'infra\main.bicep') --outfile $templateFile | Out-Null
    $declared = (Get-Content $templateFile -Raw | ConvertFrom-Json -AsHashtable).parameters.Keys

    $values = @{ patternId = $Pattern; location = $TargetLocation }
    foreach ($key in $params.Keys) {
        if ($declared -contains $key -and $key -ne 'location') { $values[$key] = $params[$key] }
    }
    if ($declared -contains 'userPrincipalId') {
        $values['userPrincipalId'] = (az ad signed-in-user show --query id -o tsv 2>$null)
    }

    $parameterFile = Join-Path $stagingRoot 'main.parameters.json'
    $parameterDocument = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{}
    }
    foreach ($key in ($values.Keys | Sort-Object)) { $parameterDocument.parameters[$key] = @{ value = $values[$key] } }
    $parameterDocument | ConvertTo-Json -Depth 20 | Set-Content -Path $parameterFile -Encoding utf8NoBOM

    if (-not $SkipWhatIf) {
        Write-Host "What-if for $resourceGroup in $TargetLocation..."
        az deployment group what-if -g $resourceGroup -n $deploymentName --template-file $templateFile `
            --parameters "@$parameterFile" --result-format ResourceIdOnly --no-pretty-print | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "What-if failed for $resourceGroup." }
    }

    Write-Host "Deploying infrastructure to $TargetLocation..."
    $raw = az deployment group create -g $resourceGroup -n $deploymentName --template-file $templateFile `
        --parameters "@$parameterFile" -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        $text = ($raw | Out-String)
        return @{ succeeded = $false; error = $text }
    }
    $deployment = ($raw | Where-Object { $_ -is [string] }) -join "`n" | ConvertFrom-Json -AsHashtable
    @{ succeeded = $true; outputs = $deployment.properties.outputs }
}

if (-not $SkipInfra) {
    $existingLocation = az group show -n $resourceGroup --query location -o tsv 2>$null
    if (-not $existingLocation) {
        Invoke-Az group create -n $resourceGroup -l $Location --tags msgpat-pattern=$Pattern -o none
    }

    $usedLocation = $Location
    $result = Invoke-InfraDeployment $Location
    $capacityNote = $null
    if (-not $result.succeeded -and $fallbackLocation -and (Test-CapacityError $result.error)) {
        $capacityNote = "Primary region $Location failed: $(($result.error -split "`n" | Select-Object -First 5) -join ' ')"
        Write-Warning "$capacityNote Retrying in $fallbackLocation."
        $usedLocation = $fallbackLocation
        $result = Invoke-InfraDeployment $fallbackLocation
    }
    if (-not $result.succeeded) { throw "Infrastructure deployment failed:`n$($result.error)" }

    $flat = [ordered]@{
        pattern = $Pattern
        resourceGroup = $resourceGroup
        location = $usedLocation
        requestedLocation = $Location
        capacityNote = $capacityNote
        deployedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    foreach ($key in $result.outputs.Keys) { $flat[$key] = $result.outputs[$key].value }
    $flat | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $resultsDir 'deployment.json') -Encoding utf8NoBOM
    Write-Host "Infrastructure deployed in $usedLocation."
}

if ($SkipCode) { return }

$outputs = Get-DeploymentOutputs $Pattern

# Build the custom code if its assemblies are missing. The build copies them into shared/logicapp/lib/custom.
$customCodeDll = Join-Path $kitRoot 'shared\logicapp\lib\custom\net8\OrderEnricher.dll'
if (-not (Test-Path $customCodeDll)) {
    dotnet build (Join-Path $kitRoot 'shared\customcode\OrderEnricher') -c Release
    if ($LASTEXITCODE -ne 0) { throw "Custom code build failed." }
}

# Build the app content: shared logic app, then the pattern's workflows and artifacts on top.
$appDir = Join-Path $stagingRoot 'app'
if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item -Path (Join-Path $kitRoot 'shared\logicapp\*') -Destination $appDir -Recurse -Force
Get-ChildItem (Join-Path $patternDir 'workflows') -Directory | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $appDir $_.Name) -Recurse -Force
}
$patternArtifacts = Join-Path $patternDir 'Artifacts'
if (Test-Path $patternArtifacts) { Copy-Item -Path $patternArtifacts -Destination $appDir -Recurse -Force }

# Merge host.json: shared base, then patterns/<id>/host.json, then params.hostSettings.
function Merge-Hashtable([hashtable]$Target, [hashtable]$Source) {
    foreach ($key in $Source.Keys) {
        if ($Target[$key] -is [hashtable] -and $Source[$key] -is [hashtable]) { Merge-Hashtable $Target[$key] $Source[$key] }
        else { $Target[$key] = $Source[$key] }
    }
}
$hostFile = Join-Path $appDir 'host.json'
$hostJson = Get-Content $hostFile -Raw | ConvertFrom-Json -AsHashtable
$patternHost = Join-Path $patternDir 'host.json'
if (Test-Path $patternHost) { Merge-Hashtable $hostJson (Get-Content $patternHost -Raw | ConvertFrom-Json -AsHashtable) }
if ($params.hostSettings) {
    foreach ($key in $params.hostSettings.Keys) { $hostJson.extensions.workflow.Settings[$key] = [string]$params.hostSettings[$key] }
}
$hostJson | ConvertTo-Json -Depth 20 | Set-Content -Path $hostFile -Encoding utf8NoBOM

# Optional patterns/<id>/connections.json adds or replaces connections in the shared connections.json.
$patternConnections = Join-Path $patternDir 'connections.json'
if (Test-Path $patternConnections) {
    $connectionsFile = Join-Path $appDir 'connections.json'
    $connections = Get-Content $connectionsFile -Raw | ConvertFrom-Json -AsHashtable
    Merge-Hashtable $connections (Get-Content $patternConnections -Raw | ConvertFrom-Json -AsHashtable)
    $connections | ConvertTo-Json -Depth 20 | Set-Content -Path $connectionsFile -Encoding utf8NoBOM
}

# ZipFile writes forward-slash entry names, which the Kudu zip deploy expects.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipFile = Join-Path $stagingRoot 'app.zip'
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($appDir, $zipFile)

Write-Host "Zip deploying $zipFile to $($outputs.logicAppName)..."
Invoke-Az logicapp deployment source config-zip -g $outputs.resourceGroup -n $outputs.logicAppName --src $zipFile -o none
Write-Host 'Workflows deployed:'
Get-ChildItem $appDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'workflow.json') } | ForEach-Object { "  $($_.Name)" }
