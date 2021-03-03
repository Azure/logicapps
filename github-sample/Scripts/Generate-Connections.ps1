# Make sure you have connected your Azure account and set context to the subscription you want to use:
# 1) Connect-AzAccount
# 2) Set-AzContext -Subscription <subscription-id-here>

<#
    .SYNOPSIS
        Generate a connections json file using API connections already deployed to a resource group.

    .PARAMETER resourceGroup
        The name of the resource group that contains the API connectors.

    .PARAMETER outputLocation
    The path to store the updated connections json file. Defaults to connections.json in the local directory.

    .PARAMETER withFunctions
    A flag to include Azure Functions in the connection file.

    .EXAMPLE
        Generates a connections json file.

        ./Generate-Connections.ps1 -resourceGroup rg-api-connections -outputLocation connections.json

        Use this if you want to include function connectors
        ./Generate-Connections.ps1 -resourceGroup rg-api-connections -outputLocation connections.json -withFunctions
#>

param(
  [Parameter(Mandatory = $True)]
  [string]
  $resourceGroup,

  [Parameter(Mandatory = $False)]
  [string]
  $outputLocation = "connections.json",

  [Parameter(Mandatory = $False)]
  [switch]
  $withFunctions
)

Function Get-ConnectionsFile {
  <#
      .SYNOPSIS
          Gets details about the connections in a given resource group and outputs a json file.
  #>
  Write-Host 'Looking up API Connectors'
  $apiConnections = (Get-ApiConnections) ?? @{}

  if ($withFunctions) {
    Write-Host 'Looking up Function Connectors'
    $functionConnections = (Get-FunctionConnections) ?? @{}
  }

  $json = $withFunctions ? @{ "managedApiConnections" = $apiConnections; "functionConnections" = $functionConnections } : @{ "managedApiConnections" = $apiConnections; }
  $json = ConvertTo-Json $json -Depth 5 -Compress
  $json = [Regex]::Replace($json, "\\u[a-zA-Z0-9]{4}", { param($u) [Regex]::Unescape($u) })
  $json | Set-Content -Path $outputLocation
}

Function Get-ApiConnections {
  $apiConnections = @{}
  $resources = Get-AzResource -ResourceGroupName $resourceGroup -ResourceType Microsoft.Web/connections
  $resources | ForEach-Object {
    $name = $_.Name;
    Write-Host 'Found API connector: '$name
    $connectionResource = Get-AzResource -ResourceId $_.id
    $apiConnections["$name"] = @{
      "api"                  = @{
        "id" = $connectionResource.Properties.api.id
      };
      "connection"           = @{
        "id" = $_.Id.ToLower();
      };
      "connectionRuntimeUrl" = $connectionResource.Properties.connectionRuntimeUrl;
      "authentication"       = @{
        "type" = "ManagedServiceIdentity"
      }
    }
  }
  return $apiConnections;
}

Function Get-FunctionConnections {
  $functionConnections = @{}
  $resources = Get-AzResource -ResourceGroupName $resourceGroup -ResourceType Microsoft.Web/sites
  $resources | ForEach-Object {
    Write-Host 'Found function app: '$_.Name

    $resourceId = $_.id
    $function = func azure functionapp list-functions $_.Name --show-keys

    if ($function -match "(Invoke url)") {
      $function | select-string -Pattern "Invoke url:" -SimpleMatch | ForEach-Object {

        $line = $_.Line -replace '\s', ''
        $name = [Regex]::Matches($line, "(?<=api\/)(.*)(?=\?)")
        $trigger = [Regex]::Matches($line, "(?<=url:)(.*)(?=\?)")
        $key = [Regex]::Matches($line, "(?<=code=).*$")

        Write-Host "Found function: $name"

        $functionResource = Get-AzResource -ResourceId ($resourceId + "/functions/$name")
        if ($functionResource -and $functionResource.ResourceType -eq "Microsoft.Web/sites/functions") {
          $functionAuth = @{
            "type"  = "QueryString";
            "name"  = "Code";
            "value" = "$key";
          }
          $functionConnections["$name"] = @{
            "function"       = @{
              "id" = $functionResource.ResourceId
            };
            "triggerUrl"     = "$trigger"
            "authentication" = $functionAuth
            "displayName"    = "$name"
          }
        }
        else {
          Write-Host "Issue adding function $name"
        }
      }
    }
    else {
      Write-Host $_.Name 'does not contain any functions, or might be a logic app.'
    }
  }
  return $functionConnections;
}

#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************

# Fix the PSScriptRoot value for older versions of PowerShell
if (!$PSScriptRoot) { $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent }

Get-ConnectionsFile