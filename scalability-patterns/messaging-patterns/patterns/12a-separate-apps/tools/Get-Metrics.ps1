<#
.SYNOPSIS
Collects Azure Monitor metrics for every Logic App and plan in the pattern's resource group:
site MemoryWorkingSet and plan CpuPercentage/MemoryPercentage, per minute. The kit's
Export-Results.ps1 has no memory metric, and performanceCounters is empty for these apps.
#>
param(
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][datetime]$StartUtc,
    [Parameter(Mandatory)][datetime]$EndUtc,
    [string]$RunId = 'adhoc'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\Common.ps1')
$rg = Get-ResourceGroupName $Pattern
$outDir = Join-Path (Get-ResultsDir $Pattern) "$RunId\custom"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$start = $StartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$end = $EndUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

function Get-Series([string]$ResourceId, [string]$Metric) {
    $raw = az monitor metrics list --resource $ResourceId --metric $Metric --start-time $start --end-time $end `
        --interval PT1M --aggregation Average Maximum -o json | ConvertFrom-Json
    @($raw.value[0].timeseries | ForEach-Object { $_.data }) | Where-Object { $null -ne $_.maximum }
}

$summary = @()
$resources = az resource list -g $rg -o json | ConvertFrom-Json
foreach ($site in $resources | Where-Object { $_.type -eq 'Microsoft.Web/sites' }) {
    $points = Get-Series $site.id 'MemoryWorkingSet'
    $summary += [pscustomobject]@{
        resource = $site.name; metric = 'MemoryWorkingSetMB'
        avg = [math]::Round((($points | Measure-Object average -Average).Average) / 1MB, 0)
        max = [math]::Round((($points | Measure-Object maximum -Maximum).Maximum) / 1MB, 0)
        points = $points.Count
    }
}
foreach ($plan in $resources | Where-Object { $_.type -eq 'Microsoft.Web/serverFarms' }) {
    foreach ($metric in 'CpuPercentage', 'MemoryPercentage') {
        $points = Get-Series $plan.id $metric
        $summary += [pscustomobject]@{
            resource = $plan.name; metric = $metric
            avg = [math]::Round(($points | Measure-Object average -Average).Average, 1)
            max = [math]::Round(($points | Measure-Object maximum -Maximum).Maximum, 1)
            points = $points.Count
        }
    }
}
$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $outDir 'metrics.json') -Encoding utf8NoBOM
$summary | Format-Table -AutoSize | Out-Host
