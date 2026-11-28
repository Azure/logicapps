param([string]$Rg, [string]$Ns, [string]$App, [string]$Out, [int]$Minutes = 40, [int]$Seconds = 30)
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$sub = "21196cdf-abb2-4697-9f73-feef0db7cb2a"
if (-not (Test-Path $Out)) { "utc,active,dlq,instances" | Set-Content $Out }
$end = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $end) {
    $q = & $az servicebus queue show --subscription $sub -g $Rg --namespace-name $Ns -n orders -o json 2>$null | ConvertFrom-Json; $q=$q.countDetails
    $inst = & $az rest --method get --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$Rg/providers/Microsoft.Web/sites/$App/instances?api-version=2023-12-01" -o json 2>$null | ConvertFrom-Json; $inst=@($inst.value).Count
    "$((Get-Date).ToUniversalTime().ToString('o')),$($q.activeMessageCount),$($q.deadLetterMessageCount),$inst" | Add-Content $Out
    Start-Sleep $Seconds
}

