param appName string
param storageAccountName string
param tags object = {
  'sample': 'arcEnabledLogicApp'
}
@secure()
param spClientSecret string
param spTenantId string
param spObjectId string
param spClientId string
param customLocationId string
param appServicePlanName string
param kubeEnvironmentName string
param appServiceIP string

var deploymentLocation = resourceGroup().location

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  kind: 'StorageV2'
  location: deploymentLocation
  sku: {
    name: 'Standard_LRS'
  }
  resource storageTable 'tableServices@2021-04-01' = {
    name: 'default'
    resource table 'tables' = {
      name: 'ratings'
    }
  }
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'

resource kubeEnvironment 'Microsoft.Web/kubeEnvironments@2021-01-15' = {
  name: kubeEnvironmentName
  location: deploymentLocation
  extendedLocation: {
    type: 'customLocation'
    name: customLocationId
  }
  properties: {
    staticIp: appServiceIP
    internalLoadBalancerEnabled: false
    arcConfiguration: {
      artifactsStorageType: 'NetworkFileSystem'
      artifactStorageClassName: 'default'
      frontEndServiceConfiguration: {
          kind: 'LoadBalancer'
      }
    }
  }
}

resource appservplan 'Microsoft.Web/serverfarms@2021-01-01' = {
  name: appServicePlanName
  location: deploymentLocation
  kind: 'linux,kubernetes'
  sku: {
    name: 'K1'
    tier: 'Kubernetes'
  }
  extendedLocation: {
    type: 'customLocation'
    name: customLocationId
  }
  properties: {
    reserved: true
    kubeEnvironmentProfile: {
        id: kubeEnvironment.id
    }
  }
}

resource workflowApp 'Microsoft.Web/sites@2021-01-15' = {
  name: appName
  location: deploymentLocation
  kind: 'kubernetes,functionapp,workflowapp,linux'
  extendedLocation: {
    type: 'customLocation'    
    name: customLocationId
  }
  properties: {
    serverFarmId: appservplan.id
    clientAffinityEnabled: false
    siteConfig: {
      appSettings: [
        {
          'name': 'APPINSIGHTS_INSTRUMENTATIONKEY'
          'value': appInsights.properties.InstrumentationKey
        }
        {
          'name': 'AzureWebJobsStorage'
          'value': storageConnectionString
        }
        {
          'name': 'FUNCTIONS_EXTENSION_VERSION'
          'value': '~3'
        }
        {
          'name': 'FUNCTIONS_WORKER_RUNTIME'
          'value': 'node'
        }
        {
          'name': 'azuretables_connectionKey'
          'value': storageConnectionString
        }
        {
          'name': 'azuretables_subscriptionId'
          'value': subscription().subscriptionId
        }
        {
          'name': 'azuretables_resourceGroup'
          'value': resourceGroup().name
        }
        {
          'name': 'azuretables_runtimeUrl'
          'value': reference(tableStorageConnection.id, '2016-06-01', 'Full').properties.connectionRuntimeUrl
        }
        {
          'name': 'AzureBlob_connectionString'
          'value': storageConnectionString
        }
        {
          'name': 'WORKFLOWAPP_AAD_CLIENTID'
          'value': spClientId
        }
        {
          'name': 'WORKFLOWAPP_AAD_OBJECTID'
          'value': spObjectId
        }
        {
          'name': 'WORKFLOWAPP_AAD_TENANTID'
          'value': spTenantId
        }
        {
          'name': 'WORKFLOWAPP_AAD_CLIENTSECRET'
          'value': spClientSecret
        }
      ]
      linuxFxVersion: 'Node|12'
    }
  }
  tags: tags
}

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: '${appName}-ai'
  location: deploymentLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: appInsightsWorkspace.id
  }
  tags: tags
}

resource appInsightsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: '${appName}-aiws'
  location: deploymentLocation
  properties: {
    sku: {
      name: 'Free'
    }
  }
  tags: tags
}

resource tableStorageConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'tablestorage'
  kind: 'v2'
  location: deploymentLocation
  properties: {
    displayName: 'tablestorage'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${deploymentLocation}/managedApis/azuretables'
    }
    parameterValues: {
      'storageaccount': storageAccountName
      'sharedkey': listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
    }
  }
  tags: tags
}

resource accessPolicy 'Microsoft.Web/connections/accessPolicies@2016-06-01' = {
  name: '${tableStorageConnection.name}/${spObjectId}'
  properties: {
    principal: {
        type: 'ActiveDirectory'
        identity: {
            objectId: spObjectId
            tenantId: spTenantId
        }
    }
  }
}
