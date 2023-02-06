# Logic Apps Custom Code Feature

Custom Code is a new Logic Apps feature in which users can author their own custom code through the usage of .NET Framework code from an Azure Logic Apps workflow.
This folder contains a sample project that utilizes this feature. The contents consist of a Logic App project (WorkflowLogicApp) and an Azure Function App (Function).  
## Installation

To run this sample, clone the repository to your local machine.

```bash
git clone https://github.com/Azure/logicapps.git
```
To pull the nuget package that contains the WorkflowActionTrigger attribute for your own project, include the phrase below in the csproj file of your project. The link to the myget package that stores this nuget package is listed here: [MyGet]( https://www.myget.org/feed/microsoft-workflowactiontrigger/package/nuget/Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger)


```bash
<PackageReference Include="Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger" Version="1.0.0" />
```
Please ensure you also have the Azure Logic Apps Standard and Azure Functions extensions for Visual Studio Code. This can be downloaded through the Extensions section in Visual Studio Code. For more information on how to install extensions for Visual Studio Code please check here: [EXTENSIONS](https://code.visualstudio.com/docs/editor/extension-marketplace).


# Workspace Setup
To setup the Logic Apps Custom Code feature in a new project, start by creating a Workspace. Due to the nature of this project where there are two distinct applications that need to be ran simultaneously, it is important to create a single VS Code workspace in order to utilize both applications. The steps for doing so are as follows:

1) Create a new folder for your workspace. 
2) Open this new folder in VS Code and open a terminal by clicking Terminal -> New Terminal (CTRL + SHIFT + 5) 
3) In the terminal create a solution: ``` dotnet new sln -n FunctionApp ```
4) Add the csproj file of your function application to this solution. ``` dotnet sln add src/dev/dev.csproj ```
5) Add the logic app project folder directly to your workspace by clicking File -> Add Folder To Workspace. 
6) Ensure that there is a build task for building the function application in task.json. The tasks.json for your Function application should be located in the location "\\..<yourfunctionfolder>\\.vscode\tasks.json"

```	{ "label": "build", "command": "dotnet", "type": "process", "args": [ "build", "${workspaceFolder}"] } ```

7) To save as workspace go to File -> Save as Workspace.

# Usage
The sections below will explain the process of how to author your own function app and logic app, as well as explain what the sample code provided contains in order for a user to create their own custom code instance. 

## Function App 
To see an example of how an function can be invoked, please refer to FlowInvokedFunction.cs is the .NET code sample that was provided in the sample repository. That class holds the custom .NET code executed by an Azure Function. The Azure function trigger needed for the function is called WorkflowActionTrigger. All of the functions authoring custom code will need to include the WorkflowActionTrigger in the function header in order to execute the code properly.
  
To make changes to author your own function, ensure that you have three things:
1) Function Name. This is the name of your function. 

![functionanme](https://user-images.githubusercontent.com/111014793/217034574-968087d3-d053-4cdb-98c4-3afa8341b1e9.png)


2) WorkflowActionTrigger. This is the respective trigger for the custom code feature. This is necessary to add as a trigger in order to invoke your custom function.

![wrok](https://user-images.githubusercontent.com/111014793/217034182-5734a894-603f-4bd7-9e68-4335df38b499.png)


3) Parameter value(s). The parameter values can be set to null if your function has no parameters.

![Screenshot_20230206_085009](https://user-images.githubusercontent.com/111014793/217033830-f0231893-6b33-47a3-a294-9c297b0b0d09.png)

For reference, the full screenshot of the code is posted below. 

![Screenshot 2023-02-06 091600](https://user-images.githubusercontent.com/111014793/217039346-7162f057-db44-4bce-b1fe-d0ffe4540ddb.png)


4) Dev.csproj file contains a the already configured build steps to copy the required assemblies needed to invoke a custom function. In the dev.csproj, replace the value in LogicAppFolder with the name of your own folder that holds the logic app project. 

```bash
<LogicAppFolder>WorkflowLogicApp</LogicAppFolder>
```

STEPS FOR AUTHORING A CUSTOM CODE FUNCTION: 

1) Add an Azure Function by clicking on the Workspace icon in the Azure tab. Click on the lighting symbol by Workspace to create an Azure Function in your workspace. 
  
![create function](https://user-images.githubusercontent.com/111014793/217051951-c1f39778-1070-48c8-b7db-dbff681b3adf.png)  

2) When the pop up appears, select a folder for your function, this would be the workspace in which you want to run both your Function and Logic App together. 
 
3) For the language please click 'C#'. For .NET runtime please click '.NET Framework'. 
  
4) For the template please click 'Skip for now' since we are authoring a custom Azure Function. 

5) Rename Program.cs to the name of your custom function code name.
  
6) Please check that your C# class file contains a namespace for your project, a public static class with the same name as your file, a function header, and the code that you wish to invoke. Please follow the sample project. Below is a screenshot of an example skeleton set up for your function. Your function class should follow a similar structure. 

![barebones](https://user-images.githubusercontent.com/111014793/217053377-37dfdf85-f566-4b0a-9f31-b44ca336d023.png)

7) Please copy the contents of dev.csproj to your personal project and replace the name of LogicAppFolder in the csproj to the name of your folder that contains your logic app.
  
8) If the WorkflowActionTrigger is not configured automatically, please click Terminal -> New Terminal and type ``` dotnet restore ```.

9) After restore, please run the build task configured for the function application. Click Run -> Run Task -> Build. 

## Logic App 

1) Workflow.json. This file is the JSON file that contains your logic app project. 

2) Host.json. In host.json a specific value needs to be enabled in order to execute the invoke function action for this feature. 
``` "extensions":{ "workflow": { "settings": { "Runtime.IsInvokeFunctionActionEnabled": "true" } }" ```


STEPS FOR AUTHORING A LOGIC APP WITH THE CUSTOM CODE ACTION: 
1) To call the invoke function action, right click on your workflow.json file and click open in designer.
![designer](https://user-images.githubusercontent.com/111014793/217036602-01f92e50-256f-4e3d-b27d-1f9e0808f035.png)

2) In the designer look for "Invoke a function in this LogicApp", and add that action to your logic app workflow. 
![invoke](https://user-images.githubusercontent.com/111014793/217037045-b6e550a3-0bee-4eef-8770-c30b9279bec8.png)

3) In the action, replace FunctionName with the same name as your Azure function, and insert the parameters necessary for your function application. Once your logic app is created, click save. ![Screenshot_20230206_090935](https://user-images.githubusercontent.com/111014793/217037991-23ad112e-d50f-4040-8d48-6eb10e508d53.png)

4) After that run Run-> Run without debugging (Ctrl + F5).

![run](https://user-images.githubusercontent.com/111014793/217038206-c254df23-f4ad-4e03-8800-4ad4cc1aa611.png)

5) Right click on your workflow.json and open the overview to run the trigger for your logic app.

![overview](https://user-images.githubusercontent.com/111014793/217038386-9cd5ce10-9f3b-4f64-b6ff-4a2d77228141.png)

6) Click on run trigger to run your trigger for your logic app. 
![runtri](https://user-images.githubusercontent.com/111014793/217038789-eaa3a736-e499-4e98-9935-91562d4ce6bf.png)

7) After the trigger has been ran you can open a run to see if the logic app run was successful and see the output of your custom code.

![sucessful](https://user-images.githubusercontent.com/111014793/217039132-f8828e74-4112-4ff3-afe7-2b2700a6b4fb.png)


![logicappsucessful](https://user-images.githubusercontent.com/111014793/217039149-200745f1-9b8d-4562-ad31-530ae7ed50ad.png)



## Contributing

This project has adopted the Microsoft Open Source Code of Conduct. For more information see the Code of Conduct FAQ or contact opencode@microsoft.com with any additional questions or comments.
