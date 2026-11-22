param name string
param location string
param tags object
param principalId string
param userPrincipalId string

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [ { locationName: location, failoverPriority: 0, isZoneRedundant: false } ]
    capabilities: [ { name: 'EnableServerless' } ]
    disableLocalAuth: true
  }
}

resource db 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: account
  name: 'msgpat'
  properties: { resource: { id: 'msgpat' } }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: db
  name: 'items'
  properties: {
    resource: {
      id: 'items'
      partitionKey: { paths: [ '/pk' ], kind: 'Hash' }
    }
  }
}

// Cosmos DB Built-in Data Contributor (data plane role).
var dataContributor = '${account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'

resource miRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: account
  name: guid(account.id, principalId, 'data-contributor')
  properties: {
    principalId: principalId
    roleDefinitionId: dataContributor
    scope: account.id
  }
}

resource userRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = if (!empty(userPrincipalId)) {
  parent: account
  name: guid(account.id, userPrincipalId, 'data-contributor')
  properties: {
    principalId: userPrincipalId
    roleDefinitionId: dataContributor
    scope: account.id
  }
}

output name string = account.name
output endpoint string = account.properties.documentEndpoint
