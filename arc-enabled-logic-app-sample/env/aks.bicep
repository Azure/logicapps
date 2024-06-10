param clusterName string

resource aks 'Microsoft.ContainerService/managedClusters@2021-03-01' = {
  name: clusterName
  location: resourceGroup().location
  properties: {
    'dnsPrefix': 'dnsprefix'
    'agentPoolProfiles': [
      { 
          'count': 3
          'vmSize': 'Standard_DS2_v2'
          'osType': 'Linux'
          'name': 'nodepool1'
          'mode' : 'System'
      }
    ]
    'networkProfile': {
      'outboundType': 'loadBalancer'
      'loadBalancerSku': 'standard'
    }
    'aadProfile': {
      'managed': true
    }
    'servicePrincipalProfile': {
      'clientId': 'msi'
    }
  }
  'identity': {
    'type': 'SystemAssigned'
    }
}

output nodeResourceGroup string = aks.properties.nodeResourceGroup

