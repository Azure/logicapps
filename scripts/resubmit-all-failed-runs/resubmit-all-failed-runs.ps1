$startDateTime = Get-Date -Date '11/21/2018 5:00:00 PM'

$endDateTime = Get-Date -Date '11/21/2018 6:00:00 PM'

$subscription = Get-AzSubscription -SubscriptionName "Name of the subscription"

$cotnext = $subscription | Set-AzContext

$tokens = $cotnext.TokenCache.ReadItems() | where { $_.TenantId -eq $cotnext.Subscription.TenantId } | Sort-Object -Property ExpiresOn -Descending

$token = $tokens[0].AccessToken

$logicApps = Get-AzResource -ResourceType Microsoft.Logic/workflows <# | where { $_.ResourceGroupName -eq 'LoremIpsum'} #>

Foreach ($la in $logicApps) {
    $runs = Get-AzLogicAppRunHistory -ResourceGroupName $la.ResourceGroupName -Name $la.name | where { $_.Status -eq 'Failed' } | where { $_.StartTime -gt $startDateTime -and $_.StartTime -lt $endDateTime }

    $headers = @{
        'Authorization' = 'Bearer ' + $token
    }

    Foreach($run in $runs) {
        $uri = 'https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Logic/workflows/{2}/triggers/{3}/histories/{4}/resubmit?api-version=2016-06-01' -f $subscription.Id, $la.ResourceGroupName, $la.Name, $run.Trigger.Name, $run.Name

        Invoke-RestMethod -Method 'POST' -Uri $uri -Headers $headers
    }
}