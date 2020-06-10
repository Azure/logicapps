# 1. Preview notes for participants

Azure Logic Apps Extensions for the Azure Functions runtime along with the new Visual Studio Code extension for Azure Logic Apps were created to provide a great developer experience for building logic app workflows. You can build these workflows in your development environment and deploy them to multiple hosting environments, such as Azure App Service, Azure Function App, or as a Docker container anywhere you want. Important: This early preview release provides an early look at functionality so that participants can give feedback. Bugs and issues are expected. These extensions for Azure Logic Apps bring most of the capabilities from Azure Logic Apps in the cloud to your local development experience. The extension also provides many new capabilities, for example:

## Managed API connectors

- Logic Apps offers 300+ managed connectors for connecting to Software-as-a-Service (SaaS) and Platform-as-a-Service (PaaS) apps and services.
- **Important:** Currently, access to cloud-based connectors requires enabling them at the subscription level. This action will initially be done on a case by case basis for select preview participants.
- You can still create connections that store credentials in the cloud for connectors, for example, OAuth access tokens for connecting to Outlook.
Logic Apps generates a Shared Access Signature (SAS) connection string that workflows running anywhere can use to send requests to the cloud connection runtime endpoint. This connection string is saved with other application settings so that you can easily store them in Azure Key Vault when deployed to Azure.

## Stateless workflows

You can author stateless workflows like any other workflow by using the Logic Apps Designer. However, unlike regular workflows, stateless workflows don't persist between actions, and don't store run histories by default.

- You can enable run histories, if necessary, for better debuggability.
- Stateless workflows provide faster response times and high throughput. Due to non-persistence, these workflows are also less costly to run.

## Additional connectors

Additional connectors, specifically, Event Hubs, Service Bus, and SQL, run in-process like built-in native connectors, and provide faster response time, high throughput, and no throttling, unlike the cloud-based connectors.

# Call Azure Functions

You can invoke an Azure function natively and directly from your workflow, which runs on the Azure Functions runtime.

1. [Set up your development environment](2-Set-up-your-development-environment.md)
2. [Develop, test and deploy](3-Develop-test-and-deploy-a-workflow-app.md)
3. [Deploy to a Docker container](4-Deploy-to-a-Docker-container.md)