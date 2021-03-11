# Logic Apps (Single-tenant) DevOps 

This repository contains a sample Logic App (preview) project, with Azure deployment and GitHub Actions examples. For a sample on how to create DevOps pipeline for Logic Apps with Azure DevOps please see [here](https://github.com/Azure/logicapps/tree/master/templates/devops-sample)

- [Logic Apps (Preview)](#logic-apps-preview)
  - [Prerequisites](#prerequisites)
  - [Local](#local)
    - [VS Code](#vs-code)
    - [API Connections](#api-connections)
      - [Recreate the operation using the connection](#recreate-the-operation-using-the-connection)
      - [Create a new workflow just for connections](#create-a-new-workflow-just-for-connections)
  - [DevOps](#devops)
    - [ARM Deployment](#arm-deployment)
    - [GitHub Actions](#github-actions)
      - [Application Pipeline](#application-pipeline)
      - [IaC Pipeline](#IaC-pipeline)
  - [Known Issues & Limitations](#known-issues--limitations)
    - [Q & A](#q--a)

## Prerequisites

- [Azure Subscription](https://azure.microsoft.com/free)
- [Azure Storage Account or Emulator](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#storage-requirements)
- [Visual Studio Code](https://code.visualstudio.com/)
- [Logic App Tools List](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#tools)

## Local

To run the project locally, you can follow the [documentation provided by the Logic Apps team](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#run-test-and-debug-locally).

### VS Code

- Open the project in VSCode
- Create or update the `local.settings.json` file and make sure it has the following variables:

  ```json
  {
    "IsEncrypted": false,
    "Values": {
      "FUNCTIONS_WORKER_RUNTIME": "dotnet",
      "AzureWebJobsStorage": "",
    }
  }
  ```

- Navigate to the `Run` tab and hit the play icon to run the application
- Right-click on the `workflow.json` file and click `Overview`
- Here you should see a callback URL, you can use that to trigger your workflow

> If you're running on a Mac, you cannot use an emulator for the storage account and will have to point to a real account in Azure for now.

### API Connections

This project uses the Azure Storage Blob connection. For you to run this project locally, you will need to generate a `connections.json` file. There are two ways you can do this,
you can either create a new API connection, or connect to a pre-deployed connection (i.e. you have already created an API connection in Azure, through an IaC pipeline or otherwise).

If you want to use a pre-deployed connection, provide the following variables in your `local.settings.json`, this is so that the designer can pick up the existing connections from Azure.
If you want to create a new connection, these values will get populated for you when you create the connection in the designer.

> Read more about why you have to recreate the operation [here](#known-issues--limitations).

```json
"WORKFLOWS_TENANT_ID": "",
"WORKFLOWS_SUBSCRIPTION_ID": "",
"WORKFLOWS_RESOURCE_GROUP_NAME": "",
"WORKFLOWS_LOCATION_NAME": "",
```

To get the `connections.json` file generated for you, for both the new and existing connectors, you have two options:

#### Recreate the operation using the connection

This approach is where you would delete and recreate operations using your connector in your project workflow file, for example:

1. Right-click on the `workflow.json` file (inside starterworkflow/ folder)
1. Click `Open in designer`
1. Right-click on the Azure blob operation and click `Delete`
1. Add a new step
1. Select the Azure tab and search for `blob`
1. Select `Azure Blob Storage' and search for `list`
1. Select the `List Blobs` operation
1. Give the blob connection a name and choose a storage account from the list (or manually enter connection information)
1. Make sure to hit `Save`

#### Create a new workflow just for connections

This approach uses another workflow as a resource for creating connections so that you don't have to recreate operations in your main project workflow, for example:

1. Use the Logic App extension to create a new workflow
   - `shift+cmd+p` -> `Azure Logic Apps: Create Workflow...`
1. Select `Stateful`
1. Name the workflow `ConnectionsGenerator`
1. Right-click on the `workflow.json` file (inside ConnectionsGenerator/ folder)
1. Click `Open in designer`
1. Create the operation that uses the connection you want to generate
   - Similar to [steps 4 to 9 above](#recreate-the-operation-using-the-connection)
1. Now that the `connections.json` file has been created for you, you can just update your real workflow file
   to reference the connection. For example with `starterworkflow`, you would update `host.connection.referenceName`
   to match the name of the connection that was created inside the `connections.json` file.

After you complete either one of the above steps, a `connection.json` file will be generated and the `local.settings.json` file should be updated to contain the key for the blob connection.
If you provided the workflow variables mentioned above, the Logic App should connect to a pre-existing connection instead of creating a new one. You can always go back into the designer and change the connection.

## DevOps

You can view a sample of this project's GitHub Actions in .github/workflows. 

BEFORE YOU RUN:
1. Add Azure credentials to Secrets 
    1. Create a Service Principal for your Azure subscription following [this guide](https://github.com/marketplace/actions/azure-login#configure-deployment-credentials). 
    - The output of the `az ad sp create-for-rbac --name "{sp-name}" --sdk-auth...` command should look like this: 
     ```json
    {
       "clientId": "<GUID>",
       "clientSecret": "<GUID>",
       "subscriptionId": "<GUID>",
       "tenantId": "<GUID>",
       (...)
    }
    ```
    1. Save the output of the above command to [GitHub Secrets](https://docs.github.com/en/free-pro-team@latest/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository) and call the secret `AZURE_CREDENTIALS`: 
    1. You also need to create a secret `AZURE_SUB` with the subscription ID of the subscription you want to deploy to. Subscription IDs can be found using the `az account list -o table` command.

2. Add environment variables to your pipeline  
	- LA_RG (name of the resource group where your logic Apps will be deployed) 
	- LA_CON (Name of the resource group where your Connections will be deployed)
  
> #### Note on separate resource groups for Logic Apps + Connections 
>
> - You do not have to have connections and logic apps in separate resource groups. The benefit of separating them out is that if you have a lot of manual sign on based connectors such as Office365, Salesforce, etc. then separation means you can separate these out into different DevOps pipelines with their own separate cadence. This means you would not have to reauthenticate on every infrastructure deployment. 


### ARM Deployment

The `ARM` folder contains the ARM templates required to deploy all the required logic app resources.

- `connectors-template.json` deploys an Azure Storage connection
- `la-template.json` deploys: 
    - Logic app
    - App service plan
    - Storage account
   
### GitHub Actions 

The `.github` folder contains examples of how to deploy the logic app, both separately and with it's infrastructure.

#### Application Pipeline

A pipeline that doth both build and deploy actions to build the Logic Apps project and deploy to a pre-existing Logic App. This is a demonstration of separation of concerns whereby your logic app application is deployed independently of the underlying infrastructure which can be handled in a separate pipeline with it's own cadences. 

- Uses the `Scripts/Generate-Connections.ps1` script to generate a `connections.json` file
- Dynamically retrieve the publish profile of the Logic App environment 
- Copy and zip files into deployment artifact
- Publishes artifact to Logic App using the Azure Functions Github Action


> #### Note on `Generate-Connections.ps1`
>
> - If you are using the script with the `-withFunctions` flag, you must have the
> [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local?tabs=linux%2Ccsharp%2Cbash#install-the-azure-functions-core-tools) installed.
> - All of the connections you want to include in your `connections.json` file must be in the same resource group
> - This script generates the `connections.json` for deployment, not for local use. This is because we set the auth type to `ManagedServiceIdentity` ([read more here](#q--a))

#### IaC Pipeline

- Deploys the logic app and API connections
- Set access policies on the connections 
- Repeats steps of the previous build/publish pipeline: 
  - builds the logic app and generates the connections.json file 
  - deploys to the logic app resource just created via ARM

> #### Note:
> 
> These are two example pipelines that are relatively condensed, however you are free to separate these out into separate pipelines as suits your DevOps process. (for example, separate pipelines for build, release, infra deployments etc.). 

## Known Issues & Limitations

With Logic App (single-tenant) being in preview, there are some caveats to be aware of.

- [Azurite](https://github.com/Azure/Azurite) is not yet supported.

- Authentication is not yet supported using the built-in HTTP operation

### Q & A

Q: Why do I have to recreate the operation that uses the API connection?

- A: Currently, whilst Logic Apps (single tenant) is in preview, the designer does not allow you to select or create a new connection when a `connections.json` file does not already exist, the only way
  around this is to recreate the operation that uses the connection, or create any operation that uses that connection inside a new workflow file.

Q: Why do I need to get a connection key to run locally?

- A: When running logic apps locally, the connection needs to use the 'Raw' authentication method for connections to work. When deploying to Azure, the authentication method needs to be `ManagedServiceIdentity`.
