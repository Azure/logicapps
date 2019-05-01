$copies = 1

$deploymentName = "recurrentLogicAppDeployment"

$resourceGroupName = "recurrentLogicAppsRGxyz16"

$ServiceBusConnConnectionString = "Endpoint=sb://{service-bus-namespace}.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey={SAS-key}"

$location = "eastus"

# Create a single resource group for all sets
New-AzResourceGroup -Name $resourceGroupName -Location $location

For($i = 0; $i -lt $copies; $i++) {
    $createRecurrenceJobLogicAppName = "CreateRecurrenceJob" + "_set" + $i
    $executeRecurrenceJobLogicAppName = "ExecuteRecurrenceJob" + "_set" + $i
    $rescheduleRecurrenceJobLogicAppName = "RescheduleRecurrenceJob" + "_set" + $i
    $ServiceBusConnName = "ServiceBusConn" + "_set" + $i + "_"

    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile "C:\Desktop\schedulesWithConn.json" -location $location -CreateRecurrenceJobLogicAppName $createRecurrenceJobLogicAppName -ExecuteRecurrenceJobLogicAppName $executeRecurrenceJobLogicAppName -RescheduleRecurrenceJobLogicAppName $rescheduleRecurrenceJobLogicAppName -ServiceBusConnName $ServiceBusConnName -ServiceBusConnConnectionString $ServiceBusConnConnectionString
}
# End of create a single resource group for all sets