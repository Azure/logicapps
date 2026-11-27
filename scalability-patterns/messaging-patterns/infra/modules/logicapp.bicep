param name string
param planName string
param location string
param tags object
param planSku string
param maximumElasticWorkerCount int
param minimumElasticInstanceCount int
param functionsRuntimeScaleMonitoringEnabled bool
param identityId string
param identityClientId string
param storageAccountName string
param contentShareName string
@description('Connection strings for scale units CU01 and later, in a values array. CU00 uses the primary account.')
@secure()
param scaleUnitConnections object = {}
@secure()
param appInsightsConnectionString string
param serviceBusFqdn string
param cosmosEndpoint string
param extraAppSettings object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var storageConnection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

// NOTE: A host with Runtime.ScaleUnitsCount above 1 stays in Error unless every unit, CU00 included, has a connection string.
var scaleUnitConnectionStrings = empty(scaleUnitConnections.?values ?? []) ? [] : concat([storageConnection], scaleUnitConnections.values)
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: planSku
    tier: 'WorkflowStandard'
  }
  properties: {
    elasticScaleEnabled: true
    maximumElasticWorkerCount: maximumElasticWorkerCount
    zoneRedundant: false
  }
}

var defaultSettings = {
  APP_KIND: 'workflowApp'
  FUNCTIONS_EXTENSION_VERSION: '~4'
  FUNCTIONS_WORKER_RUNTIME: 'dotnet'
  AzureWebJobsStorage: storageConnection
  WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: storageConnection
  WEBSITE_CONTENTSHARE: contentShareName
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
  AzureFunctionsJobHost__extensionBundle__id: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
  AzureFunctionsJobHost__extensionBundle__version: '[1.*, 2.0.0)'
  LOGIC_APPS_CUSTOMCODE_DOTNETVERSION: 'net8'
  serviceBus_fullyQualifiedNamespace: serviceBusFqdn
  cosmos_endpoint: cosmosEndpoint
  UAMI_CLIENT_ID: identityClientId
  UAMI_RESOURCE_ID: identityId
}

// Defaults with the same name as an extra setting are dropped, so params.json can override them.
var extraSettingsArray = map(items(extraAppSettings), setting => { name: setting.key, value: string(setting.value) })

resource site 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      minimumElasticInstanceCount: minimumElasticInstanceCount
      functionsRuntimeScaleMonitoringEnabled: functionsRuntimeScaleMonitoringEnabled
      appSettings: concat(
        filter(map(items(defaultSettings), setting => { name: setting.key, value: string(setting.value) }), setting => !contains(extraAppSettings, setting.name)),
        map(range(0, length(scaleUnitConnectionStrings)), index => {
          name: 'CloudStorageAccount.Workflows.ScaleUnitsDataStorage.CU${padLeft(index, 2, '0')}.ConnectionString'
          value: scaleUnitConnectionStrings[index]
        }),
        extraSettingsArray)
    }
  }
}

output name string = site.name
output id string = site.id
output planName string = plan.name
output planId string = plan.id

