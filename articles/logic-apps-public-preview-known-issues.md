# Logic Apps Public Preview Known Issues

This article documents the region availability and known issues for the new containerized and rehostable Logic Apps runtime, Visual Studio Code extension, and the improved designer.

## Available regions

Logic Apps Public Preview is available in all Azure regions.

## Issues

* Enterprise connectors, custom connectors, on-premises data gateway triggers, and some built-in B2B actions, such as Flat File, are currently unavailable. For more information, see [Overview for Azure Logic Apps Preview](https://docs.microsoft.com/azure/logic-apps/logic-apps-overview-preview#limited-unavailable-unsupported).

* For Visual Studio Code running on Linux or macOS, the [**Inline Code - Execute JavaScript Code** action (renamed **Inline Code Operations - Run in-line JavaScript**)](https://docs.microsoft.com/azure/logic-apps/logic-apps-add-run-inline-code) is currently unavailable.

  * To use this action on supported operating systems, make sure that you install [Azure Functions Core Tools 3.0.2931 or later](https://docs.microsoft.com/azure/azure-functions/functions-run-local.md#install-the-azure-functions-core-tools), which includes a version of the same runtime that powers the Azure Functions runtime that runs in Visual Studio Code.

  * After you make changes to this action action, you must restart your logic app.

* The built-in action, **Azure Functions - Choose an Azure function** (renamed as **Azure Function Operations - Call an Azure Function**), currently works only for functions that are created from the HTTP Trigger template. For more information, see [Overview for Azure Logic Apps Preview](https://docs.microsoft.com/azure/logic-apps/logic-apps-overview-preview#limited-unavailable-unsupported).

* Data persistence in the details pane for triggers and actions

  When you work with the Logic App Designer in Visual Studio Code, and you make changes to a trigger or action in the details pane on the **Settings**, **Run After**, or **Static Result** tab, make sure that you select **Done** and commit your changes before you switch tabs or change focus to the designer. Otherwise, your changes won't persist.

* Newly added workflows don't immediately appear in Visual Studio Code or the Azure portal.

  In rare cases, changes that you make to your logic app, such as adding a new workflow, either in your local project in Visual Studio Code or in your deployed **Logic App (Preview) resource** in the Azure portal, might not immediately appear because your logic app needs to restart. If those changes don't appear after some time, try refreshing the project pane by pressing Shift + F5 or by clearing your browser's cache by pressing Ctrl + Shift + Delete.

* **Parallel branches**: Currently, you can't add parallel branches through the new designer experience. However, you can still add these branches through the original designer experience and have them appear in the new designer

  1. At the bottom of the designer, disable the new experience by selecting the **New Canvas** control.
  
  2. Add the parallel branches to your workflow.
  
  3. Enable the new experience by selecting the **New Canvas** control again.

* **Zoom control**: This control is currently unavailable on the designer.

* Delays in disabling your workflow in the Azure portal

  If you select **Disable** on a logic app's **Workflows** pane or on a workflow on their **Overview** pane, you might experience a delay, usually around 30 seconds, before the **Status** changes from **Enabled** to **Disabled**. This delay happens because the function host, which powers the workflow, has to restart. However, the **Status** column shows the correct state after the function host finishes restarting.

* **Breakpoint debugging in Visual Studio Code**: Although you can add and use breakpoints inside the workflow.json file for a workflow, breakpoints are currently supported only for actions, not triggers. For more information, see [Create stateful and stateless workflows in Visual Studio Code](https://docs.microsoft.com/azure/logic-apps/create-stateful-stateless-workflows-visual-studio-code).

* Users can still access connections using old keys even after revocation of existing keys. The fix will be available in all regions by 12/15.

## Issues not listed here?

Open them [in this GitHub repo's issues section](https://github.com/Azure/logicapps/issues).

## Provide feedback

You can submit feedback and comments using [this form](https://aka.ms/lafeedback).
