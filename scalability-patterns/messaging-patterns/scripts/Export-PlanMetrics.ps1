<#
.SYNOPSIS
    Exports App Service plan CPU and memory for a benchmark run.

.DESCRIPTION
    Reads the run window from servicebus-metrics.csv in the run folder, then reads
    CpuPercentage and MemoryPercentage for every App Service plan in the sample's
    resource group at one-minute grain. Writes plan-metrics.csv to the run folder.
    Azure Monitor keeps platform metrics for 93 days, so export soon after the run.

.EXAMPLE
    ./Export-PlanMetrics.ps1 -RunFolder ../results/batch-steady-drain/run-20261126-015557 `
        -ResourceGroup rg-msgpat-batch-steady-drain
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RunFolder,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [string] $Subscription
)

$ErrorActionPreference = 'Stop'

$subscriptionArgs = @()
if ($Subscription) { $subscriptionArgs = @('--subscription', $Subscription) }

$serviceBusRows = Import-Csv (Join-Path $RunFolder 'servicebus-metrics.csv')
$minutes = $serviceBusRows | ForEach-Object { [datetime]::Parse($_.minute).ToUniversalTime() } | Sort-Object
$startTime = $minutes[0].ToString('yyyy-MM-ddTHH:mm:ssZ')
$endTime = $minutes[-1].AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ssZ')

$planIds = az resource list --resource-group $ResourceGroup --resource-type Microsoft.Web/serverfarms `
    --query '[].id' -o tsv @subscriptionArgs
if (-not $planIds) { throw "No App Service plan found in resource group '$ResourceGroup'." }

$rows = foreach ($planId in @($planIds)) {
    $planName = ($planId -split '/')[-1]
    $raw = az monitor metrics list --resource $planId --metrics CpuPercentage MemoryPercentage `
        --interval PT1M --aggregation Average Maximum --start-time $startTime --end-time $endTime -o json
    $metrics = ($raw -join "`n") | ConvertFrom-Json
    $byMinute = @{}
    foreach ($metric in $metrics.value) {
        foreach ($point in $metric.timeseries.data) {
            $key = ([datetime]$point.timeStamp).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            if (-not $byMinute.ContainsKey($key)) {
                $byMinute[$key] = [ordered]@{ minute = $key; plan = $planName }
            }

            $byMinute[$key]["$($metric.name.value)Avg"] = $point.average
            $byMinute[$key]["$($metric.name.value)Max"] = $point.maximum
        }
    }

    $byMinute.Keys | Sort-Object | ForEach-Object {
        $entry = $byMinute[$_]
        [pscustomobject]@{
            minute = $entry.minute
            plan = $entry.plan
            cpuAvg = $entry['CpuPercentageAvg']
            cpuMax = $entry['CpuPercentageMax']
            memoryAvg = $entry['MemoryPercentageAvg']
            memoryMax = $entry['MemoryPercentageMax']
        }
    }
}

$rows | Export-Csv (Join-Path $RunFolder 'plan-metrics.csv') -NoTypeInformation -Encoding utf8NoBOM
Write-Host "  plan-metrics : $(@($rows).Count) rows"
