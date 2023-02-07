# Sample: Write and run your own custom code from a Standard workflow in Azure Logic Apps

> This capability is in preview and is subject to the [Supplemental Terms of Use for Microsoft Azure Previews](https://azure.microsoft.com/support/legal/preview-supplemental-terms/).

With the custom code feature in Azure Logic Apps (Standard), you can write your own code as a function using the .NET Framework, and then use the custom code feature to run that function from a Standard logic app workflow. To illustrate, the provided sample project uses the custom code capability and includes the following applications:

- A Standard logic app named **WorkflowLogicApp**
- An Azure function app named **Function**

## Prerequisites

- For Visual Studio Code, make sure to meet the [prerequisites to create a Standard logic app](https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-visual-studio-code#prerequisites) and the [prerequisites to create a function app](https://learn.microsoft.com/azure/azure-functions/functions-develop-vs-code), which include the [extensions for Azure Logic Apps (Standard) and Azure Functions](https://marketplace.visualstudio.com/VSCode).

- Copy and update the sample project by following these steps:

  1. Clone the following GitHub repository to your local computer:

     `git clone https://github.com/Azure/logicapps.git`

  1. On your computer, go to the folder that contains the sample project.

  1. Open the project's .csproj file, and add the following line to specify the project attribute named `WorkflowActionTrigger`, which pulls the required NuGet package into the sample project:

     ```xml
     <PackageReference Include="Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger" Version="1.0.0" />
     ```

     For the link to the MyGet package that stores this NuGet package, see [Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger 1.0.0](https://www.myget.org/feed/microsoft-workflowactiontrigger/package/nuget/Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger).

- To set up the custom code feature in a new project, create a single new workspace in Visual Studio Code with the following steps. You need this workspace so that both the logic app and function app can run at the same time.

  1. On your computer, create a new folder.

  1. From Visual Studio Code, open the created folder.

  1. From the **Terminal** menu, select **New Terminal**. (Keyboard: Ctrl + Shift + 5)

  1. In the terminal window, run the following command to create a new solution:

     `dotnet new sln -n FunctionApp`

  1. Add your function app's **dev.csproj** file to the created solution by running the following command:

     `dotnet sln add src/dev/dev.csproj`

  1. From the **File** menu, select **Add Folder To Workspace**. Add the logic app project folder directly to your workspace.

  1. Go to the following location, and open the **tasks.json** file:

     `..\<yourfunctionfolder>\.vscode\tasks.json`

  1. Check that the **tasks.json** file has the following build task to build the function app:

     `{ "label": "build", "command": "dotnet", "type": "process", "args": [ "build", "${workspaceFolder}"] }`

  1. Save all your changes as a workspace. From the **File** menu, select **Save as Workspace**.

## Create your custom code function

This section describes how to set up your project so that you can add and call your own custom code function. The sample project contains an example that shows how to set up and call your custom code function. To find this example, go to the sample function app's **Function** folder, and review the class file named **FlowInvokedFunction.cs**. This class file contains the sample .NET custom code that an Azure function runs.

1. In Visual Studio Code, from the [Activity Bar](https://code.visualstudio.com/api/ux-guidelines/activity-bar) on the left side, select **Azure**, which opens the **AZURE** pane.

1. To add an Azure function to your workspace, in the **AZURE** pane, browse to **WORKSPACE** > **Local Project** > **Functions**.

1. On the **WORKSPACE** section's toolbar, select **Create Function** (lightning icon).

   ![Screenshot that shows Visual Studio Code, 'Azure' pane, 'Workspace' section expanded to 'Functions', and on the section toolbar, the 'Create Function' button is selected.](https://user-images.githubusercontent.com/111014793/217051951-c1f39778-1070-48c8-b7db-dbff681b3adf.png)  

1. Select the folder where you want to put your function. This folder is the workspace from where you want to run both your function and logic app workflow.

1. For the language, select **C#**. For the .NET runtime, select **.NET Framework**.

1. For the template, select **Skip for now** because you're authoring a custom Azure function.

1. Rename the **Program.cs** C# class file to the name for your custom code function.

1. Confirm that your C# class file contains the following items:

   - A namespace for your project
   - A public static class with the same name as your file, a function header, and the code that you want to call. 

   In any function that includes custom code, the function header must include the Azure Functions trigger that's named **WorkflowActionTrigger** to correctly run that custom code. Make sure that your function includes the following items:

   | Item | Value | Description |
   |------|-------|-------------|
   | Function name | `[FunctionName("FlowInvokedFunction")]` | The name for your custom code function |
   | Workflow action trigger | `[WorkflowActionTrigger]` | The respective trigger that you must add to correctly call your custom code function |
   | Parameter values | `public static Task<Wrapper> Run([WorkflowActionTrigger] string parameter1, int parameter2)` | Any parameter values that your custom code function requires. If your custom code function doesn't have parameters, you can set these values to null. |

   The following code example shows the references to the required items:

   ```csharp
   /// <summary>
   /// The flow invoked function.
   /// </summary>
   public static class FlowInvokedFunctionTest
   {
       /// <summary>
       /// Run method.
       /// </summary>
       /// <param name="parameter1">The parameter 1.</param>
       /// <param name="parameter2">The parameter 2.</param>
       [FunctionName("FlowInvokedFunction")]
       public static Task<Wrapper> Run([WorkflowActionTrigger] string parameter1, int parameter2)
       {
           var result = new Wrapper
           {
               RandomProperty = new Dictionary<string, object>(){
                   ["parameter1"] = parameter1,
                   ["parameter2"] = parameter2
               }
           };

           return Task.FromResult(result);
       }
   }
   ```

1. Check that your file follows the function class skeleton structure in the sample project, for example:

   ![Screenshot that shows Visual Studio Code, C# class file, and example custom code function skeleton structure.](https://user-images.githubusercontent.com/111014793/217053377-37dfdf85-f566-4b0a-9f31-b44ca336d023.png)

1. In the sample project, open the sample function app's **Function** folder, and then open the **dev.csproj** file.

   The **dev.csproj** file contains configured build steps that copy the required assemblies to call a custom function.

1. From the sample **dev.csproj** file, copy the contents to your own project.

1. In your copy, find the following **<LogicAppFolder></LogicAppFolder>** element: `<LogicAppFolder>WorkflowLogicApp</LogicAppFolder>`

1. Replace the default value with the folder name for your logic app project, for example: `<LogicAppFolder>MyLogicAppWorkflow-CustomCode</LogicAppFolder>`

1. If **WorkflowActionTrigger** isn't automatically configured, follow these steps:

   1. from the **Terminal** menu, select **New Terminal**. In the terminal window, enter `dotnet restore`.

   1. After the restore operation completes, run the build task that's configured for the function app. From the **Run** menu, select **Run Task** > **Build**.

## Set up your logic app workflow to call your custom code function

The sample logic app project includes the following files relevant to the custom code capability:

| Item | Description |
|------|-------------|
| **workflow.json** | The JSON file that defines a workflow in your logic app project |
| **host.json** | The JSON file where you have to enable a specific value to run the **Invoke a function** action used by the custom code capability: <br><br>`"extensions": { "workflow": { "settings": { "Runtime.IsInvokeFunctionActionEnabled": "true" } }` |

1. In Visual Studio Code, open the **workflow.json** file shortcut menu, select **Open in Designer**.

   ![Screenshot that shows Visual Studio Code, workspace, Standard logic app project, 'workflow.json' file with open shortcut menu, and 'Open in Designer' selected.](https://user-images.githubusercontent.com/111014793/217036602-01f92e50-256f-4e3d-b27d-1f9e0808f035.png)

1. In the designer search box, find and select the built-in action named **Invoke a function in this Logic App**. This action is part of the **Local Function operations** collection.

   ![Screenshot that shows the Standard workflow designer with the action named 'Invoke a function in this logic app' selected.](https://user-images.githubusercontent.com/111014793/217037045-b6e550a3-0bee-4eef-8770-c30b9279bec8.png)

1. When the selected action appears on the designer, in the **Function Name** property, enter the name for your function.

1. In the **Function parameters** property, enter any parameters that your function requires, for example:

   ![Screenshot that shows the Standard workflow designer, the 'Invoke a function in this Logic App' action, plus the 'Function Name' and 'Function parameters' property values entered.](https://user-images.githubusercontent.com/111014793/217037991-23ad112e-d50f-4040-8d48-6eb10e508d53.png)

1. When you're done, on the designer toolbar, select **Save**.

1. From the **Run** menu, select **Run Without Debugging**. (Keyboard: Ctrl + F5)

   ![Screenshot that shows the Visual Studio Code 'Run' menu with 'Run Without Debugging' selected.](https://user-images.githubusercontent.com/111014793/217038206-c254df23-f4ad-4e03-8800-4ad4cc1aa611.png)

1. After the workflow finishes running, from the **workflow.json** file shortcut menu, select **Overview**.

   ![Screenshot that shows the 'workflow.json' file's shortcut menu opened and the 'Overview' command selected.](https://user-images.githubusercontent.com/111014793/217038386-9cd5ce10-9f3b-4f64-b6ff-4a2d77228141.png)

1. On the **Overview** page that opens, select **Run trigger** to run your workflow's trigger.

   ![Screenshot that shows the workflow's 'Overview' page and the 'Run trigger' command selected.](https://user-images.githubusercontent.com/111014793/217038789-eaa3a736-e499-4e98-9935-91562d4ce6bf.png)

1. After the trigger runs, select the workflow run that just finished.

   ![Screenshot that shows the recent workflow run selected.](https://user-images.githubusercontent.com/111014793/217039132-f8828e74-4112-4ff3-afe7-2b2700a6b4fb.png)

   The workflow's run history opens to show whether the run successfully finished. From the page, you can review the output from your custom code.

   ![Screeshot shows a successful run with the inputs and outputs from the run.](https://user-images.githubusercontent.com/111014793/217039149-200745f1-9b8d-4562-ad31-530ae7ed50ad.png)

## Contributions

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact opencode@microsoft.com with any additional questions or comments.
