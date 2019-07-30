Login-AzureRmAccount
Get-AzureRmSubscription
Select-AzureRmSubscription -SubscriptionId {subscriptionId}

$runOnceHandlerCallbackUrl = Get-AzureRmLogicAppTriggerCallbackUrl -Name 'RunOnceHandler' -ResourceGroupName 'DeliRG' -TriggerName 'manual'

$nextDaylightSavingEnd = Get-Date -Date '2018-11-04'
$nextDaylightSavingStart = Get-Date -Date '2019-03-10'

<#
Get all the Scheduler Job Collections, then all the jobs within each job collection.
#>
$jobCollections = Get-AzureRmSchedulerJobCollection

$jobs = @()

Foreach ($jobCollection in $jobCollections) {
    $jobs += Get-AzureRmSchedulerJob -ResourceGroupName $jobCollection.ResourceGroupName -JobCollectionName $jobCollection.JobCollectionName
}

<#
Iterate over all run-once jobs and create corresponding Logic App runs
Scheduler jobs stores time in UTC w/o timezone information, so sourceTimeZone will be hardcoded to UTC
#>
Foreach ($job in $jobs) {
    If ($job.EndSchedule -eq 'Run once') {
        $newTimestamp = $job.StartTime

        <#
        Assume all jobs are in DST zones, therefore shifting back one hour
        It also only checks for the next two DST switches
        #>
        If ($job.StartTime -gt $nextDaylightSavingEnd -and $job.StartTime -lt $nextDaylightSavingStart) {
            $newTimestamp = $job.StartTime.AddHours(-1)
        }

        $payload = @{
            timestamp = $newTimestamp.ToString()
            sourceTimeZone = 'UTC'
            queue = $job.JobAction.ServiceBusQueueName
            content = $job.JobAction.ServiceBusMessage} | ConvertTo-Json

        Invoke-RestMethod -Method Post -Uri $runOnceHandlerCallbackUrl.Value -ContentType 'application/json' -Body $payload
    } Else {
        #ToDo
    }
}
