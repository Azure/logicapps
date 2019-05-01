# Migrate Azure Scheduler jobs to Logic Apps

`run-once-handler.json`

A Logic App definition that will be responsible for all run-once schedules.

`scheduler-migration.ps1`

This script will find all the failed runs for Logic Apps under a subscription or resource group, and resubmit them.