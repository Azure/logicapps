# Azure Logic Apps (Standard)

## Bundle and NuGet version 1.55.x
- **AS2** and **Flat File** operations: Added new settings.
- Agreements:
  - Removed limit.
  - EDI actions that fetch an agreement from a Premium integration account can now find the agreement, regardless the number of agreements, using the filtering API.
- **X12 Encode** built-in action: Now supports encoding batch messages.
- **SFTP** built-in operations: Now include the `inferContentType` parameter.
- **CICS** built-in, service provider-based operations: Now available.
- **IMS** built-in, service provider-based operations: Now available.
- **SI3270** built-in, service provider-based operations: Now available.
- Premium integration account: Bug fix for null path, null map name, and null schema name.

- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.49.x
- **X12 Encode** built-in action: Added support for X12 interchange encode.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.44.x
- **Azure Storage Blob** built-in connector: Add action named **Copy Blob by URI**.
- **X12 Decode** built-in action: Fix action to properly handle the CRLF delimiters.
- **Transform XML** built-in action: Adding transform options so that you can, for example, disable the byte order mark during XML transformation.
- **AS2** built-in actions: Increase agreement limit from 25 to 50 in an integration account.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.41.x
- Azure Blob Storage built-in connector: Added support for blob full path in operation outputs. The output property will contain the complete blob path, including the container name.
- Azure Blob Storage built-in connector: Added action named **Upload blob to storage container referenced by URI**.
- Azure Blob Storage built-in connector: Added the ability to disable automatic content type inference in the actions named **Read blob content** and **Read blob content referenced by URI**.
- Azure Blob Storage built-in connector: Added action named **Read blob content referenced by URI**.
- Azure Service Bus built-in connector: Added new session-based triggers and actions.
- Application Insights: Fixed live streaming capabilities.
- Integration account - Premium tier: Added support for XML actions.
- Workflow Language Definition support for functions that encode and decode an XML element name and value: **encodeXmlValue()**, **decodeXmlValue()**, **encodeXmlName()**, and **decodeXmlName()** 
- Enhanced Byte Order Mark (BOM) input support for string, binary and loading XML
- AS2 built-in connector: Fixed bug with invalid callback URL validation.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.33.x
- Various bug fixes and improvements
<br><br>


## Bundle and NuGet version 1.31.x
- Fix bug in JavaScript action to properly retry transient failures.
- Increased `EventGridPublisherConnectionPoolSize` default value to `64`.
- Fixed bug: SAP error **Unable to allocate client in pool, peak connections limit 10 exceeded**
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.23.x
- Various bug fixes and improvements
<br><br>

## NuGet and Bundle version 1.21.13
- Various bug fixes and improvements
<br><br>

## NuGet version 1.19.5 | Bundle version 1.19.5 Latest
- Enable Zstandard compression algorithm for Azure Logic Apps (Standard) running on Windows.

   **Important**: This update isn't backward compatible with Azure Logic Apps Standard extension 1.13.0.0 and earlier because this change affects the format of persisted data. If you're upgrading your extension version, before you install this release, upgrade to version 1.3.x.x.

- Service Bus built-in connector
  - **Create a topic subscription** action: Add correlation filter named **userProperties**.
  - Peek-lock triggers and **Complete the message** action: Can now now run in stateful workflows with splitOn disabled. To enable this capability, see [Enabling Service Bus and SAP built-in connectors for stateful workflows](https://techcommunity.microsoft.com/t5/integrations-on-azure-blog/enabling-service-bus-and-sap-built-in-connectors-for-stateful/ba-p/3820381).

- Add custom JSON parsing to preserve the Raw data type format under config for download JSON content from Blob.
- Fix runtime issue with using a logic app as the map source.
- Add the following Data Mapper functions:

  **Looping**
  - sort()
  - distinct-values()
  - reverse()
  - sub-sequence()
  - filter()

  **Addition**
  - add-daytime-to-date()
  - add-daytime-to-datetime()
  - add-daytime-to-time()
  - add-yearmonth-to-date()
  - add-yearmonth-to-datetime()

  **Comparison**
  - is-dateTime()
  - is-day-equal()
  - is-equal-date()
  - is-equal-datetime()
  - is-equal-time()
  - is-greater-than-date()
  - is-greater-than-datetime()
  - is-greater-than-time()
  - is-less-than-date()
  - is-less-than-datetime()
  - is-less-than-time()
  - is-month-equal()
  - is-monthday-equal()
  - is-year-equal()
  - is-yearmonth-equal()

  **Concatenation**
   - datetime()

  **Conversion**
  - adjust-date-to-timezone()
  - adjust-datetime-to-timezone()
  - adjust-time-to-timezone()
  - format-date()
  - format-time()

  **Get**
  - day-from-date()
  - day-from-datetime()
  - hours-from-datetime()
  - hours-from-time()
  - minutes-from-datetime()
  - minutes-from-time()
  - month-from-date()
  - month-from-datetime()
  - seconds-from-datetime()
  - seconds-from-time()
  - timezone-from-date()
  - timezone-from-datetime()
  - timezone-from-time()
  - year-from-date()
  - year-from-datetime()

  **Subtraction**
  - subtract-dates()
  - subtract-daytime-from-date()
  - subtract-daytime-from-datetime()
  - subtract-daytime-from-time()
  - subtract-datetimes()
  - subtract-times()
  - subtract-yearmonth-from-date()
  - subtract-yearmonth-from-datetime()

<br><br>

## NuGet version 1.15.24 | Bundle version 1.15.24
- Azure Service Bus built-in connector: Added support for **When messages are available...(peek-lock)** triggers and **Complete the message** action to run in stateful workflows.
- Fixed an unhandled exception bug with the actions named Transform XML and XML Validation.
- XML Transform action: Added support for using with integration account.
- SAP
    - SAP built-in connector: Added Get IDoc status and Read table actions.
    - Enable starting the SAP design-time worker for local authoring.
- SFTP built-in connector: Added **Delete folder** action.
<br><br>

## NuGet version 1.11.15 | Bundle version 1.11.15
- Data Mapper: Added as a new operations category in the designer.
- Data Mapper operations: Added a new action named **Transform using Data Mapper XSLT** for working with XSLT generated from the Data Mapper tool.
- Batch operations: Added support for **Batch messages** trigger and **Send to batch** action in Standard workflows.
- RosettaNet operations: Added support in Standard workflows.
<br><br>

## NuGet version 1.8.9 | Bundle version 1.8.9
- Inline Code built-in connector: Added support for throwing strings from the **Execute JavaScript Code** action. These strings appear in the message for the action's error object.
- SFTP and FTP built-in connectors: Enabled concurrency settings for triggers.
- SAP built-in connector: Added **Create stateful session** and **Close stateful session** actions.
- SAP built-in connector: Added support for BizTalk-style XML IDoc.
- Azure Blob built-in connector: Fixed bug for blob trigger and **Read blob content** action.
<br><br>

## NuGet version 1.3.7 | Bundle version 1.3.7
- Removed "preview" tags from built-in connectors now generally available (GA):

  - Azure Automation
  - Azure Event Grid Publisher
  - Azure Event Hubs
  - Azure File Storage
  - Azure Key Vault
  - Azure Queue Storage
  - Azure Service Bus
  - Azure Table Storage
  - Flat File
  - FTP
  - Liquid
  - SFTP
  - SMTP
  - SQL Server
  - XML operations

- Add support for workflow metrics and move status as a dimension.
- FTP built-in connector: Add a new action named **Extract archive**.
- **Microsoft.Azure.Workflows.ContentStorage.ContentStorage.RequestOptionsThreadCount** configuration setting; This new setting manages the blob upload or download thread count and forces the runtime to use multiple threads when uploading or downloading content from an action's inputs or outputs. To configure this setting, see the documentation at [https://aka.ms/logic-apps-settings](https://aka.ms/logic-apps-settings).
- SFTP built-in connector: Added the action named **Extract archive**. This action unpacks a ZIP archive file that either exists on the SFTP server or is provided by the output from a preceding action in the workflow.
- Increase the default parameters limit from 50 to 500 and introduce a configuration setting named "Microsoft.Azure.Workflows.TemplateLimits.InputParametersLimit" to change this limit. For more information, see the documentation at [https://aka.ms/logic-apps-settings](https://aka.ms/logic-apps-settings).
- Add the "List blob directories" action for the Azure Blob Storage built-in connector. This action returns the directory details for the blob path provided in the request.
- Add normalization for the Flat File built-in connector.
- Fix the MD5 hash value.
- Fix the "Execute query" action for the DB2 built-in connector.
<br><br>

## NuGet version 1.2.18 | Bundle version 1.2.18
- Enabled SWIFT MT operations.
- Standardized capitalization and wording compared to other operations. Updated for clarity and easier comprehension.
- XSLT Net FX worker.
- Fixed a bug to show the input parameter named **Table Name** in designer view for the **Query Entities** action for the Azure Tables Storage built-in connector.
- Azure Queue connector: 
   - Add new trigger named **When messages are added in a queue**.
   - Add support for dynamic schema.
- Added support to override default hostname for Azure Logic Apps Standard through the application configuration setting named **`Workflows.CustomHostName`**.
- SAP built-in (service provider) connector: New preview with the **Call RFC** action.
- Updated **Microsoft.Azure.WebJobs.Extensions.ServiceBus** from 5.5.0 to 5.7.0.
- Updated **Azure.Messaging.ServiceBus** from 7.8.1 to 7.10.0.
- Throw a 500 status error instead of a bad request to enable retries.
<br><br>

## NuGet version 1.2.9 | Bundle version 1.2.5
- Liquid: Fixed operation manifest to have any content type.
- Added support to the **nthIndexOf()** function for negative indexes as an occurrence number.
<br><br>

## NuGet version 1.2.7 | Bundle version 1.2.11
- Added sort() and reverse() functions to template expression language.
- Enable custom retry policy for users in SFTP operations.
- Updated **Microsoft.Azure.WebJobs.Extensions.EventHubs** to 5.1.1.
- Updated **Azure.Messaging.EventHubs** to 5.7.1.
- Updated **Microsoft.Azure.WebJobs** to 3.0.33.
- Updated **Azure.Core** to 1.25.0.
- Azure Queue built-in connector: Added support for managed identity and Azure Active Directory authentication.
- Handle empty queue scenarios diligently.
- Azure Key Vault built-in connector: Added and enabled support for dynamic schema.
- SQL Server built-in connector: Added and enabled support for managed identity and Azure Active Directory authentication.
- **Upload file** action - The **File content** parameter is optional.
- Added new action named **Copy file**.
- Azure Queue Storage built-in connector: Added **List queues** action.
- Azure File Storage built-in connector: Added all actions supported by the managed connector.
<br><br>

## NuGet version 1.2.6 | Bundle version 1.2.10
- AS2 built-in connector: Added support for actions.
- Liquid actions: Added support for integration account.
- Add new **chunk()** function to template expressions. 
<br><br>

## NuGet version 1.2.3 | Bundle version 1.1.35
- Various bug fixes and improvements
<br><br>

## NuGet version 1.2.2 | Bundle version 1.1.33
- Fixed consistency issue that happened while deleting workflows from Standard logic app resource.
- Fallback to storage when a workflow isn't found in the memory cache for the Edge browser.
- SFTP connector now supports following actions:
  - Get metadata
  - List folder
  - Delete file
  - Create folder
  - Rename file
- Added Flat File cache for schema processing.
- Removed limits on entity sizes for the stateless provider and so stateless runs.
- Added support for **connections.json** and **parameters.json** file validation using the validate API. Pass the **connections.json** body using the "connections" field and **parameters.json** body using the "parameters" field in the request body under "properties". The **workflow.json** is passed using the "definition" field as before.
- Stateless workflows: Enabled pagination, concurrency, retries, and static result.
- SFTP built in connector: Added support in the **Upload File Content** action to upload data to a file on remote server. If the file already exists, that file is overwritten.


## NuGet version 1.2.1 | Bundle version 1.1.32
- Added two new functions to the logic apps expression language: **parseDateTime()** and **slice()**.
- **formatDateTime()** function: Added a new optional **locale** parameter.
- **indexOf()** function: Added a new optional **nth occurrence** parameter.
- Azure Service Bus built-in connector: Added system properties.
- SQL Server built-in connector: Updated the default timeout for the setting named **ServiceProviders.Sql.QueryExecutionTimeout** from 30 seconds to 2 minutes.
- Introduced necessary material to be able to split dynamic schemas input and output limits.
- Azure Service Bus built-in connector: Added support for sessions in topic subscription triggers.
<br><br>

## NuGet version 1.1.9 | Bundle version 1.1.26
- Stateless workflows: To improve performance, added response notification channel.
- Built-in recurrence triggers: Added state support, allowing states to persist though repeated trigger iterations.
- **decimal()** function: This new function takes in a decimal number as a string so that you can use in other math functions. For more information, see [https://aka.ms/logicexpressions#decimal](https://aka.ms/logicexpressions#decimal).
<br><br>

## NuGet version 1.1.8 | Bundle version 1.1.25
- Azure Functions built-in connector: Added retry settings to the **Call an Azure Function** action.
- Added InsertRow Action
- Added UpdateRow Action
- Added DeleteRow Action
- DB2 built-in connector: Set all actions to preview.
- IBM Host File built-in connector: Set all actions to preview.
<br><br>

## NuGet version 1.1.7 | Bundle version 1.1.24
- Handle job execution errors that could happen due to partial resource availability when the host is being recycled.
- Event Hub built-in connector: Add option to specify Consumer Group.
- DB2 built-in connector: Add **Get Tables** action from the managed connector.
<br><br>

## NuGet version 1.1.5 | Bundle version 1.1.20
- Built-in connector (service provider manifest): Added new retry capability so you can configure retries on the custom built-in connectors.
- DB2 built-in connector: Added new connection parameters, so that you can use either connection parameters or the previous connection string field.

- IBM Host File built-in connector: Added new connector.
- Built-in connectors: For service provider-based connectors, a new feature was added so that a service provider implementer can provide additional trigger parameters, which the customer can't update in the workflow definition. For example, if a service provider wants to add a default parameter and doesn't want the trigger user to override its behavior, the provider can add that parameter using this implementation. <br><br>To use this feature, implement the **GetFunctionTriggerDefinition()** method on the **IServiceOperationsTriggerProvider** interface. Create **FunctionTriggerDefinition** correctly by setting the function trigger type (TriggerType) and a dictionary with the additional parameters.

<br><br>


## NuGet version 1.1.4 | Bundle version 1.1.19
- Stateless workflows: Decouple dispatcher worker configuration from stateful workflows.
- SQL Server built-in connector: Fixed bug in the **Execute Query** action to respect the **QueryExecutionTimeout** setting.
- DB2 built-in connector: Added this connector, which uses managed drdaclient.
<br><br>

## NuGet version 1.1.3 | Bundle version 1.1.17
- Request built-in trigger: Fixed bug to correctly handle CORS request calls.
