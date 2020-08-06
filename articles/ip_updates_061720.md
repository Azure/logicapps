# Update Firewall Configurations That Filter Azure Logic Apps IP Addresses

## Background
On 6/17/2020, we emailed the subscription owners and administrators about upcoming IP address changes for Azure Logic Apps.

The e-mail is titled **Action required: Update firewall configurations that filter Azure Logic Apps IP addresses**. 

You will also find the same notification by searching Service history on Azure Service Health in Azure portal. The tracking ID is **D_9M-1T8**.

This article provides some more details on the changes.

## What's Changing

1.	The updated IP lists have already been published here: https://docs.microsoft.com/en-us/azure/logic-apps/logic-apps-limits-and-config#firewall-configuration-ip-addresses-and-service-tags.  The changes (aka added and removed IPs) will not take effect until 08/31/2020.
1.	The updated IP lists have no change on inbound IP addresses.
1.	The updated IP lists have no change on Logic Apps outbound IP addresses.
1.	The updated IP lists have these changes on Managed Connectors outbound IP addresses.

## Action Required
We suggest inventorying what connectors and connections you are using on what regions, then determine whether any of them are filtered by firewall configuration.

For any connection going through a firewall, please ask your firewall/network administrator or your business partner to update the filtering list before 08/31/2020.

If you are using Integration Service Enviornment, you will need to go through the same process because Logic Apps in ISE could be using the multi-tenant connectors.
