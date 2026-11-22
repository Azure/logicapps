<#
.SYNOPSIS
Runs the 4-trickle queries\*.kql for a run window, saves JSON and CSV in results\4-trickle\<RunId>\custom,
and draws a per-message latency chart (trickle-latency.png).
#>
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][datetime]$StartUtc,
    [Parameter(Mandatory)][datetime]$EndUtc
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\Common.ps1')
$outputs = Get-DeploymentOutputs '4-trickle'
$outDir = Join-Path (Get-ResultsDir '4-trickle') "$RunId\custom"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '..\queries') -Filter *.kql) {
    $text = (Get-Content -Raw $file.FullName).
        Replace('{{startUtc}}', $StartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')).
        Replace('{{endUtc}}', $EndUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    $rows = @(Invoke-AppInsightsQuery -AppId $outputs.appInsightsAppId -Query $text)
    $rows | ConvertTo-Json -Depth 5 -AsArray | Set-Content (Join-Path $outDir ($file.BaseName + '.json')) -Encoding utf8NoBOM
    if ($rows.Count -gt 0) { $rows | Export-Csv (Join-Path $outDir ($file.BaseName + '.csv')) -NoTypeInformation -Encoding utf8NoBOM }
    Write-Host "$($file.BaseName): $($rows.Count) rows"
}
& (Get-Python) (Join-Path $PSScriptRoot 'New-TrickleChart.py') $outDir
