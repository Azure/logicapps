# Logic Apps Public Preview Know Issues

This article documents the known issues of the Logic Apps's new containerized and rehostable runtime, Visual Studio code extension, and the improved designer.

1. Local development experience on MacOS is not yet supported.

1. Creaing the new Logic App resource is only supported via VS Code, not Azure portal. Once created via VS Code, workflows can be added and/or edited in Azure portal.

1. In rare cases, changes may not be reflected in Azure portal after update. Try clear the browse cache to resolve the issue.

1. Restarting the app is required after updating an Inline Code action.

1. Enterprise connectors, custom connectors, and or gateway-based connectors are not yet supported.

## See issues not listed?

You can open issues [here](https://github.com/Azure/logicapps/issues) on GitHub. 

## Provide feedback

You can submit feedbacks and comments using [this form](https://aka.ms/lafeedback).
