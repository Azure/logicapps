$subscription = Get-AzSubscription -SubscriptionName "SubscriptionName"

$cotnext = $subscription | Set-AzContext

$logicApps = Get-AzResource -ResourceType Microsoft.Logic/workflows -ResourceGroupName 'ResourceGroupName' -Name 'LogicAppsName'

Foreach ($la in $logicApps) {
    $runs = Get-AzLogicAppRunHistory -ResourceGroupName $la.ResourceGroupName -Name $la.name | where { $_.Status -eq 'Running' }

    Foreach($run in $runs) {
        Stop-AzLogicAppRun -ResourceGroupName $la.ResourceGroupName -Name $la.name -RunName $run.name 
    }
}
