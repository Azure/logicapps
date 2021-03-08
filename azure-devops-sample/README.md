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

## Local

To run the project locally, you can follow the [documentation provided by the Logic Apps team](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#run-test-and-debug-locally).

### VS Code

- Open the project in VSCode
- Create or update the `local.settings.json` file and make sure it has the following variables:

  ```json
  {
    "IsEncrypted": false,
    "Values": {
      "AzureWebJobsStorage": "UseDevelopmentStorage=true",
      "FUNCTIONS_WORKER_RUNTIME": "node",
      "FUNCTIONS_V2_COMPATIBILITY_MODE": "true",
      "emailAddress": ""
    }
  }
  ```

- Navigate to the `Run` tab and hit the play icon to run the application
- Right-click on the `workflow.json` file and click `Overview`
- Here you should see a callback URL, you can use that to trigger your workflow

> If you're running on a Mac, you cannot use an emulator for the storage account and will have to point to a real account in Azure for now.

### Docker

Using docker, you can build and run using the following commands:

`docker build . -t local/logicappsample`

`docker run --env-file .env -p 8080:80 local/logicappsample`

You will need a .env file containing these variables:

```txt
AzureWebJobsStorage=
emailAddress=
office365-connectionKey=
```

Once your application is running:

- Get the master key from your storage account or emulator
  - [Documentation here](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code#get-callback-url-for-request-trigger)

- Call `listCallbackUrl` to get the workflow URL:

  `http://localhost:8080/runtime/webhooks/workflow/api/management/workflows/ExampleWorkflow/triggers/manual/listCallbackUrl?api-version=2020-05-01-preview&code=<MASTER KEY GOES HERE>`

- You can then use the workflow URL to trigger your Logic App

> NOTE: When using docker, I have noticed that the `host.json` (inside the storage account) is not created until a request is made to the logic app.
> So if you don't see a new folder with a `host.json` file, try just making a call to `listCallbackUrl` URl above without the master key then check your storage account again.

### API Connections

This project uses the office 365 API connection. For you to run this project, you will need to generate a `connections.json` file. There are two ways you can do this,
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

1. Right-click on the `workflow.json` file (inside ExampleWorkflow/ folder)
1. Click `Open in designer`
1. Right-click on the office operation and click `Delete`
1. Add a new step
1. Select the Azure tab and search for `office365`
1. Select the `Office 365 Outlook` and search for `send email`
1. Select the `Send an email (V2)` operation
1. Click `Sign in` and follow the process to authenticate the office 365 connection
1. Make sure to hit `Save`

> NOTE: If you recreate the `Send an email` operation, the parameter used for the "To" address" will be removed. If you want to parameterize this value, update the `workflow.json` file so that
> it uses app settings for the email address `To": "@appsetting('emailAddress')"`

#### Create a new workflow just for connections

This approach uses another workflow as a resource for creating connections so that you don't have to recreate operations in your main project workflow, for example:

1. Use the Logic App extension to create a new workflow
   - `cmd+shift+p` / `ctrl+shift+p` -> `Azure Logic Apps: Create Workflow...`
2. Select `Stateful`
3. Name the workflow `ConnectionsGenerator`
4. Right-click on the `workflow.json` file (inside ConnectionsGenerator/ folder)
5. Click `Open in designer`
6. Create the operation that uses the connection you want to generate
   - Similar to [steps 4 to 9 above](#recreate-the-operation-using-the-connection)
7. Now that the `connections.json` file has been created for you, you can just update your real workflow file
   to reference the connection. For example with `ExampleWorkflow`, you would update `host.connection.referenceName`
   to match the name of the connection that was created inside the `connections.json` file.

After you complete either one of the above steps, a `connection.json` file will be generated and the `local.settings.json` file should be updated to contain the key for the office365 connection.
If you provided the workflow variables mentioned above, the Logic App should connect to a pre-existing connection instead of creating a new one. You can always go back into the designer and change the connection.

## DevOps

You can view a sample of this project's pipelines in [Azure DevOps](https://dev.azure.com/logicappsdemo/Logic%20Apps%20v2%20Sample/_build?view=folders).

### ARM Deployment

The `deploy` folder contains the ARM templates required to deploy all the required logic app resources.

- `connectors-template.json` deploys an office 365 connector
- classic/
  - `logicapp-template.json`
    - Windows logic app
    - App service plan
    - Storage account
- container/
  - `logicapp-template.json`
    - Linux logic app (container based deployment)
    - App service plan
    - Storage account
  - `acr-template.json`
    - Azure container registry (ACR)

### Azure Pipelines

The `.pipelines` folder contains examples of how to deploy both the container version and the normal version of the logic app.

#### IaC Pipeline

- Deploys the logic app and API connections
  - [Container version] also deploys ACR

#### CI Pipeline

- Uses the `.pipelines/scripts/Generate-Connections.ps1` script to generate a `connections.json` file
- [Classic version]
  - Create a zip of the project
  - Publishes project zip as pipeline artifact
- [Container version]
  - Build and push docker file to ACR

> #### Note on `Generate-Connections.ps1`
>
> - If you are using the script with the `-withFunctions` flag, you must have the
> [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local?tabs=linux%2Ccsharp%2Cbash#install-the-azure-functions-core-tools) installed.
> - All of the connections you want to include in your `connections.json` file must be in the same resource group
> - This script generates the `connections.json` for deployment, not for local use. This is because we set the auth type to `ManagedServiceIdentity` ([read more here](#q--a))

#### CD Pipeline

- [Classic version]
  - Download CI pipeline artifact containing project zip
  - Use the Azure Functions task to deploy the project
- [Container version]
  - Use the Azure Functions container task to deploy the project (using the docker image that was published by the CI pipeline)

### Pipeline Variables

For both the classic and container deployment approach, you will need to supply a set of variables to make the deployments possible.

#### Variable Files

Under the `variables/` folder & in some pipeline files, you will need to fill in some variables:

```yml
# pipeline-vars.yml
devServiceConnection: 'NAME OF AZURE SERVICE CONNECTION IN AZURE DEVOPS'

# cd-pipeline.yaml
toEmailAddress: 'EMAIL ADDRESS THE EXAMPLE WORKFLOW SHOULD EMAIL'
resources.pipelines.pipeline.source: 'NAME OF THE CI PIPELINE IN AZURE DEVOPS'
```

> NOTE: You can search for `TODO` to find all the values you need to replace.

You will need need to create a service connection for your Azure subscription for many of the pipeline tasks to work.
[Follow this documentation to create your service connection](https://docs.microsoft.com/azure/devops/pipelines/library/connect-to-azure?view=azure-devops).

## Known Issues & Limitations

With Logic App v2 being in preview, there are some caveats to be aware of.

- [**Connections**] You cannot parameterize values inside the `connection.json` file. You can replace an entire variable with an `appsetting` parameter, but you cannot parameterize parts of a string. For example:

  - This works: `"someVariable": "@appsetting('exampleVariable')"`
  - This *does **not*** work: `"someVariable": "/subscriptions/@{appsetting('subId')}/resourceGroups/@{appsetting('resourceGroup')}/"`

- [**Workflow**] Parameters are not yet supported inside the `workflow.json` file, but you can use `appsetting` instead. For example:

  - `"someVariable": "myPrefix-@{appsetting('example')}"` || `"someVariable": "@appsetting('example')"`

- [Azurite](https://github.com/Azure/Azurite) is not yet supported.

- There is currently a bug where you cannot view Azure operations in the designer when using a stateless workflow

- Authentication is not yet supported using the built-in HTTP operation

- ManagedServiceIdentity is not yet supported using the built-in HTTP operation

### Q & A

Q: Why do I have to recreate the operation that uses the API connection?

- A: Currently, whilst Logic Apps v2 is in preview, the designer does not allow you to select or create a new connection when a `connections.json` file does not already exist, the only way
  around this is to recreate the operation that uses the connection, or create any operation that uses that connection inside a new workflow file.

Q: Why do I need to get a connection key to run locally?

- A: When running logic apps locally, the connection needs to use the 'Raw' authentication method for connections to work. When deploying to Azure, the authentication method needs to be `ManagedServiceIdentity`.
