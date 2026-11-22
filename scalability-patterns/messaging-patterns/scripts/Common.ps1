# Shared helpers for the benchmark kit scripts. Dot-source this file; it has no side effects.

$ErrorActionPreference = 'Stop'

$azCliPath = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin'
if ((Test-Path $azCliPath) -and ($env:PATH -notlike "*$azCliPath*")) {
    $env:PATH = "$azCliPath;$env:PATH"
}

$script:KitRoot = Split-Path -Parent $PSScriptRoot

function Get-KitRoot { $script:KitRoot }

function Get-PatternDir([string]$Pattern) {
    $dir = Join-Path $script:KitRoot "patterns\$Pattern"
    if (-not (Test-Path $dir)) { throw "Pattern folder '$dir' does not exist." }
    $dir
}

function Get-PatternParams([string]$Pattern) {
    Get-Content (Join-Path (Get-PatternDir $Pattern) 'params.json') -Raw | ConvertFrom-Json -AsHashtable
}

function Get-ResourceGroupName([string]$Pattern) { "rg-msgpat-$Pattern" }

function Get-ResultsDir([string]$Pattern) {
    $dir = Join-Path $script:KitRoot "results\$Pattern"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dir
}

# Reads the outputs that Deploy-Pattern.ps1 saved; falls back to the deployment in the RG.
function Get-DeploymentOutputs([string]$Pattern) {
    $file = Join-Path (Get-ResultsDir $Pattern) 'deployment.json'
    if (Test-Path $file) { return Get-Content $file -Raw | ConvertFrom-Json -AsHashtable }
    $rg = Get-ResourceGroupName $Pattern
    $outputs = az deployment group show -g $rg -n "msgpat-$Pattern" --query properties.outputs -o json | ConvertFrom-Json -AsHashtable
    if (-not $outputs) { throw "No deployment outputs for '$Pattern'. Run Deploy-Pattern.ps1 first." }
    $flat = @{ resourceGroup = $rg }
    foreach ($key in $outputs.Keys) { $flat[$key] = $outputs[$key].value }
    $flat
}

# Runs az with the given arguments and throws on a non-zero exit code.
function Invoke-Az {
    $output = & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed with exit code $LASTEXITCODE." }
    $output
}

# Finds a Python interpreter that is not the Windows Store stub.
function Get-Python {
    $candidates = @()
    if ($env:MSGPAT_PYTHON) { $candidates += $env:MSGPAT_PYTHON }
    $candidates += (Get-Command python, python3, py -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*WindowsApps*' } | ForEach-Object Source)
    $candidates += 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
    # Packages installed with 'pip install --target .tools/pylib' are found without a virtual environment.
    $pylib = Join-Path $script:KitRoot '.tools\pylib'
    if ((Test-Path $pylib) -and ($env:PYTHONPATH -notlike "*$pylib*")) {
        $env:PYTHONPATH = if ($env:PYTHONPATH) { "$pylib;$env:PYTHONPATH" } else { $pylib }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    throw 'No Python interpreter found. Set MSGPAT_PYTHON to python.exe.'
}

function Invoke-AppInsightsQuery {
    <#
    .SYNOPSIS
    Runs a KQL query against an Application Insights resource and returns rows as objects.
    #>
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Query,
        [string]$Timespan
    )
    $body = @{ query = $Query }
    if ($Timespan) { $body.timespan = $Timespan }
    $stagingDir = Join-Path $script:KitRoot '.staging'
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
    $bodyFile = Join-Path $stagingDir ("kql-" + [guid]::NewGuid() + ".json")
    try {
        $body | ConvertTo-Json -Depth 5 | Set-Content -Path $bodyFile -Encoding utf8NoBOM
        $raw = az rest --method post --uri "https://api.applicationinsights.io/v1/apps/$AppId/query" `
            --resource "https://api.applicationinsights.io" --headers "Content-Type=application/json" `
            --body "@$bodyFile" -o json 2>&1
        if ($LASTEXITCODE -ne 0) { throw "App Insights query failed: $raw" }
        $result = ($raw -join "`n") | ConvertFrom-Json
        $table = $result.tables[0]
        foreach ($row in $table.rows) {
            $obj = [ordered]@{}
            for ($i = 0; $i -lt $table.columns.Count; $i++) { $obj[$table.columns[$i].name] = $row[$i] }
            [pscustomobject]$obj
        }
    }
    finally { Remove-Item $bodyFile -ErrorAction SilentlyContinue }
}

function Get-KqlFileText {
    <#
    .SYNOPSIS
    Reads a KQL file from scripts/queries and substitutes {{name}} tokens.
    #>
    param([Parameter(Mandatory)][string]$Name, [hashtable]$Tokens = @{})
    $path = Join-Path $script:KitRoot "scripts\queries\$Name.kql"
    $text = Get-Content -Raw -Path $path
    foreach ($key in $Tokens.Keys) { $text = $text.Replace("{{$key}}", [string]$Tokens[$key]) }
    $text
}
