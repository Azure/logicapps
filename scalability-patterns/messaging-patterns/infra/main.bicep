// Shared infrastructure for one benchmark pattern. Deploy once per resource group (rg-msgpat-<id>).
targetScope = 'resourceGroup'

@description('Pattern id, for example 1a-max-throughput. Used for names and tags.')
param patternId string

@description('Azure region.')
param location string = resourceGroup().location

@description('Workflow Standard plan SKU: WS1, WS2 or WS3.')
@allowed([ 'WS1', 'WS2', 'WS3' ])
param planSku string = 'WS1'

@description('Maximum burst (elasticMaximumWorkerCount) for the plan.')
@minValue(1)
@maxValue(100)
param maximumElasticWorkerCount int = 20

@description('Always-ready instances (minimumElasticInstanceCount) on the Logic App.')
@minValue(1)
@maxValue(20)
param minimumElasticInstanceCount int = 1

@description('Runtime scale monitoring. Needed only when the scale controller cannot reach the storage account (for example VNET-restricted storage).')
param functionsRuntimeScaleMonitoringEnabled bool = false

@description('Service Bus namespace SKU.')
@allowed([ 'Standard', 'Premium' ])
param serviceBusSku string = 'Standard'

@description('Messaging units when serviceBusSku is Premium.')
@allowed([ 1, 2, 4, 8, 16 ])
param serviceBusPremiumCapacity int = 1

@description('Queues to create. Each item: { name, requiresSession?, maxSizeInMegabytes?, lockDuration?, maxDeliveryCount?, deadLetteringOnMessageExpiration? }. A results queue is always added.')
param queues array = [
  { name: 'orders' }
]

@description('Topics to create. Each item: { name, subscriptions: [ { name, requiresSession?, maxDeliveryCount?, lockDuration?, sqlFilter? } ] }.')
param topics array = []

@description('Extra Logic App app settings (name/value object). Overrides defaults with the same name.')
param extraAppSettings object = {}

@description('Object id of the signed-in user. When set, grants Load Test Contributor, Service Bus Data Owner and Cosmos data contributor to this user.')
param userPrincipalId string = ''

@description('Short unique suffix for globally unique names.')
param suffix string = uniqueString(resourceGroup().id)

var shortId = toLower(take(replace(replace(patternId, '-', ''), '_', ''), 10))
var baseName = 'msgpat-${shortId}-${take(suffix, 6)}'
var tags = {
  purpose: 'logicapps-messaging-benchmark'
  pattern: patternId
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: 'id-${baseName}'
    location: location
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    baseName: baseName
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: take('st${shortId}${suffix}', 24)
    location: location
    tags: tags
    contentShareName: take('la-${baseName}', 63)
    principalId: identity.outputs.principalId
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  params: {
    name: 'sb-${baseName}'
    location: location
    tags: tags
    sku: serviceBusSku
    premiumCapacity: serviceBusPremiumCapacity
    queues: queues
    topics: topics
    principalId: identity.outputs.principalId
    userPrincipalId: userPrincipalId
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    name: 'cosmos-${baseName}'
    location: location
    tags: tags
    principalId: identity.outputs.principalId
    userPrincipalId: userPrincipalId
  }
}

module logicApp 'modules/logicapp.bicep' = {
  name: 'logicapp'
  params: {
    name: 'la-${baseName}'
    planName: 'asp-${baseName}'
    location: location
    tags: tags
    planSku: planSku
    maximumElasticWorkerCount: maximumElasticWorkerCount
    minimumElasticInstanceCount: minimumElasticInstanceCount
    functionsRuntimeScaleMonitoringEnabled: functionsRuntimeScaleMonitoringEnabled
    identityId: identity.outputs.id
    identityClientId: identity.outputs.clientId
    storageAccountName: storage.outputs.name
    contentShareName: storage.outputs.contentShareName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    serviceBusFqdn: serviceBus.outputs.fqdn
    cosmosEndpoint: cosmos.outputs.endpoint
    extraAppSettings: extraAppSettings
  }
}

module loadTest 'modules/loadtest.bicep' = {
  name: 'loadtest'
  params: {
    name: 'alt-${baseName}'
    location: location
    tags: tags
    identityId: identity.outputs.id
    userPrincipalId: userPrincipalId
  }
}

output logicAppName string = logicApp.outputs.name
output planName string = logicApp.outputs.planName
output logicAppId string = logicApp.outputs.id
output planId string = logicApp.outputs.planId
output serviceBusNamespace string = serviceBus.outputs.name
output serviceBusFqdn string = serviceBus.outputs.fqdn
output serviceBusId string = serviceBus.outputs.id
output cosmosAccount string = cosmos.outputs.name
output cosmosEndpoint string = cosmos.outputs.endpoint
output appInsightsName string = monitoring.outputs.appInsightsName
output appInsightsAppId string = monitoring.outputs.appInsightsAppId
output appInsightsId string = monitoring.outputs.appInsightsId
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
output loadTestName string = loadTest.outputs.name
output identityId string = identity.outputs.id
output identityClientId string = identity.outputs.clientId
output storageAccountName string = storage.outputs.name
