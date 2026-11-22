<#
.SYNOPSIS
Exports the measurements for a pattern run to results/<Pattern>/<RunId>/.

.DESCRIPTION
Reads results/<Pattern>/last-run.json (or -RunId, or -StartUtc/-EndUtc) for the time window and
results/<Pattern>/deployment.json for the resource names. The script then:
  * runs every scripts/queries/*.kql against Application Insights and writes <query>.csv and <query>.json;
  * reads Service Bus metrics per entity (ActiveMessages, IncomingMessages, CompleteMessage,
    DeadletteredMessages) at one-minute grain into servicebus-metrics.csv;
  * writes summary.json with the headline numbers.
New-Charts.py turns the folder into PNG charts.

.EXAMPLE
./scripts/Export-Results.ps1 -Pattern 1a-max-throughput
./scripts/Export-Results.ps1 -Pattern 1a-max-throughput -RunId run-20261122-061500
./scripts/Export-Results.ps1 -Pattern 1a-max-throughput -StartUtc 2026-11-22T06:00:00Z -EndUtc 2026-11-22T06:30:00Z
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Pattern,
    [string]$RunId,
    [datetime]$StartUtc,
    [datetime]$EndUtc,
    [int]$IngestionDelayMinutes = 3,
    [switch]$SkipCharts
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$outputs = Get-DeploymentOutputs $Pattern
$params = Get-PatternParams $Pattern
$resultsDir = Get-ResultsDir $Pattern

$run = $null
$runFile = if ($RunId) { Join-Path $resultsDir "$RunId.run.json" } else { Join-Path $resultsDir 'last-run.json' }
if (Test-Path $runFile) { $run = Get-Content $runFile -Raw | ConvertFrom-Json -AsHashtable }

if (-not $PSBoundParameters.ContainsKey('StartUtc')) {
    if (-not $run) { throw "No run record at '$runFile'. Pass -StartUtc and -EndUtc." }
    $StartUtc = ([datetime]$run.startUtc).ToUniversalTime().AddMinutes(-1)
}
if (-not $PSBoundParameters.ContainsKey('EndUtc')) {
    $EndUtc = if ($run -and $run.endUtc) { ([datetime]$run.endUtc).ToUniversalTime() } else { (Get-Date).ToUniversalTime() }
}
$StartUtc = $StartUtc.ToUniversalTime()
$EndUtc = $EndUtc.ToUniversalTime()
if (-not $RunId) { $RunId = if ($run) { $run.testRunId } else { 'window-' + $StartUtc.ToString('yyyyMMdd-HHmmss') } }

# App Insights ingestion lags a few minutes behind the clock.
$readyAt = $EndUtc.AddMinutes($IngestionDelayMinutes)
$wait = ($readyAt - (Get-Date).ToUniversalTime()).TotalSeconds
if ($wait -gt 0) {
    Write-Host "Waiting $([int]$wait)s for App Insights ingestion."
    Start-Sleep -Seconds ([int]$wait)
}

$workflowName = if ($params.measurement -and $params.measurement.workflowName) {
    $params.measurement.workflowName
}
else {
    $workflows = Get-ChildItem (Join-Path (Get-PatternDir $Pattern) 'workflows') -Directory
    if ($workflows.Count -ne 1) { throw "Set measurement.workflowName in params.json; the pattern has $($workflows.Count) workflows." }
    $workflows[0].Name
}

$outDir = Join-Path $resultsDir $RunId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$tokens = @{
    startUtc = $StartUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    endUtc = $EndUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    workflowName = $workflowName
}
Write-Host "Exporting $Pattern ($workflowName) from $($tokens.startUtc) to $($tokens.endUtc) into $outDir."

# ConvertFrom-Json turns timestamps into DateTime, which Export-Csv writes in the local culture.
# Write them as ISO 8601 UTC so the CSVs parse the same way on any machine.
function ConvertTo-IsoRow($row) {
    $copy = [ordered]@{}
    foreach ($property in $row.PSObject.Properties) {
        $value = $property.Value
        if ($value -is [datetime]) { $value = $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
        elseif ($value -is [datetimeoffset]) { $value = $value.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
        $copy[$property.Name] = $value
    }
    [pscustomobject]$copy
}

$queryResults = @{}
foreach ($file in Get-ChildItem (Join-Path (Get-KitRoot) 'scripts\queries') -Filter '*.kql') {
    $name = $file.BaseName
    try {
        $rows = @(Invoke-AppInsightsQuery -AppId $outputs.appInsightsAppId -Query (Get-KqlFileText -Name $name -Tokens $tokens) | ForEach-Object { ConvertTo-IsoRow $_ })
        $queryResults[$name] = $rows
        $rows | ConvertTo-Json -Depth 5 -AsArray | Set-Content (Join-Path $outDir "$name.json") -Encoding utf8NoBOM
        if ($rows.Count -gt 0) { $rows | Export-Csv (Join-Path $outDir "$name.csv") -NoTypeInformation -Encoding utf8NoBOM }
        Write-Host "  $name : $($rows.Count) rows"
    }
    catch { Write-Warning "Query '$name' failed: $_" }
}

# Service Bus metrics, one row per minute and entity.
$entities = @()
if ($params.queues) { $entities += $params.queues | ForEach-Object { $_.name } }
if ($params.topics) { $entities += $params.topics | ForEach-Object { $_.name } }
$metricNames = 'ActiveMessages', 'IncomingMessages', 'CompleteMessage', 'DeadletteredMessages'
$sbRows = @{}
foreach ($entity in $entities) {
    $raw = Invoke-Az monitor metrics list --resource $outputs.serviceBusId --metrics @metricNames `
        --filter "EntityName eq '$entity'" --interval PT1M --aggregation Average Total Maximum `
        --start-time $tokens.startUtc --end-time $tokens.endUtc -o json
    $metrics = ($raw -join "`n") | ConvertFrom-Json
    foreach ($metric in $metrics.value) {
        foreach ($series in $metric.timeseries) {
            foreach ($point in $series.data) {
                $key = "$entity|$($point.timeStamp)"
                if (-not $sbRows[$key]) {
                    $sbRows[$key] = [ordered]@{ minute = $point.timeStamp; entity = $entity; activeMessages = 0; incomingMessages = 0; completeMessages = 0; deadletteredMessages = 0 }
                }
                switch ($metric.name.value) {
                    'ActiveMessages' { $sbRows[$key].activeMessages = [double]($point.maximum ?? $point.average ?? 0) }
                    'DeadletteredMessages' { $sbRows[$key].deadletteredMessages = [double]($point.maximum ?? $point.average ?? 0) }
                    'IncomingMessages' { $sbRows[$key].incomingMessages = [double]($point.total ?? 0) }
                    'CompleteMessage' { $sbRows[$key].completeMessages = [double]($point.total ?? 0) }
                }
            }
        }
    }
}
$sbTable = @($sbRows.Values | ForEach-Object { ConvertTo-IsoRow ([pscustomobject]$_) } | Sort-Object entity, minute)
if ($sbTable.Count -gt 0) { $sbTable | Export-Csv (Join-Path $outDir 'servicebus-metrics.csv') -NoTypeInformation -Encoding utf8NoBOM }
Write-Host "  servicebus-metrics : $($sbTable.Count) rows"

$loadQueue = if ($params.loadTest -and $params.loadTest.queueName) { $params.loadTest.queueName } elseif ($params.loadTest.env.SB_TOPIC) { $params.loadTest.env.SB_TOPIC } else { $entities | Select-Object -First 1 }
$loadRows = @($sbTable | Where-Object entity -eq $loadQueue)
$kql = if ($queryResults['summary']) { $queryResults['summary'] | Select-Object -First 1 } else { $null }
$summary = [ordered]@{
    pattern = $Pattern
    runId = $RunId
    workflowName = $workflowName
    windowStartUtc = $tokens.startUtc
    windowEndUtc = $tokens.endUtc
    targetMessagesPerSecond = $run.targetMessagesPerSecond
    loadDurationMinutes = $run.durationMinutes
    loadTestStatus = $run.status
    loadTestResult = $run.testResult
    loadEntity = $loadQueue
    messagesSent = [int](($loadRows | Measure-Object incomingMessages -Sum).Sum)
    messagesCompletedByBroker = [int](($loadRows | Measure-Object completeMessages -Sum).Sum)
    peakQueueBacklog = [int](($loadRows | Measure-Object activeMessages -Maximum).Maximum)
    deadletteredAtEnd = [int](($loadRows | Select-Object -Last 1).deadletteredMessages)
    runsCompleted = $kql.runsCompleted
    runsSucceeded = $kql.runsSucceeded
    runsFailed = $kql.runsFailed
    avgMessagesPerSecond = $kql.avgMessagesPerSecond
    peakRunsPerSecond = $kql.peakRunsPerSecond
    runDurationMs = [ordered]@{ p50 = $kql.runP50; p95 = $kql.runP95; p99 = $kql.runP99 }
    endToEndLatencyMs = [ordered]@{ p50 = $kql.e2eP50; p95 = $kql.e2eP95; p99 = $kql.e2eP99 }
    maxInstances = $kql.maxInstances
    firstSentUtc = $kql.firstSent
    lastFinishedUtc = $kql.lastFinished
    drainSeconds = $kql.drainSeconds
    failedActions = [int](($queryResults['failures'] | Measure-Object failedActions -Sum).Sum)
    exceptions = [int](($queryResults['failures'] | Measure-Object exceptions -Sum).Sum)
    portalUrl = $run.portalUrl
}
$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $outDir 'summary.json') -Encoding utf8NoBOM
Write-Host ($summary | ConvertTo-Json -Depth 5)
Write-Host "Results written to $outDir."
if (-not $SkipCharts) {
    $python = Get-Python
    & $python (Join-Path $PSScriptRoot 'New-Charts.py') $outDir
    if ($LASTEXITCODE -ne 0) { Write-Warning "New-Charts.py failed. Install matplotlib (see README) and rerun: python scripts/New-Charts.py $outDir" }
}
