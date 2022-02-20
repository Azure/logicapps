# Logic Apps (Single-tenant)

This folder contains a sample Logic App (single-tenant) project, with Azure deployment and pipeline examples.

- [Logic Apps](#logic-apps)
  - [Prerequisites](#prerequisites)
  - [Local](#local)
    - [VS Code](#vs-code)
    - [Docker](#docker)
    - [API Connections](#api-connections)
      - [Recreate the operation using the connection](#recreate-the-operation-using-the-connection)
      - [Create a new workflow just for connections](#create-a-new-workflow-just-for-connections)
  - [DevOps](#devops)
    - [ARM Deployment](#arm-deployment)
    - [Azure Pipelines](#azure-pipelines)
      - [IaC Pipeline](#iac-pipeline)
      - [PR Pipeline](#pr-pipeline)
      - [CI Pipeline](#ci-pipeline)
      - [CD Pipeline](#cd-pipeline)
    - [Pipeline Variables](#pipeline-variables)
      - [Variable Files](#variable-files)
  - [Known Issues & Limitations](#known-issues--limitations)
    - [Q & A](#q--a)

## Prerequisites

- [Azure Subscription](https://azure.microsoft.com/free)
- [Azure Storage Account or Emulator](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#storage-requirements)
- [Visual Studio Code](https://code.visualstudio.com/)
- [Logic App Tools List](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#tools)
- [ARM Outputs Azure DevOps Task](https://marketplace.visualstudio.com/items?itemName=keesschollaart.arm-outputs)
- [Powershell v7](https://docs.microsoft.com/powershell/scripting/install/installing-powershell?view=powershell-7.1)
  - [Azure Powershell Module](https://docs.microsoft.com/powershell/azure/install-az-ps?view=azps-5.4.0#install-the-azure-powershell-module)

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

You can view a sample of this project's pipelines in [Azure DevOps](https://dev.azure.com/liliankasem/Logic%20Apps%20v2%20Sample/_build?view=folders).

### ARM Deployment

The `deploy` folder contains the ARM templates required to deploy all the required logic app resources.

- `connectors-template.json` deploys a blob API connector
- classic/
  - `logicapp-template.json`
    - Windows logic app
    - Workflow Standard Plan
    - Storage account
- container/ (please note: container updates for this repo are coming, use classic deployment in the meantime)

### Azure Pipelines

The `.pipelines` folder contains examples of how to deploy both the container version and the normal version of the logic app.

#### IaC Pipeline

- Deploys the logic app and API connections
  - [Container version] also deploys ACR

#### CI Pipeline

- [Classic version]
  - Create a zip of the project
  - Swaps out parameter files configured specifically for the azure environment 
  - Publishes project zip as pipeline artifact
- [Container version]
  - Build and push docker file to ACR

#### CD Pipeline

- [Classic version]
  - Download CI pipeline artifact containing project zip
  - Use the Azure Functions task to deploy the project
- [Container version]
  - Use the Azure Functions container task to deploy the project (using the docker image that was published by the CI pipeline)

### Pipeline Variables

For both the classic and container deployment approach, you will need to supply a set of variables to make the deployments possible.

#### Variable Files

Under the `variables/` folder & in some pipeline files, you will need to fill in some variables. 

> NOTE: You can search for `TODO` to find all the values you need to replace.

You will need need to create a service connection for your Azure subscription for many of the pipeline tasks to work.
[Follow this documentation to create your service connection](https://docs.microsoft.com/azure/devops/pipelines/library/connect-to-azure?view=azure-devops).


### Q & A

Q: Why do I have to recreate the operation that uses the API connection?

- A: Currently, whilst Logic Apps v2 is in preview, the designer does not allow you to select or create a new connection when a `connections.json` file does not already exist, the only way
  around this is to recreate the operation that uses the connection, or create any operation that uses that connection inside a new workflow file.

Q: Why do I need to get a connection key to run locally?

- A: When running logic apps locally, the connection needs to use the 'Raw' authentication method for connections to work. When deploying to Azure, the authentication method needs to be `ManagedServiceIdentity`.
