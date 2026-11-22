param name string
param location string
param tags object
@allowed([ 'Standard', 'Premium' ])
param sku string
param premiumCapacity int
param queues array
param topics array
param principalId string
param userPrincipalId string

var allQueues = concat(queues, [ { name: 'results' } ])

resource ns 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
    capacity: sku == 'Premium' ? premiumCapacity : null
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: false
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = [for q in allQueues: {
  parent: ns
  name: q.name
  properties: {
    requiresSession: q.?requiresSession ?? false
    maxSizeInMegabytes: q.?maxSizeInMegabytes ?? 5120
    lockDuration: q.?lockDuration ?? 'PT1M'
    maxDeliveryCount: q.?maxDeliveryCount ?? 10
    deadLetteringOnMessageExpiration: q.?deadLetteringOnMessageExpiration ?? true
    enablePartitioning: q.?enablePartitioning ?? false
  }
}]

resource topic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = [for t in topics: {
  parent: ns
  name: t.name
  properties: {
    maxSizeInMegabytes: t.?maxSizeInMegabytes ?? 5120
  }
}]

module subscriptions 'servicebus-subscriptions.bicep' = [for (t, index) in topics: {
  name: 'sbsubs-${index}'
  params: {
    namespaceName: ns.name
    topicName: t.name
    subscriptions: t.?subscriptions ?? []
  }
  dependsOn: [ topic ]
}]

var dataOwner = '090c5cfd-751d-490a-894a-3ce6f1109419'

resource miRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ns
  name: guid(ns.id, principalId, dataOwner)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataOwner)
  }
}

resource userRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  scope: ns
  name: guid(ns.id, userPrincipalId, dataOwner)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataOwner)
  }
}

output name string = ns.name
output id string = ns.id
output fqdn string = '${ns.name}.servicebus.windows.net'
