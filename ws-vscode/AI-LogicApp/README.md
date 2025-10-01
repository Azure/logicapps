# Post deployment instructions

## Azure Logic Apps workspace - Create from package

### Managed identity connections

The **Create a workspace from a package** capability doesn't replace built-in connections that use a managed identity for authentication. To use a different authentication option, you must update these connections after deployment.

> [!IMPORTANT]
>
> For authentication, use [Microsoft Entra ID](https://go.microsoft.com/fwlink/?linkid=2300022) with 
> [managed identities](https://go.microsoft.com/fwlink/?linkid=2299913) whenever possible. 
> This method provides optimal and superior security without having to provide credentials. Azure manages 
> this identity for you and helps keep authentication information secure so that you don't have to manage 
> this sensitive information. To set up a managed identity for Azure Logic Apps, see 
> [Authenticate access and connections to Azure resources with managed identities in Azure Logic Apps](https://go.microsoft.com/fwlink/?linkid=2300115).

To check whether a connection uses a managed identity, check the following setting in your logic app project's **connections.json** file:

**"parameterSetName": "ManagedServiceIdentity"**

The following example shows an Azure Service Bus connection that uses a managed identity:

```JSON
{
  "serviceProviderConnections": {
    "serviceBus": {
      "parameterValues": {
        "fullyQualifiedNamespace": "@appsetting('serviceBus_fullyQualifiedNamespace')",
        "authProvider": {
          "Type": "ManagedServiceIdentity"
        }
      },
      "parameterSetName": "ManagedServiceIdentity",
      "serviceProvider": {
        "id": "/serviceProviders/serviceBus"
      },
      "displayName": "my-servicebus-connection"
    }
  },
  "managedApiConnections": {}
}
```

To update this connection to a different authentication method, use one of the following options:

- For the trigger or action, create a new connection and update the connection reference.

- In the **connections.json** file, update the connection reference to use another authentication option.

  > [!IMPORTANT]
  >
  > If you change the authentication type, you must also update the 
  > **local.settings.json** file and provide the correct app settings entries.
  >
  > A connection string includes the authorization information required for your 
  > app to access a specific resource, service, or system. The access key in the 
  > connection string is similar to a root password. In production environments, 
  > always protect your access keys. Make sure to secure your connection string 
  > using Microsoft Entra ID, and use [Azure Key Vault](https://go.microsoft.com/fwlink/?linkid=2300117) 
  > to securely store and rotate your keys.
  >
  > Avoid distributing access keys to other users, hardcoding them, or saving them 
  > anywhere in plain text where others can access. Rotate your keys as soon as 
  > possible if you think these keys might be compromised. 

The following example shows an updated Service Bus connection that uses the connection string method instead:

```JSON
{
  "serviceProviderConnections": {
        "serviceBus": {
      "parameterValues": {
        "connectionString": "@appsetting('serviceBus_11_connectionString')"
      },
      "parameterSetName": "connectionString",
      "serviceProvider": {
        "id": "/serviceProviders/serviceBus"
      },
      "displayName": "ServiceBusConnStr"
    }
  },
  "managedApiConnections": {}
}
```
