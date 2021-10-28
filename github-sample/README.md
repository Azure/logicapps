# Logic Apps (Single-tenant) DevOps 

This repository contains a sample Logic App (preview) project, with Azure deployment and GitHub Actions examples. For a sample on how to create DevOps pipeline for Logic Apps with Azure DevOps please see [here](https://github.com/Azure/logicapps/tree/master/azure-devops-sample)

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

To run the project locally, you can follow the [documentation](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#run-test-and-debug-locally).

### Setting up your project in VS Code

- Clone this repository locally and open the `github-sample` folder in VSCode
- Navigate to the `logic` folder and create a `local.settings.json` file and paste in the following:

  ```json
  {
    "IsEncrypted": false,
    "Values": {
      "AzureWebJobsStorage": "UseDevelopmentStorage=true",
      "FUNCTIONS_WORKER_RUNTIME": "node", 
      "azureblob-connectionKey": "", 
      "BLOB_CONNECTION_RUNTIMEURL": ""
    }
  }
  ```
- "AzureWebJobsStorage" for local development in Visual Studio Code, you need to set up a local data store for your logic app project and workflows to use for running in your local development environment. You can use and run the Azurite storage emulator as your local data store (see pre-requisites).
- "azureblob-connectionKey" this string will be automatically generated further on in the instructions. Keep it blank for now. This is the will be needed to provide raw authentication credentials so your local VS Code project can access your azure hosted API connection. 
- "BLOB_CONNECTION_RUNTIMEURL" is the endpoint URL for the blob connection which is hosted on Azure. This will be generated in further steps. 


### Setting up your API Connections

This project uses the Azure Storage Blob connection. For you to run this project locally, you will need to generate local credentials for your connection withing `connections.json` file: "azureblob-connectionKey" and the connections runtime URL. To do this we are going to open the first workflow 'EventTrigger' create a new blob connection from scratch (which will generate all the local values for us) then copy these values into local.settings to work with our already parameterised connection. 

The first step is to set up your connection to Azure so your local project can access your Azure hosted API connections. To do this: 
1. Right click on the EventTrigger workflow.json file 
1. When prompted to use connections from Azure select yes 
1. Select your Subscription and Resource Group 

Once your workflow is opened in the designer, let's create a new blob connection (we need to do this to generate new raw keys and grab the endpoint URL). If you already have a blob connection in your resource group you can reuse that, otherwise a new connection will be created for you. To create a new blob connection: 
1. Add a new step
1. Select the Azure tab and search for `blob`
1. Select `Azure Blob Storage` and search for `list`
1. Select the `List Blobs` operation
1. Give the blob connection a name and choose a storage account from the list (or manually enter connection information)
1. Make sure to hit `Save`
1. Once you've hit save you can delete the action you've just created - you won't need this anymore (the connection information will still remain in connections.json)

Behind the scenes this will create a new Azure Blob connection in Azure you can use for development, generating the raw authentication key and retrieving the endpoint URL for us to update our local.settings.json. 

Navigate to `connections.json` and you will see you have two blob connections configured, the sample has pre-parameterised this for you so all you need to do is copy your "azureblob-connectionKey" and connection runtimeURL to the clipboard. You can then delete the duplicate connection, you won't need this anymore. 

Now you can update your local settings in your `local.settings.json` file. It will look something like this now:
 ```json
  {
    "IsEncrypted": false,
    "Values": {
      "AzureWebJobsStorage": "UseDevelopmentStorage=true",
      "FUNCTIONS_WORKER_RUNTIME": "node", 
      "azureblob-connectionKey": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6ImZic1poS.....", 
      "BLOB_CONNECTION_RUNTIMEURL": "https://a9ab15f5a12185bf.07.common.logic.azure-apihub.net/apim/azureblob......", 
      "WORKFLOWS_TENANT_ID": "<your-tenant>",
      "WORKFLOWS_SUBSCRIPTION_ID": "<your-subscription>",
      "WORKFLOWS_RESOURCE_GROUP_NAME": "<your-resource-group>",
      "WORKFLOWS_LOCATION_NAME": "<your-location>",
    }
  }
  ```
We can now test out our new connection! 


### Running your Project in VS Code

- Navigate to the `Run` tab and hit the play icon to run the application
- Right-click on `workflow.json` under your `EventProcessor` folder and click `Overview`
- Here you should see a callback URL, you can use that to trigger your workflow
- Your workflow will run and add a new blob into your storage account. 

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
    1. This sample deploys the logic app resources and connections into separate resource groups. Currently you will need to create these resource groups separately and then add a GitHub Secret with the names of the resource groups: `RG_LA` should hold the name of your logic apps resource group and `RG_CON` the name of your connections resource group. 

  
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

#### The Samples Pipeline explained

There are many ways to configure your DevOps pipelines. This sample separates the infrastructure deployment (`IaC_deploy.yml`)and logic apps build and deploy (`logicapp_deploy.yml`) into separate pipelines.

Whenever you push a change to your ARM template folder OR you manually trigger the IaC_deploy pipeline, GitHub Actions will deploy your infrastructure. This pipeline will: 
- Deploy the logic app infrastructure and API connections into their respective resource groups 
- Set access policies on the connections 
- Update the Logic Apps app settings with all connections credentials 

Once this has run successfully, this will then trigger the Logic Apps build and deploy pipeline which will build the logic app and deploy it to the newly created environment. Alternatively if you just make a change to your `logic` folder only the Logic Apps Build and Deploy pipeline will run. Meaning you don't have to deploy your infrastructure on every push. 

> #### Note:
> 
> These are two example pipelines that are relatively condensed, however you are free to separate these out into separate pipelines as suits your DevOps process. (for example, separate pipelines for build, release, infra deployments etc.). 

#### Deploying to more environments 

Everything in this sample is parameterised for you. To deploy to new environments: 
- IAC: create a new parameter files for your infrastructure deployments. Input any updated parameter names, configuration in these
- Logic App: There is already an azure specific parameters.json file configured for this sample. You won't need to create a new parameters file unless you have added more parameters in the file that do need to change between environments. For an example of how to dynamically swap out your parameter files see the last step in the `logicapp_deploy.yml` pipeline. 


> #### Note:
> 
> These are two example pipelines that are relatively condensed, however you are free to separate these out into separate pipelines as suits your DevOps process. (for example, separate pipelines for build, release, infra deployments etc.). 



### Q & A

Q: Why do I have to recreate the operation that uses the API connection?

- A: Currently the designer does not allow you to select or create a new connection when a `connections.json` file does not already exist, the only way
  around this is to recreate the operation that uses the connection, or create any operation that uses that connection inside a new workflow file.

Q: Why do I need to get a connection key to run locally?

- A: When running logic apps locally, the connection needs to use the 'Raw' authentication method for connections to work. When deploying to Azure, the authentication method needs to be `ManagedIdentity`.
