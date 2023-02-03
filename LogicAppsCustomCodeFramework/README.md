# Logic Apps Custom Code Feature

Custom Code is a new Logic Apps feature in which users can author their own custom code through the usage of .NET Framework code from an Azure Logic Apps workflow.
This project contains a sample project that utilizes this feature. The contents consist of a Logic App project (WorkflowLogicApp) and an Azure Function App (Function).  
## Installation

To run this sample, clone the repository to your local machine.

```bash
git clone https://github.com/Azure/logicapps.git
```
To pull the nuget package that contains the WorkflowActionTrigger attribute for your project. 

```bash
<PackageReference Include="Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger" Version="1.0.0" />
```

# Workspace Setup
To setup the Logic Apps Custom Code feature in a new project, start by creating a Workspace. Due to the nature of this project where there are two distinct applications that need to be ran simultaneously, it is important to create a single VS Code workspace in order to utilize both applications.The steps for doing so are as follows:

1) Create a new folder for your workspace. 
2) Open this new folder in VS Code and open a terminal.
3) In the terminal create a solution: ``` dotnet new sln -n FunctionApp ```
4) Add the csproj file of your function application to this solution. ``` dotnet sln add src/dev/dev.csproj ```
5) Add the logic app project folder directly to your workspace by clicking File -> Add Folder To Workspace. 
6) Ensure that there is a build task for building the function application in task.json. This should be located in "..\<yourfunctionfolder>\.vscode\tasks.json"

```	{ "label": "build", "command": "dotnet", "type": "process", "args": [ "build", "${workspaceFolder}"] } ```

7) To save as workspace go to File -> Save as Workspace.

## Usage

Function App 
To see an example of how an function can be invoked, please refer to FlowInvokedFunction.cs is the cs project that was provided in sample repo. That class holds the custom .NET code executed by an Azure Function. The Azure function trigger needed for the function is called WorkflowActionTrigger. All of the function headers authoring custom code will need to include the WorkflowActionTrigger in order to execute the code properly.
To make changes to author your own function, ensure that you have three things:
1) Function Header Name. This is the name of your function. 

2) WorkflowActionTrigger. This is the respective trigger for the custom code feature. This is necessary to add as a trigger in order to invoke your custom function.

3) Parameter value(s). The parameter values can be set to null if your function has no parameters.

Dev.csproj file contains a the already configured build steps to copy the required assemblies needed to invoke a custom function. In the dev.csproj, replace the value in LogicAppFolder with the name of your own folder that holds the logic app project. 

```bash
<LogicAppFolder>WorkflowLogicApp</LogicAppFolder>
```

STEPS: 

Logic App 

1) Workflow.json. This file is the JSON file that contains your logic app project. 

2 Host.json. In host.json a specific value needs to be enabled in order to execute the invoke function action for this feature. 
``` "extensions":{ "workflow": { "settings": { "Runtime.IsInvokeFunctionActionEnabled": "true" } } ```



STEPS: 
1) To call the invoke function action, right click on your workflow.json file and click open in designer.
2) In the designer look for "Invoke a function in this LogicApp", and add that action to your logic app workflow. 
3) In the action, replace FunctionName with the same name as your Azure function, and insert the parameters necessary for your function application. Once your logic app is created, click save. 
4) After that run Run-> Run without debugging (Ctrl + F5).
5) Right click on your workflow.json and open the overview to run the trigger for your logic app.
6) After the trigger has been ran you can open a run to see if the logic app run was sucessful and see the output of your custom code.

## Contributing

This project has adopted the Microsoft Open Source Code of Conduct. For more information see the Code of Conduct FAQ or contact opencode@microsoft.com with any additional questions or comments.
