# Logic Apps Templates

## Introduction
Azure Logic Apps is an integration-Platform-as-a-Service (iPaaS) developed by Microsoft. With its innovative visual designer, you can build workflows that integrate different services without having to write a single line of code.

Template is a great starting point for new users or seasoned integration developers when creating a new workflow. A wide selection of templates are provided out of box, now you also have the opporutunity to contribute to the template gallary.

## Setup
To start developing template for Logic Apps, you will need the following:

* An active Azure subscription for test new templates in Logic Apps
* A GitHub account in order to submit pull request for your proposed change
* [Fiddler](http://www.telerik.com/fiddler) to redirect network traffic to test new templates

## Overview of the template structure

| Property                          | Description                                              | Example |
| --------------------------------- | -------------------------------------------------------- | --------------- |
| `id`                              | ID of the template, ends with a guid                     | `"/providers/Microsoft.Logic/galleries/public/templates/{guid}"` |
| `name`                            | Same guid used in `id`                                   | `"{guid}"` |
| `type`                            | Indicate this is a template for Logic Apps               | `Microsoft.Logic/galleries/templates` |
| `properties.author`               | Name of the template author                              | `"Jane Doe"` |
| `properties.categoryNames`        | Collection of categories in which the template is shown, possible values are `"enterprise_integration"`, `"schedule"`,`"producitivity"`,`"social"`,`"sync"`, and `"general"` | `["enterprise_integration", "sync"]` |
| `properties.description`          | Text description of the template                         | `"A useful template"` | 
| `properties.displayName`          | Template name shown in template gallery                  | `"Sync CRM with SQL"` |
| `properties.definition`           | The workflow definition of the template                  | See below |
| `properties.connectionReferences` | Connection references for connector used in the template | See below |
| `properties.apiSummaries`         | Collection of connection referenced in the template for shown in template gallery | |
| `properties.changedTime`          | Timestamp in which the template was updated              | `"2017-07-05T00:00:52.000Z` |
| `properties.createTime`           | Timestamp in which the template was created              | `"2017-07-05T00:00:52.000Z` |
| `properties.popularity`           | Populatiry of the template, always use `99`              | `99` |

### `properties.definition`
`properties.definition` is the object containing the workflow.

| Property         | Description                                    | Example |
| ---------------- | ---------------------------------------------- | --------------- |
| `$schema`        | Schema of the workflow definition language     | `"https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"` |
| `actions`        | Same guid used in `id`                         | `"{guid}"` |
| `parameters`     | Empty connection parameter object to be filled | `{"$connections": {"defaultValue": {}, "type": "Object"}` |
| `triggers`       | Trigger of the template Logic App              | |
| `contentVersion` | This value should always be `"1.0.0.0"`        | `"1.0.0.0"` |
| `outputs`        | Output of the Logic App, can be left empty     | | 

### `properties.connectionReferences`
`properties.connectionReferences` tells Logic Apps which connector to use for actions specified in the workflow.

| Property                      | Description                                | Example  |
| ----------------------------- | ------------------------------------------ | --------------- |
| `{connectionName}`            | Name of the connection, referenced by `properties.definition.actions.input.host.connection` | `"azurequeues"` |
| `{connectionName}.connection` | Connection to be created by the template user | `{"id": ""}` |
| `{connectionName}.api`        | Identify the connector used, this can be found under `$connections.value.{connectionName}.id` of your Logic App. Remember to substitude out your subscription and region  | `/subscriptions/{0}/providers/Microsoft.Web/locations/{1}/managedApis/azurequeues` |

### `properties.apiSummaries`
`properties.apiSummaries` determines how the template is shown in the template gallery.

| Property         | Description                                | Example  |
| ---------------- | ------------------------------------------ | --------------- |
| `[].type`        | Type of the connection, can be found under `definition.actions.{action}.type` | `"ApiConnection"` |
| `[].displayName` | Name of the connector | `"Dropbox"` |
| `[].iconUri`     | Icon of the connector  | `"https://az818438.vo.msecnd.net/icons/dropbox.png"` |
| `[].brandColor`  | Hex value of the brand color | `"#007ee5"` |

*You can find out the icon and brand color in DOM explorer. Feel free to leave it blank if you're having trouble locating the values, and we can help you fill it in.*

## Creating a new template
The easiest way to create a new template is to build out the workflow first using Logic Apps designer. Once you have a working Logic App, you can then templatize it. Depending on the complexity of the Logic Apps, you have a few different options:

1. Manually edit the Logic App code view
1. Use "Download" functionality in Cloud Explorer in Visual Studio
1. Use [Logic Apps template creator script](https://github.com/logicappsio/LogicAppTemplateCreator)

Once the Logic App is templatized, it can be plugged into the [sample template file](sample.json), add other required metadatas and you are good to go.

## Add template to the manifest
Once the template is created, add it to [manifest.json](manifest.json) so that it can be indexed and rendered by Logic Apps.

## Testing
To test a new template, it is the easiest to use Fiddler to redirect traffic.

The following script will redirect all traffic to Logic Apps' repository to your own fork.

1. Launch Fiddler.
1. Press Ctrl + R to launch Fiddler ScriptEditor.
1. Locate OnBeforeRequest methed, and add the following code to the method.

    ```javascript
    if (oSession.url.StartsWith("raw.githubusercontent.com/Azure/logicapps")) {
        oSession.url.Replace("Azure", "{replace with your GitHub username}");
    }
    ```

Once the Fiddler url re-write is setup, you can navigate to Azure portal, launch a Logic App, navigate to "Template" page and see the changes you just made.

## Localization
Please authtor the template with text in the language of your choice. Please feel free to upvote to support localization in [UserVoice](https://feedback.azure.com/forums/287593-logic-apps/suggestions/20495815-support-localization-for-public-templates).

## Contribution Guide
This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
