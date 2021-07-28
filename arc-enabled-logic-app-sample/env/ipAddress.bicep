param staticIpName string

resource ip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: staticIpName
  location: resourceGroup().location
  'sku': {
    'name': 'Standard'
  }
  'properties': {
    'publicIPAllocationMethod': 'Static'
  }
}

output staticIp string = ip.properties.ipAddress
