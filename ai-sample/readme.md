# Create a **Chat with Your Data** Logic App Project

This readme document provides step-by-step instructions on how to enable a **Chat with your Data** Logic Apps project.

## Prerequisites

Before you begin, make sure you have the following prerequisites installed:

- [Visual Studio Code](https://code.visualstudio.com/)
- [Azure Logic Apps extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-logicapps)
- [Azure Functions extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azurefunctions)
- [Azurite extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=Azurite.azurite)
- Access to an Azure OpenAI Service
- Access to an Azure AI Search Service
- This guide also assumes you have pulled this repo down to your local machine.

## Steps
There are 2 projects that need to be created and published to Azure:
 - Azure Functions project located in `TokenizeDocFuntion` folder
 - Azure Standard Logic Apps project located in `SampleAIWorkflows` folder

### Follow these steps to create the Azure Functions project and deploy it to Azure:

1. Open Visual Studio Code.

2. Go to the Azure Function extension.

3. Under Azure Function option, click `Create New Project` then navigate to and select the `TokenizeDocFunction` folder.

4. Follow the setup prompts:
   - Choose `Python` language
   - Choose Python programming model V1 or V2
   - Skip `Trigger Type` selection
   - Select `Yes` if asked to overwrite any existing files except the `requirements.txt` file

6. Deploy your Function App:
   - Go to the Azure Function extension.
   - Under the Azure Function option, click `Create Function App in Azure`
   - Select a Subscription and Resource Group to deploy your Function App.

7. Go to the Azure portal to verify your app is up and running.

8. Make note of the URL generated by your Function App, it will be used later inside of your `ingest` workflow.


### Follow these steps to create the Azure Standard Logic Apps project and deploy it to Azure:

 1. Open Visual Studio Code.

 2. Go to the Azure Logic Apps extension.

 3. Click `Create New Project` then navigate to and select the `SampleAIWorkflows` folder.

 4. Follow the setup prompts:
    - Choose Stateful Workflow
    - Press Enter to use the default `Stateful` name. This can be deleted later
    - Select `Yes` if asked to overwrite any existing files

 5. Update your connections.json file:
    - Repalce the text `{Your_AzureOpenAI_Endpoint}` and `{Your_AzureOpenAI_Key}` with your own Azure OpenAI endpoint and authentication key, respectively.
    - Replace the text `{Your_AzureAISearch_Endpoint}` and `{Your_AzureAISearch_AdminKey}` with your own Azure AI Search endpoint and admin key, respectively.
 
 6. Update the `Tokenize_a_document` function, replacing the URL path with the URL path from your newly created Azure Function.
 
 7. Deploy your Logic App:
    - Go to the Azure Logic Apps extension
    - Click `Deploy to Azure`
    - Select a Subscription and Resource Group to deploy your Logic App

 7. Go to the Azure portal to verify your app is up and running.
 
 8. Verify your Logic Apps contains two workflows. They will be named: `chat-workflow` and `ingest-workflow`.

## Run your workflows

Now that the Azure Function and Azure Logic App workflows are live in Azure. You are ready to ingest your data and chat with it.

 ### Ingest Workflow
 1. Go to your Logic App in the Azure portal.
 
 2. Go to your `ingest` workflow.

 3. On the `Overview` tab click the drop down `Run` then select `Run with payload`.

 4. Fill in the JSON `Body` section with your `fileUrl` and `documentName`. For example: `{ "fileUrl": "https://mydata.enterprise.net/file1", "documentName": "file1" }`

 5. Click `Run`, this will trigger the `ingest` workflow. This will pull in your data from the above file and store it in your Azure AI Search Service.

 6. View the `Run History` to ensure a successful run.

### Chat Workflow
1. Go to your Logic App in the Azure portal.
 
 2. Go to your `chat` workflow.

 3. On the `Overview` tab click the drop down `Run` then select `Run with payload`.

 4. Fill in the JSON `Body` section with your `prompt`. For example: `{ "prompt": "Ask a question about your data?" }`

 5. Click `Run`, This will trigger the `chat` workflow. This will query your data stored in your Azure AI Search Service and respond with an answer.

 6. View the `Run History` to see the Response from your query.


## Conclusion

In this readme document, you learned how to create and deploy an Azure Function and multiple Logic Apps workflows using Visual Studio Code and their respective extensions. 

For more information and advanced usage, refer to the official documentation of Azure Logic Apps and Azure Functions.