# Recurrence jobs

If you have a large number of recurrence jobs, instead of creating one Logic App per schedule, you can use this template to dramatically reduce the number of Logic Apps needed.

`deploy.ps1`

This script will find all the failed runs for Logic Apps under a subscription or resource group, and resubmit them.

`schedulesWithConn.json`

This ARM deployment template contains three Logic Apps, together they will be able to handle multiple schedules.

This script also shows off a few other tricks:

* Define multiple connections and randomly choose one at run time for higher throughput
* Deploy Logic Apps with circular references by deploy blank Logic App first then redeploy with actual reference
* Deploy multiple copies of the Logic Apps