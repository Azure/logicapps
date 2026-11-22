<#
.SYNOPSIS
Switches the bulk workflow between the capped orders-low (default) and the uncapped baseline
orders-low-nocap. Both read the orders-low queue, so only one is enabled at a time. A separate
workflow is used because removing trigger concurrency from a deployed workflow is not supported.
#>
param(
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][ValidateSet('capped', 'nocap')][string]$Variant
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\Common.ps1')
$outputs = Get-DeploymentOutputs $Pattern
$capped = if ($Variant -eq 'capped') { 'Enabled' } else { 'Disabled' }
$nocap = if ($Variant -eq 'nocap') { 'Enabled' } else { 'Disabled' }
az logicapp config appsettings set -g $outputs.resourceGroup -n $outputs.logicAppName `
    --settings "Workflows.orders-low.FlowState=$capped" "Workflows.orders-low-nocap.FlowState=$nocap" -o none
if ($LASTEXITCODE -ne 0) { throw 'Could not update the workflow states.' }
Write-Host "orders-low: $capped, orders-low-nocap: $nocap"
