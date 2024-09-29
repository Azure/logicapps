# Use these cmdlets to retrieve outputs from prior steps
# oldActionOutput = Get-ActionOutput -ActionName <name of old action>
# oldTriggerOutput = Get-TriggerOutput
Connect-AzAccount -Identity

# Define the parameters for the VM
$resourceGroupName = "anand-filesystem"
$vmName = "anand-file-server"

# Start the VM
Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName

# Prepare the custom response
$customResponse = [PSCustomObject]@{
    Message = "VM '$vmName' started successfully in resource group '$resourceGroupName'."
}

# Use Write-Host/ Write-Output/Write-Debug to log messages to application insights
# Write-Host/Write-Output/Write-Debug and 'returns' will not return an output to the workflow
# Write-Host "Sending to application insight logs"

# Use Push-WorkflowOutput to push outputs forward to subsequent actions
Push-WorkflowOutput -Output $customResponse
