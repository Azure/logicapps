# Logic Apps Templates

## Introduction
Azure Logic Apps is an integration-Platform-as-a-Service (iPaaS) developed by Microsoft.
With an innovative visual designer, you can build workflows that integrate different services without having to write any code.

Whether you're a new or a seasoned integration developer, you can use templates as a quick starting points for creating workflows.
Azure Logic Apps offers a wide range and variety of predefined templates, but you can also contribute to the template gallary.

## Setup
To start developing templates for Azure Logic Apps, you need these items:

* An active Azure subscription so you can test templates in Azure Logic Apps.

    If you don't have a subscription, you can start with a [free Azure account](https://azure.microsoft.com/free/), or [sign up for a Pay-As-You-Go subscription](https://azure.microsoft.com/pricing/purchase-options/).
* A [GitHub](https://github.com/) account so you that can submit pull requests for your proposed changes
* [Fiddler](http://www.telerik.com/fiddler) so that you can redirect network traffic to test your new templates

## Overview of the template structure

| Property                          | Description                                              | Example |
| --------------------------------- | -------------------------------------------------------- | --------------- |
| `id`                              | The template ID, ends with a GUID                        | `"/providers/Microsoft.Logic/galleries/public/templates/{guid}"` |
| `name`                            | The same GUID that you used for `id`                     | `"{guid}"` |
| `type`                            | Indicates that this template is for Logic Apps           | `Microsoft.Logic/galleries/templates` |
| `properties.author`               | The template's author name                               | `"Jane Doe"` |
| `properties.categoryNames`        | The collection of categories where the template appears. Possible values: `"enterprise_integration"`, `"schedule"`,`"producitivity"`,`"social"`,`"sync"`, and `"general"` | `["enterprise_integration", "sync"]` |
| `properties.description`          | The template's text description                          | `"A useful template"` | 
| `properties.displayName`          | The template name shown in template gallery              | `"Sync CRM with SQL"` |
| `properties.definition`           | The template's workflow definition                       | See below |
| `properties.connectionReferences` | The connection references for the connector used in the template | See below |
| `properties.apiSummaries`         | The collection of connections referenced in the template and shown in template gallery | |
| `properties.changedTime`          | The timestamp for when the template was updated          | `"2017-07-05T00:00:52.000Z` |
| `properties.createTime`           | The timestamp for when the template was created          | `"2017-07-05T00:00:52.000Z` |
| `properties.popularity`           | The template's popularity, always use `99` when submitting a new template | `99` |

### `properties.definition`
`properties.definition` is an object that defines and contains the logic app workflow.

| Property         | Description                                       | Example |
| ---------------- | ------------------------------------------------- | --------------- |
| `$schema`        | The schema of the workflow definition language    | `"https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"` |
| `actions`        | The actions for the Logic App template            | `"{guid}"` |
| `parameters`     | Empty connection parameter object to be filled    | `{"$connections": {"defaultValue": {}, "type": "Object"}` |
| `triggers`       | The trigger for the Logic App template            | |
| `contentVersion` | Always set this value to `"1.0.0.0"`              | `"1.0.0.0"` |
| `outputs`        | The logic app's output, which you can leave empty | | 

### `properties.connectionReferences`
`properties.connectionReferences` tells Logic Apps which connector to use for the specified actions in the workflow.

| Property                      | Description                                | Example  |
| ----------------------------- | ------------------------------------------ | --------------- |
| `{connectionName}`            | The connection's name and referenced by `properties.definition.actions.input.host.connection` | `"azurequeues"` |
| `{connectionName}.connection` | The connection created by the template user | `{"id": ""}` |
| `{connectionName}.api`        | Identifies the connector used and is found under `$connections.value.{connectionName}.id` for your logic app. Make sure to replace your Azure subscription ID and region with placeholders | `/subscriptions/{0}/providers/Microsoft.Web/locations/{1}/managedApis/azurequeues` |

### `properties.apiSummaries`
`properties.apiSummaries` determines how your template appears in the template gallery.

| Property         | Description                                                              | Example |
| ---------------- | ------------------------------------------------------------------------ | --------------- |
| `[].type`        | The connection's type and found under `definition.actions.{action}.type` | `"ApiConnection"` |
| `[].displayName` | The connector's name                                                     | `"Dropbox"` |
| `[].iconUri`     | The connector's icon                                                     | `"https://az818438.vo.msecnd.net/icons/dropbox.png"` |
| `[].brandColor`  | The hex value for the brand color                                         | `"#007ee5"` |

*To find the icon and brand color values, you can use the Document Object Model (DOM) Explorer.* 
*Or, if you have trouble finding these values, feel free to leave these properties empty.* 
*We can help you fill in these values.*

## Creating a new template
To get started, first build your logic app with the Logic Apps Designer. 
You can then create a template more easily and quickly after you get your logic app working. 
Depending on your logic app's complexity, you have several options:

* Manually edit your logic app in Logic App Code View.
* Download your logic app into Visual Studio by using Cloud Explorer.
* Run the [Logic Apps template creator script](https://github.com/jeffhollan/LogicAppTemplateCreator).

After you create your logic app template, you can plug the template into the [sample template file](sample.json),
add other required metadata, and you're good to go.

## Add your Logic App template to the manifest for indexing and rendering
When you're ready, add your template to the [manifest.json file](manifest.json) 
so that Logic Apps can index and render the template.

## Test your logic app template
For the easiest experience when testing your template, redirect traffic by using Fidder.
You can use this script, which redirects all traffic to the Logic Apps repository to your own fork instead:

1. Start Fiddler.
2. Launch Fiddler ScriptEditor by pressing Ctrl + R.
3. Find the `OnBeforeRequest` method. Add this code to that method:

    ```javascript
    if (oSession.url.StartsWith("raw.githubusercontent.com/Azure/logicapps")) {
        oSession.url.Replace("Azure", "{replace with your GitHub username}");
    }
    ```

After the Fiddler URL rewrite finishes setting up, you can browse to the Azure portal,
run a logic app, browse to the "Template" page, and see your changes.

## Localization for your template
You can write the template text in any language that you choose. 
To vote for localization support, upvote this 
[UserVoice suggestion](https://feedback.azure.com/forums/287593-logic-apps/suggestions/20495815-support-localization-for-public-templates) suggestion.

## Contribution Guide
This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
