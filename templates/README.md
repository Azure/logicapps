# Logic Apps Templates

## Introduction
Azure Logic Apps is an integration-Platform-as-a-Service (iPaaS) developed by Microsoft. With its innovative visual designer, you can build workflows that integrate different services without having to write a single line of code.

Template is a great starting point for new users or seasoned integration developers when creating a new workflow. A wide selection of templates are provided out of box, now you also have the opporutunity to contribute to the template gallary.

## Setup
To start developing template for Logic Apps, you will need the following:

* An active Azure subscription
* A GitHub account
* Fiddler

## Overview of the template structure

| Property                        | Description                                                                       | Possible Value  | Example |
| ------------------------------- | --------------------------------------------------------------------------------- | ----- | ----- |
| id                              | right-aligned                                                                     | $1600 | |
| name                            | centered                                                                          |   $12 | |
| type                            | Indicate this is a template for Logic Apps                                        | Microsoft.Logic/galleries/templates | Microsoft.Logic/galleries/templates |
| properties.author               | Name of the template author                                                       | Any string                          | Jane Doe |                            |
| properties.categoryNames        | Categories in which the template is shown                                         | enterprise_integration, general, producitivity, social, sync,  schedule | ["schedule"], ["general", "sync"]   |
| properties.description          | Text description of the template                                                  | Any string | This is a great template to try out |
| properties.displayName          | Template name shown in template gallery                                           | Any string | Service Bus Peek-Lock Pattern |
| properties.galleryName          | centered                                                                          | public | public |
| properties.summary              | are neat                                                                          | "" | "" |
| properties.definition           | The workflow definition of the template                                           | A valid JSON object representing the workflow | |
| properties.connectionReferences |                                                                                   |  | |
| properties.apiSummaries         | Collection of connection referenced in the template for shown in template gallery |    $1 | |
| properties.changedTime          | Timestamp in which the template was updated                                       | $1600 | |
| properties.createTime           | Timestamp in which the template was created                                       |   $12 | |
| properties.popularity           | are neat                                                                          |    $1 | |

## Creating a new template
The easiest way to create a new template is to build out the workflow using Logic Apps designer. 

## Testing
To test a new template, it is the easiest to use Fiddler to redirect traffic.

The following script will redirect all traffic to Logic Apps' repository to your own fork.

1. Launch Fiddler.
2. Press Ctrl + R to launch Fiddler ScriptEditor.
3. Locate OnBeforeRequest methed, and add the following code to the method.

    ```javascript
    if (oSession.url.StartsWith("raw.githubusercontent.com/Azure/logicapps")) {
        oSession.url.Replace("Azure", "derek1ee");
        oSession["ui-color"] = "red";
    }

## Localization
Please authtor the template with text in the language of your choice. 

## Contribution Guide
This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
