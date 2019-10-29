# Max number of pages to follow when retriving runs
# Each page contains up to 30 runs
$maxPage = 10

# Logic Apps to cancel
$subscriptionName = 'Subscription Name'
$resourceGroup = 'Resource Group Name'
$logicAppsName = 'Logic Apps Name'


#####

$subscription = Get-AzSubscription -SubscriptionName $subscriptionName

$cotnext = $subscription | Set-AzContext

# Get token from context for use when making REST call to run API
$tokens = $cotnext.TokenCache.ReadItems() | where { $_.TenantId -eq $cotnext.Subscription.TenantId } | Sort-Object -Property ExpiresOn -Descending

$token = $tokens[0].AccessToken

$logicApps = Get-AzResource -ResourceType Microsoft.Logic/workflows -ResourceGroupName $resourceGroup -Name $logicAppsName

Foreach ($la in $logicApps) {
    # Get-AzLogicAppRunHistory does not follow nextLink when retriving runs
    # https://github.com/Azure/azure-powershell/issues/9141
    # $runs = Get-AzLogicAppRunHistory -ResourceGroupName $la.ResourceGroupName -Name $la.name | where { $_.Status -eq 'Running' }

    $headers = @{
        'Authorization' = 'Bearer ' + $token
    }

    # GET https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Logic/workflows/{workflowName}/runs?api-version=2016-06-01&$top={$top}&$filter={$filter}
    $nextLink = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Logic/workflows/{2}/runs?api-version=2016-06-01&$filter=status eq ''Running''' -f $subscription.Id, $la.ResourceGroupName, $la.Name
    $runs = @()
    $page = 0

    Do {
        $data = Invoke-RestMethod -Method 'GET' -Uri $nextLink -Headers $headers

        $runs += $data.value
        $nextLink = if ($data.nextLink) { $data.nextLink } else { '' }

        $page++
    } Until ($nextLink -eq "" -or $page -ge $maxPage)


    Foreach($run in $runs) {
        Stop-AzLogicAppRun -ResourceGroupName $la.ResourceGroupName -Name $la.name -RunName $run.name -Force
    }
}