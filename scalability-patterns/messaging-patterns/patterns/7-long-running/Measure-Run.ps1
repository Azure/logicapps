<#
.SYNOPSIS
Runs the pattern 7 queries and collects memory and dead-letter metrics for one run window.
.DESCRIPTION
Export-Results.ps1 covers one workflow and does not collect memory. This script adds the
pattern 7 queries (both workflows) and the app and queue metrics. Output goes to
results/7-long-running/<RunId>/pattern7/.
#>
param(
    [Parameter(Mandatory)] [string] $RunId,
    [Parameter(Mandatory)] [datetime] $StartUtc,
    [Parameter(Mandatory)] [datetime] $EndUtc
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$dep = Get-Content (Join-Path $root 'results\7-long-running\deployment.json') | ConvertFrom-Json
$out = Join-Path $root "results\7-long-running\$RunId\pattern7"
New-Item -ItemType Directory -Force $out | Out-Null
$s = $StartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$e = $EndUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
foreach ($q in Get-ChildItem (Join-Path $PSScriptRoot 'queries\*.kql')) {
    $text = (Get-Content $q -Raw).Replace('{{startUtc}}', $s).Replace('{{endUtc}}', $e)
    $text = ($text -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    $token = az account get-access-token --resource https://api.applicationinsights.io --query accessToken -o tsv
    $body = @{ query = $text } | ConvertTo-Json
    $rows = Invoke-RestMethod -Method Post -Uri "https://api.applicationinsights.io/v1/apps/$($dep.appInsightsAppId)/query" -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
    $t = $rows.tables[0]
    $cols = $t.columns.name
    $objs = foreach ($r in $t.rows) { $o = [ordered]@{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }; [pscustomobject]$o }
    $objs | Export-Csv -NoTypeInformation (Join-Path $out ($q.BaseName + '.csv'))
    "  $($q.BaseName): $(@($objs).Count) rows"
}
$mem = az monitor metrics list --resource $dep.logicAppId --metric MemoryWorkingSet --interval PT1M --aggregation Maximum Average --start-time $s --end-time $e -o json | ConvertFrom-Json
$mem.value[0].timeseries[0].data | Select-Object timeStamp, average, maximum | Export-Csv -NoTypeInformation (Join-Path $out 'memory.csv')
$sb = az monitor metrics list --resource $dep.serviceBusId --metric DeadletteredMessages ActiveMessages --interval PT1M --aggregation Maximum --filter "EntityName eq '*'" --start-time $s --end-time $e -o json | ConvertFrom-Json
$sbRows = foreach ($m in $sb.value) { foreach ($ts in $m.timeseries) { foreach ($d in $ts.data) { [pscustomobject]@{ metric = $m.name.value; entity = $ts.metadatavalues[0].value; timeStamp = $d.timeStamp; maximum = $d.maximum } } } }
$sbRows | Export-Csv -NoTypeInformation (Join-Path $out 'servicebus-deadletter-active.csv')
"  memory and Service Bus metrics written to $out"

