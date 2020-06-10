# 4. Deploy to a Docker container

1. Build your project by running this command:
> dotnet build -c release

2. Publish your build by running this command:
dotnet publish

3. Build a Docker container by using a workflow. For example, here's a sample Docker file for a .NET workflow:
```dockerfile
FROM mcr.microsoft.com/azure-functions/dotnet:3.0.13614-appservice
ENV AzureWebJobsStorage <STORAGE_CONNECTION_STRING>
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \ AzureFunctionsJobHost__Logging__Console__IsEnabled=true
COPY ./bin/Release/netcoreapp3.1/publish/ /home/site/wwwroot
```

Note: Replace the <STORAGE_CONNECTION_STRING> value with the connection string to Azure Storage.

> docker build --tag local/workflowcontainer .

4. Run the container locally:
> docker run -p 8080:80 local/workflowcontainer

5. The callback url for request triggers can be obtained by making the following request
> POST /runtime/webhooks/flow/api/management/workflows/{workflowName}/triggers/{triggerName}/ listCallbackUrl?api-version=2019-10-01-edge-preview&code=<MASTER_KEY>

## Getting the master key

You can learn how to obtain the `Master_Key` value in this [GitHub issue](https://github.com/Azure/azure-functions-docker/issues/84), but to summarize:

The master-key is defined in the storage account you have set for `AzureWebJobsStorage` in `azure-webjobs-secrets/{deployment-name}/host.json` It should look something like this:

```json
{ ... "masterKey": { "name": "master", "value": "{value in here}", "encrypted": false } ... }
```