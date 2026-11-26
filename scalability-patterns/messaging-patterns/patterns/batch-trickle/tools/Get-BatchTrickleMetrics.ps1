<#
.SYNOPSIS
Runs the batch-trickle queries\*.kql for a run window, exports Service Bus and plan metrics,
saves JSON and CSV in results\batch-trickle\<RunId>, and draws the charts.

.EXAMPLE
./Get-BatchTrickleMetrics.ps1 -RunId run-20261125-231224 -StartUtc 2026-11-25T23:12:00Z -EndUtc 2026-11-25T23:42:00Z
#>
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][datetime]$StartUtc,
    [Parameter(Mandatory)][datetime]$EndUtc
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\Common.ps1')
$pattern = 'batch-trickle'
$resourceGroup = Get-ResourceGroupName $pattern
$outputs = Get-DeploymentOutputs $pattern
$runDir = Join-Path (Get-ResultsDir $pattern) $RunId
$outDir = Join-Path $runDir 'custom'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$start = $StartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$end = $EndUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '..\queries') -Filter *.kql) {
    $text = (Get-Content -Raw $file.FullName).Replace('{{startUtc}}', $start).Replace('{{endUtc}}', $end)
    $rows = @(Invoke-AppInsightsQuery -AppId $outputs.appInsightsAppId -Timespan 'P1D' -Query $text)
    $rows | ConvertTo-Json -Depth 5 -AsArray | Set-Content (Join-Path $outDir ($file.BaseName + '.json')) -Encoding utf8NoBOM
    if ($rows.Count -gt 0) { $rows | Export-Csv (Join-Path $outDir ($file.BaseName + '.csv')) -NoTypeInformation -Encoding utf8NoBOM }
    Write-Host "$($file.BaseName): $($rows.Count) rows"
}

# Service Bus queue metrics at one-minute grain. Export-PlanMetrics.ps1 reads its window from this file.
$namespaceId = az resource list -g $resourceGroup --resource-type Microsoft.ServiceBus/namespaces --query '[0].id' -o tsv
$raw = az monitor metrics list --resource $namespaceId --metrics IncomingMessages CompleteMessage ActiveMessages DeadletteredMessages `
    --interval PT1M --aggregation Total Average Maximum --start-time $start --end-time $end -o json
$metrics = ($raw -join "`n") | ConvertFrom-Json
$byMinute = [ordered]@{}
foreach ($metric in $metrics.value) {
    foreach ($point in $metric.timeseries[0].data) {
        $key = ([datetime]$point.timeStamp).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not $byMinute.Contains($key)) { $byMinute[$key] = [ordered]@{ minute = $key } }
        $value = switch ($metric.name.value) {
            'ActiveMessages' { $point.maximum }
            'DeadletteredMessages' { $point.maximum }
            default { $point.total }
        }
        $byMinute[$key][$metric.name.value] = $value
    }
}
$byMinute.Values | ForEach-Object { [pscustomobject]$_ } | Export-Csv (Join-Path $runDir 'servicebus-metrics.csv') -NoTypeInformation -Encoding utf8NoBOM

& (Join-Path $PSScriptRoot '..\..\..\scripts\Export-PlanMetrics.ps1') -RunFolder $runDir -ResourceGroup $resourceGroup
& (Get-Python) (Join-Path $PSScriptRoot 'New-BatchTrickleChart.py') $runDir
