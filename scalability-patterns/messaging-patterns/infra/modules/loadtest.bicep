param name string
param location string
param tags object
param identityId string
param userPrincipalId string

resource loadTest 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    description: 'Logic Apps messaging benchmark load generator'
  }
}

var loadTestContributor = '749a398d-560b-491b-bb21-08924219302e'

resource userRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  scope: loadTest
  name: guid(loadTest.id, userPrincipalId, loadTestContributor)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', loadTestContributor)
  }
}

output name string = loadTest.name
output id string = loadTest.id
