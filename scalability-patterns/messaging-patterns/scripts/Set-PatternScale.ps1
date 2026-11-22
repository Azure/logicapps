<#
.SYNOPSIS
    Scales a pattern's Logic App and plan down to the minimum (or back up to params.json values).
.DESCRIPTION
    -Down sets the plan's maximum burst to 1, the site's always-ready instances to 1, and stops the app,
    so the resource group costs close to nothing between runs. It never deletes the resource group.
    -Up restores maximumElasticWorkerCount and minimumElasticInstanceCount from params.json and starts the app.
.EXAMPLE
    ./scripts/Set-PatternScale.ps1 -Pattern 1a-max-throughput -Down
#>
[CmdletBinding(DefaultParameterSetName = 'Down')]
param(
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(ParameterSetName = 'Down')][switch]$Down,
    [Parameter(ParameterSetName = 'Up')][switch]$Up,
    [Parameter(ParameterSetName = 'Down')][switch]$KeepRunning
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$outputs = Get-DeploymentOutputs $Pattern
$params = Get-PatternParams $Pattern
$rg = $outputs.resourceGroup
$app = $outputs.logicAppName
$plan = $outputs.planName

if ($Up) {
    $maxBurst = if ($params.ContainsKey('maximumElasticWorkerCount')) { $params.maximumElasticWorkerCount } else { 20 }
    $minInstances = if ($params.ContainsKey('minimumElasticInstanceCount')) { $params.minimumElasticInstanceCount } else { 1 }
    Write-Host "Scaling $plan up: max burst $maxBurst, always-ready $minInstances; starting $app."
    Invoke-Az appservice plan update -g $rg -n $plan --max-elastic-worker-count $maxBurst -o none
    Invoke-Az resource update -g $rg -n "$app/config/web" --resource-type Microsoft.Web/sites/config `
        --set "properties.minimumElasticInstanceCount=$minInstances" -o none
    Invoke-Az logicapp start -g $rg -n $app -o none
}
else {
    Write-Host "Scaling $plan down: max burst 1, always-ready 1."
    Invoke-Az resource update -g $rg -n "$app/config/web" --resource-type Microsoft.Web/sites/config `
        --set 'properties.minimumElasticInstanceCount=1' -o none
    Invoke-Az appservice plan update -g $rg -n $plan --max-elastic-worker-count 1 -o none
    if (-not $KeepRunning) {
        Write-Host "Stopping $app (resource group is kept)."
        Invoke-Az logicapp stop -g $rg -n $app -o none
    }
}

$planState = Invoke-Az resource show -g $rg -n $plan --resource-type Microsoft.Web/serverfarms --query '{sku:sku.name, maxBurst:properties.maximumElasticWorkerCount}' -o json | ConvertFrom-Json
$siteState = Invoke-Az resource show -g $rg -n $app --resource-type Microsoft.Web/sites --query '{state:properties.state}' -o json | ConvertFrom-Json
Write-Host "Plan $plan sku=$($planState.sku) maxBurst=$($planState.maxBurst); app $app state=$($siteState.state)."
