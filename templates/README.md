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

| Property                          | Description                                              | Possible Value  |
|:---------------------------------:| -------------------------------------------------------- |:---------------:|
| `id`                              | ID of the template, ends with a guid                     | `/providers/Microsoft.Logic/galleries/public/templates/{guid}` |
| `name`                            | Same guid used in `id`                                   | `{guid}` |
| `type`                            | Indicate this is a template for Logic Apps               | `Microsoft.Logic/galleries/templates` |
| `properties.author`               | Name of the template author                              | String |
| `properties.categoryNames`        | Collection of categories in which the template is shown  | `enterprise_integration`, `general`, `producitivity`, `social`, `sync`,  `schedule` |
| `properties.description`          | Text description of the template                         | String | 
| `properties.displayName`          | Template name shown in template gallery                  | String |
| `properties.definition`           | The workflow definition of the template                  | A valid JSON object representing the workflow |
| `properties.connectionReferences` | Connection references for connector used in the template | |
| `properties.apiSummaries`         | Collection of connection referenced in the template for shown in template gallery | |
| `properties.changedTime`          | Timestamp in which the template was updated              | DateTime |
| `properties.createTime`           | Timestamp in which the template was created              | DateTime |
| `properties.popularity`           | Unsigned integer value indicating the populatiry of the template, lower value indicate higher popularity | Unsigned int |

## Creating a new template
The easiest way to create a new template is to build out the workflow using Logic Apps designer. 
1. Create a Logic App
2. Templatize and export the Logic App
3. Create template JSON with template metadata, [this sample](sample.json) is a great place to start

## Testing
To test a new template, it is the easiest to use Fiddler to redirect traffic.

The following script will redirect all traffic to Logic Apps' repository to your own fork.

1. Launch Fiddler.
2. Press Ctrl + R to launch Fiddler ScriptEditor.
3. Locate OnBeforeRequest methed, and add the following code to the method.

    ```javascript
    if (oSession.url.StartsWith("raw.githubusercontent.com/Azure/logicapps")) {
        oSession.url.Replace("Azure", "{replace with your GitHub username}");
    }

## Localization
Please authtor the template with text in the language of your choice.

## Contribution Guide
This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
