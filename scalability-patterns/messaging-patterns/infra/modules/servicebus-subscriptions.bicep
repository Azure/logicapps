param namespaceName string
param topicName string
param subscriptions array

resource sub 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = [for s in subscriptions: {
  name: '${namespaceName}/${topicName}/${s.name}'
  properties: {
    requiresSession: s.?requiresSession ?? false
    lockDuration: s.?lockDuration ?? 'PT1M'
    maxDeliveryCount: s.?maxDeliveryCount ?? 10
    deadLetteringOnMessageExpiration: true
  }
}]

resource rule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = [for (s, index) in subscriptions: if (contains(s, 'sqlFilter')) {
  name: '${namespaceName}/${topicName}/${s.name}/filter'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: { sqlExpression: s.?sqlFilter ?? '1=1' }
  }
  dependsOn: [ sub[index] ]
}]
