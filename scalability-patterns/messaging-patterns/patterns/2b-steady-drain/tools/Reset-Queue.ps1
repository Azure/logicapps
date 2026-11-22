<#
.SYNOPSIS
Empties the pattern's queues before a run by deleting and recreating each queue with the
settings in params.json. Roles are assigned at namespace scope, so they survive.
#>
param([Parameter(Mandatory)][string]$Pattern)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\Common.ps1')
$params = Get-PatternParams $Pattern
$outputs = Get-DeploymentOutputs $Pattern
$rg = Get-ResourceGroupName $Pattern
$ns = $outputs.serviceBusFqdn.Split('.')[0]
foreach ($queue in $params.queues) {
    az servicebus queue delete -g $rg --namespace-name $ns -n $queue.name -o none
    az servicebus queue create -g $rg --namespace-name $ns -n $queue.name --lock-duration $queue.lockDuration `
        --max-delivery-count $queue.maxDeliveryCount --max-size $queue.maxSizeInMegabytes -o none
    if ($LASTEXITCODE -ne 0) { throw "Could not recreate queue '$($queue.name)'." }
    $count = (az servicebus queue show -g $rg --namespace-name $ns -n $queue.name -o json | ConvertFrom-Json).countDetails.activeMessageCount
    Write-Host "Queue '$($queue.name)' recreated, active messages: $count"
}
