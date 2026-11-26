<#
.SYNOPSIS
Adds VNet integration and two VNet private ports to the pattern 7 Logic App.

.DESCRIPTION
A Stateful workflow that settles or renews a peek-lock message in a later action needs the
message to come back to the instance that holds the lock. The runtime reaches that instance
through a VNet private port. Without VNet integration and siteConfig.vnetPrivatePortsCount of
2 or more, completeMessage, abandonMessage and renewLockMessage fail in a Stateful run with
VNetPrivatePortsNotConfigured.

The script creates a VNet and a subnet delegated to Microsoft.Web/serverFarms, integrates the
app with the subnet, sets vnetPrivatePortsCount, and restarts the app. It also sets the
SlowDownstreamUrl app setting that the hold-the-lock workflows call. Run it after every
Deploy-Pattern.ps1 run that deploys the infrastructure, because that deployment replaces the
site configuration and app settings and removes these settings.

.EXAMPLE
./Set-VnetPorts.ps1
./Set-VnetPorts.ps1 -PortCount 2
#>
[CmdletBinding()]
param(
    [int]$PortCount = 2,
    [string]$VnetName = 'vnet-msgpat-7longrunning',
    [string]$AddressPrefix = '10.70.0.0/16',
    [string]$SubnetName = 'snet-logicapp',
    [string]$SubnetPrefix = '10.70.1.0/24'
)

. (Join-Path $PSScriptRoot '..\..\scripts\Common.ps1')

if ($PortCount -lt 2) { throw 'PortCount must be 2 or more.' }

$pattern = Split-Path -Leaf $PSScriptRoot
$outputs = Get-DeploymentOutputs $pattern
$resourceGroup = $outputs.resourceGroup
$appName = $outputs.logicAppName
$location = az group show -n $resourceGroup --query location -o tsv

if (-not (az network vnet show -g $resourceGroup -n $VnetName --query id -o tsv 2>$null)) {
    Write-Host "Creating VNet $VnetName..."
    Invoke-Az network vnet create -g $resourceGroup -n $VnetName -l $location --address-prefixes $AddressPrefix -o none
}
$subnetId = az network vnet subnet show -g $resourceGroup --vnet-name $VnetName -n $SubnetName --query id -o tsv 2>$null
if (-not $subnetId) {
    Write-Host "Creating subnet $SubnetName delegated to Microsoft.Web/serverFarms..."
    $subnetId = Invoke-Az network vnet subnet create -g $resourceGroup --vnet-name $VnetName -n $SubnetName `
        --address-prefixes $SubnetPrefix --delegations Microsoft.Web/serverFarms --query id -o tsv
}

$siteId = az resource show -g $resourceGroup -n $appName --resource-type Microsoft.Web/sites --query id -o tsv
Write-Host "Integrating $appName with $SubnetName..."
Invoke-Az resource update --ids $siteId --set "properties.virtualNetworkSubnetId=$subnetId" -o none

Write-Host "Setting vnetPrivatePortsCount to $PortCount..."
Invoke-Az resource update --ids "$siteId/config/web" --set "properties.vnetPrivatePortsCount=$PortCount" -o none

Invoke-Az logicapp restart -g $resourceGroup -n $appName -o none
Invoke-Az logicapp start -g $resourceGroup -n $appName -o none

# The hold-the-lock workflows call slow-downstream through the SlowDownstreamUrl app setting.
# The infrastructure deployment replaces the app settings, so set it again here.
Write-Host 'Setting SlowDownstreamUrl to the slow-downstream callback URL...'
$callbackUri = "https://management.azure.com$siteId/hostruntime/runtime/webhooks/workflow/api/management/workflows/slow-downstream/triggers/manual/listCallbackUrl?api-version=2022-03-01"
$callbackUrl = $null
for ($attempt = 1; $attempt -le 12 -and -not $callbackUrl; $attempt++) {
    $callbackUrl = az rest --method post --uri $callbackUri --query value -o tsv 2>$null
    if (-not $callbackUrl) { Start-Sleep -Seconds 10 }
}
if (-not $callbackUrl) { throw 'Could not get the slow-downstream callback URL. Check that the app is running.' }
# NOTE: The callback URL contains '&', which az.cmd splits on, so pass the setting in a file.
$settingsDir = Join-Path $PSScriptRoot '..\..\.tools'
New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
$settingsFile = Join-Path $settingsDir 'slow-downstream-setting.json'
@{ SlowDownstreamUrl = $callbackUrl } | ConvertTo-Json | Set-Content -Path $settingsFile -Encoding utf8
try {
    Invoke-Az logicapp config appsettings set -g $resourceGroup -n $appName --settings "@$settingsFile" -o none
}
finally {
    Remove-Item -Path $settingsFile -Force -ErrorAction SilentlyContinue
}
Invoke-Az logicapp start -g $resourceGroup -n $appName -o none

$check = az resource show --ids "$siteId/config/web" --query 'properties.vnetPrivatePortsCount' -o tsv
Write-Host "Done. vnetPrivatePortsCount = $check, subnet = $subnetId"
