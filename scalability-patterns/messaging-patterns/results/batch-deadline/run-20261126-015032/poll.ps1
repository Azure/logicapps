$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
$folder = $PSScriptRoot
$t0 = [datetime]::Parse((Get-Content (Join-Path $folder 't0.txt')).Trim()).ToUniversalTime()
$csv = Join-Path $folder 'backlog.csv'
if (-not (Test-Path $csv)) { 'utc,elapsedSeconds,active' | Set-Content $csv }
$zeroCount = 0
while ($true) {
    $json = az servicebus queue show -g rg-msgpat-batch-deadline --namespace-name sb-msgpat-batchdeadl-njv4cr -n orders -o json 2>$null
    try {
        $queue = $json | ConvertFrom-Json
        $now = [datetime]::UtcNow
        $active = $queue.countDetails.activeMessageCount
        $elapsed = [int]($now - $t0).TotalSeconds
        "$($now.ToString('yyyy-MM-ddTHH:mm:ssZ')),$elapsed,$active" | Add-Content $csv
        Write-Output "$elapsed $active"
        if ($active -eq 0) { $zeroCount++ } else { $zeroCount = 0 }
        if ($zeroCount -ge 6 -or $elapsed -gt 3600) { break }
    }
    catch { Write-Output "poll error" }
    Start-Sleep 10
}
