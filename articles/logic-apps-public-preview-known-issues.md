# Logic Apps Public Preview Known Issues

This article documents the region availability and known issues for the new containerized and rehostable Logic Apps runtime, Visual Studio Code extension, and the improved designer.

## Available regions

Logic Apps public preview is currently available in the following Azure regions.

* Central US EUAP
* East US EUAP
* West Central US
* West US 2
* Central US
* Japan West
* Brazil South
* Central India
* South Africa West

## Issues

* Local development experience on macOS is not yet supported.

* Creating the new **Logic App (Preview)** resource is only supported in Visual Studio Code, not the Azure portal. After you create this new resource in Visual Studio Code and deploy to Azure, you can add or edit workflows through the Azure portal.

* Cloud connectors are supported in Logic Apps VS Code extension 0.0.3 or above, and in West Central US region. More region support coming soon.

* Enterprise connectors, custom connectors, and on-premises data gateway connectors are not yet supported.

* The [**Inline Code** action](https://docs.microsoft.com/azure/logic-apps/logic-apps-add-run-inline-code), which you can use for running JavaScript code, currently isn't supported on Linux operating systems or on the Azure Functions runtime version 2x.

  To use this action on a non-Linux OS, make sure that you install [Azure Functions Core Tools 3.0.14492](https://docs.microsoft.com/azure/azure-functions/functions-run-local.md#install-the-azure-functions-core-tools), which includes a version of the same runtime that powers the Azure Functions runtime that runs in Visual Studio Code.

* After you make changes to an Inline Code action, you must restart your logic app.

* Data persistence in the details pane for triggers and actions

  When you work with the Logic App Designer in Visual Studio Code, and you make changes to a trigger or action in the details pane on the **Settings**, **Run After**, or **Static Result** tab, make sure that you select **Done** and commit your changes before you switch tabs or change focus to the designer. Otherwise, your changes won't persist.

* Newly added workflows don't immediately appear in Visual Studio Code or the Azure portal.

  In rare cases, changes that you make to your logic app, such as adding a new workflow, either in your local project in Visual Studio Code or in your deployed **Logic App (Preview) resource** in the Azure portal, might not immediately appear because your logic app needs to restart. If those changes don't appear after some time, try refreshing the project pane by pressing Shift + F5 or by clearing your browser's cache by pressing Ctrl + Shift + Delete.

* Delays in disabling your workflow in the Azure portal

  If you select **Disable** on a logic app's **Workflows** pane or on a workflow on their **Overview** pane, you might experience a delay, usually around 30 seconds, before the **Status** changes from **Enabled** to **Disabled**. This delay happens because the function host, which powers the workflow, has to restart. However, the **Status** column shows the correct state after the function host finishes restarting.

* Zoom levels and off-screen content in Visual Studio Code

  No scrollbar appears when you zoom in or zoom out in Visual Studio Code, which prevents you from viewing content that appears off the screen.

  * To restore the original view, reset the zoom level with either option:

    * Press **Ctrl** + **NumPad0**.

    * From the **View** menu, select **Appearance** **>** **Reset Zoom**.

  * To change the zoom level only on the Logic App Designer canvas, use the designer's zoom controls (**+** **100%** **-**) at the bottom of the canvas.

## Issues not listed here?

Open them [in this GitHub repo's issues section](https://github.com/Azure/logicapps/issues).

## Provide feedback

You can submit feedback and comments using [this form](https://aka.ms/lafeedback).
