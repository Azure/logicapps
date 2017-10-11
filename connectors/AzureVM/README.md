# Azure VM Connector

This is a logic app custom connector for Azure Virtual Machines.  It provides the following actions:

|Action|Description|
|--|--|
|Restart|Restart a VM|
|Start|Start a VM|
|Deallocate|Deallocate and Stop a VM|
|Power Off|Stop a VM (does not deallocate)|
|Capture Image|Capture an image of a VM|

## Pre-Requisites

This connector does require authentication to Azure Active Directory.  As such, deployment will require the client ID and client Secret for an AAD Application.  [These instructions](https://docs.microsoft.com/azure/azure-resource-manager/resource-manager-api-authentication) will walk through how to register an Azure Active Directory application with **User + app access** so the connector can act on-behalf-of the authenticated user.  Be sure to set your application up to get delegate access to the Windows Azure application.

After deploying, you will need to open the connector (named `azure-vm-connector` in whichever resource group and location selected) and copy the redirect URL from the security tab.  Update your Azure AD Application reply URLs to support the logic app consent flow.

![AAD Reply UX Screenshot](images/aad-reply-ux.png)

## Deploying

You can deploy with the [azuredeploy.json](azuredeploy.json) or by clicking the button below:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fazure%2Flogicapps%2Fmaster%2Fconnectors%2FAzureVM%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

After deployment you can view the connector `Azure VM` in any of the logic apps in the region you deployed the connector to.  You can deploy this connector to as many regions as you require.