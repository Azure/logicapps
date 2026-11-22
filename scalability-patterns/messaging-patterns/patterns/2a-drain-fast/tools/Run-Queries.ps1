<#
.SYNOPSIS
Runs this pattern's queries\*.kql for a time window and saves the rows as JSON in results\<pattern>.
#>
param(
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][datetime]$StartUtc,
    [Parameter(Mandatory)][datetime]$EndUtc,
    [string]$RunId = 'adhoc'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\Common.ps1')
$params = Get-PatternParams $Pattern
$outputs = Get-DeploymentOutputs $Pattern
$outDir = Join-Path (Get-ResultsDir $Pattern) "$RunId\custom"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '..\queries') -Filter *.kql) {
    $text = (Get-Content -Raw $file.FullName).
        Replace('{{startUtc}}', $StartUtc.ToUniversalTime().ToString('o')).
        Replace('{{endUtc}}', $EndUtc.ToUniversalTime().ToString('o')).
        Replace('{{workflowName}}', $params.measurement.workflowName)
    $rows = @(Invoke-AppInsightsQuery -AppId $outputs.appInsightsAppId -Query $text)
    $rows | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $outDir ($file.BaseName + '.json')) -Encoding utf8NoBOM
    Write-Host "$($file.BaseName): $($rows.Count) rows"
}
