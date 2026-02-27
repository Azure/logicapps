# Azure Logic Apps (Standard)

## Bundle and NuGet version 1.160.21
- Platform library update for Logic App Runtime.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.160.9
- **Agent workflows**: Added reasoning effort parameter, expanded model support, improved retry logic, and enhanced response format validation.
- **HL7 messaging**: Fixed MSH header parsing for large content, added custom target namespace support, and improved error handling.
- **SAP connector**: Fixed IDoc reception issue for unreleased segments.
- **FTP built-in connector**: Disabled EPSV (Extended Passive Mode) to improve compatibility.
- **MLLP connector**: Added Send message operation for HL7 message transmission.
- **MCP (Model Context Protocol)**: Improved tool call response handling with structured content support.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.156.x
- Agent and workflow improvements: Enhanced reliability for agent workflows, including better caching and validation for agent handoff and tool calls.
- Confluent connector: Now generally available and ready for production use.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.149.x
- **SAP** built-in trigger: Fixed support for large messages. Reduced CPU and memory overhead for SAP built-in trigger.
- **MCP servers in agents**: Preview capability for adding remote MCP servers to agents in workflows. Agents can then call tools in these MCP servers.
- **On-Behalf-Of (OBO) updates**: Expanded OBO authentication with dynamic connections and improved per-user context for agent workflows. Better CORS and preflight (OPTIONS request) support for A2A and agent endpoints.
- **RabbitMQ GA**: RabbitMQ connector operations are generally available (GA) and ready for production use.
- **Execute PowerShell GA**: Run inline PowerShell is generally available (GA) and lets you select the PowerShell version plus improved error handling. 
- **Security and authentication**: Improved security for agents and workflow authentication by excluding refresh tokens from API responses. Expanded support for Okta as an identity provider alongside Microsoft Entra.
- **HL7 and SAP messaging**: Enhanced HL7 support for more flexible line-endings and schema compatibility. SAP connector operations are more reliable and provide explicit exception handling for advanced integration scenarios.
- **API and workflow management**: Improved validation and state management for agent and A2A loop workflows. Workflow cloning, type switching, session controls, and token usage limits are now more robust, enabling safer workflow evolution and management.
- **Metrics, billing, and performance**: Enhanced in-memory cache usage and support for new metrics, including detailed billing and usage tracking for agent-based execution.
- **Parse document action with metadata GA**: The **Parse document with metadata** action is generally available (GA) and ready for production use.
- **Azure AI Document Intelligence GA**: The **Document Intelligence** connector operations are generally available (GA) and ready for production use.
- **Chunk text with metadata GA**: The **Chunk text with metadata** action is generally available (GA) and ready for production use.
- **Execute C# scripts GA**: Run inline C# is generally available (GA) and ready for production use. Added capability to use isolated worker process for running scripts. 
- [**Azure Logic Apps Labs**](https://aka.ms/lalabs): Refreshed content for Agent Loop, including support for Consumption workflows, bring your Azure API Management AI Gateway, Microsoft Team chat clients, MCP servers, and Easy Auth with Okta.
- Various bug fixes and general improvements.
<br><br>

## Bundle and NuGet version 1.145.x
- **SAP** connector operations: Added the **Gateway without work process** setting to enable SAP topologies with standalone gateways or with message server plus gateway-only instances. Helps resolve the following errors: "Gateway without R/3 connectivity" and "Gateway without work processes".
- **trimByteOrderMark()**: This new expression function removes the Byte Order Mark (BOM) characters from the beginning of strings or binary content and is especially useful for processing XML content.
- **Visual Studio Code designer**: Support dynamic schema-defined inputs and outputs for the **Compose XML with schema** and **Parse XML with schema** actions.
- **Compose XML with schema** and **Parse XML with schema** actions: Added support for more XML schema constructs.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.138.x
- **AI Foundry support**: Build agent workflows that run with AI Foundry models. Centrally manage agents and use AI Foundry capabilities like tools, threads, and more.
- **Autonomous agent workflows**: Build independent agent workflows that run with any available trigger. Start with new workflows or convert existing workflows by adding agent loops.
- **Conversational agent workflows**: Build agent workflows with native chat client support using the Agent-to-Agent (A2A) protocol. Includes standalone chat client secured with Easy Auth and Microsoft Entra ID.
- **Per user connections**: Build conversational agent workflows with user-scoped context so tools run with the identity of the signed-in user.
- **Nested agents**: Delegate tasks to other agents as tools by using the new action **Send a task to a nested agent**.
- **Agent handoff**: Support multi-agent patterns with capability to delegate task execution to specific agents.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.131.x
- Model Context Protocol (MCP) support: Create logic apps as remote MCP servers that use Server-Sent Events (SSE) and streamable HTTP transports for client-server communication.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.127.x
- **Compose XML with schema** and **Parse XML with schema** actions: Add support to choose XML schema.
- **Logic Apps Rules Engine**: General availability. For more information, see https://go.microsoft.com/fwlink/?linkid=2325117
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.123.x
- **Agent workflows**: Public preview for running agents in Standard workflows created with the **Agent** type. For more information, see https://go.microsoft.com/fwlink/?linkid=2320014.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.119.x
- **SAP** built-in connector: The response to SAP operations supports the SafeType parameter.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.114.x
- Custom code action: Enable support for dependency injection in .NET 8
- **FTP** built-in connector: Connection setup has an option to remove the connection after the operation completes.
- mergeObjects(): New expression function that merges two JSON objects.
- Parse XML action: Added support for **xs:ID** data type.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.94.x
- Data storage persistence: Enable ZStandard compression.

- Visual Studio Code extension: Added ability to generate unit tests and mock data from existing runs.

- Non-production slot logic apps: Enable more thorough workflow validation.

- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.91.x
- Custom code action: Enable support for external dependent assemblies in .NET 8.
- Data storage persistence: Enable ZStandard compression.
- **XML Compose** and **XML Parse**: Public preview for new built-in operations.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.87.x
- .NET Framework (NetFx) Worker: Add retry logic.
- Unsupported trigger type: Clarified error message.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.81.x
- **Service Bus** built-in connector: Added new peek-lock triggers and actions to remove dependency on fixed role instances for App Service Plan. The runtime is still supported for the existing operations. The designer uses the new operations for new workflows.
- **File System** built-in connector: For the **Append File** action, add new input parameter to create file, if non-existent.
- **File System** built-in connector: For the **Get File Content** action, add the **inferContentType** parameter.
- Workflow template: Fixed error handling for workflow template expression resolution errors.
- XML handling: Fixed inconsistent handling of various XML errors. The service now handles a range of .NET XML implementation parsing exceptions.
- **Azure OpenAI** and **Azure AI Search** built-in connectors: Now generally available with this change.
- **Data Operations** built-in actions: The **Chunk text** and **Parse a document** actions are now in Preview.
- **Call a local function in this logic app** built-in action: Added .NET 8 support for calling custom .NET code.
- **Integration Account Artifact Lookup** built-in action: Fixed a caching bug that caused the action to take a long time to complete.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.70.x
- **Azure OpenAI** and **Azure AI Search** built-in connectors: Now generally available with this change.
- **3270**, **Host File**, **CICS**, **IMS**, and **IBM i** built-in connectors: Now generally available with this change.
- **Azure Service Bus** built-in connector: Added support to get deferred messages.
- **Call local function in this logic app** built-in action: Supports .NET 8 Framework for authoring and running custom code.
- **Execute CSharp Script Code** built-in action: Added new action.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.66.x
- **Service Bus** action: Added support for using sessions to get deferred messages in Service Bus operations.
- **XML Transform** action: Fixed a bug where the action retried endlessly.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.62.x
- **AS2 Encode** action: Expose receiver URI in this action's output.
- **XML Transform** action: Fixed a bug where action continues to run when artifact name isn't valid.
- Azure Logic Apps runtime: Errors now appear in Azure portal notifications as error events, not information events.
- **XML Validation** action: Supports nested schemas in an integration account.
- Various bug fixes and improvements
<br><br>

## Bundle and NuGet version 1.58.x
- **AS2** and **EDIFACT**: Operations use `$filter` to find the necessary agreement, eliminating the limit on the number of agreements.
- **AS2** and **Flat File** operations: Added new settings.
- **AS2**: Actions that work with Standard integration account now support more than 40 agreements.
- Various bug fixes and improvements
<br><br>

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
