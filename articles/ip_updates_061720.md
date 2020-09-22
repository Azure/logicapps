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

### Added IPs for outbound managed connectors

| Region   |      IP addresses      |
|----------|:-------------:|
| Australia East | 13.70.78.224 - 13.70.78.255 |
| Australia Southeast | 13.77.55.160 - 13.77.55.191 |
| Brazil South | 191.233.207.160 - 191.233.207.191 |
| Canada Central | 13.71.175.160 - 13.71.175.191, 13.71.170.224 - 13.71.170.239 |
| Canada East | 40.69.111.0 - 40.69.111.31 |
| Central India | 20.43.123.0 - 20.43.123.31 |
| Central US | 40.77.68.110, 13.89.178.64 - 13.89.178.95 |
| East Asia | 104.214.164.0 - 104.214.164.31 |
| East US | 52.188.157.160, 40.71.15.160 - 40.71.15.191 |
| East US 2 | 40.65.220.25, 40.70.151.96 - 40.70.151.127 |
| France Central | 40.79.148.96 - 40.79.148.127 |
| France South | 40.79.180.224 - 40.79.180.255 |
| Japan East | 40.79.189.64 - 40.79.189.95 |
| Japan West | 40.80.180.64 - 40.80.180.95 |
| Korea Central | 20.44.29.64 - 20.44.29.95 |
| Korea South | 52.231.148.224 - 52.231.148.255 |
| North Central US | 52.162.111.192 - 52.162.111.223 |
| North Europe | 40.115.108.29, 13.69.231.192 - 13.69.231.223 |
| South Africa North | 40.127.2.94, 102.133.155.0 - 102.133.155.15, 102.133.253.0 - 102.133.253.31 |
| South Africa West | 102.133.75.194, 102.133.27.0 - 102.133.27.15, 102.37.64.0 - 102.37.64.31 |
| South Central US | 13.73.244.224 - 13.73.244.255 |
| Southeast Asia | 13.67.15.32 - 13.67.15.63 |
| UK South | 51.105.77.96 - 51.105.77.127 |
| UK West | 51.140.212.224 - 51.140.212.255 |
| US DoD Central | 52.127.61.192 - 52.127.61.223 |
| US Gov Arizona | 52.127.5.224 - 52.127.5.255 |
| US Gov Texas | 20.140.137.128 - 20.140.137.159 |
| West Central US | 13.71.199.192 - 13.71.199.223 |
| West Europe | 13.93.36.78, 13.69.71.192 - 13.69.71.223 |
| West India | 20.38.128.224 - 20.38.128.255 |
| West US | 13.86.223.32 - 13.86.223.63 |
| West US 2 | 13.66.164.219, 13.66.145.96 - 13.66.145.127 |

### Removed IPs from outbound managed connectors

|  Region |      IP addresses      |
|---------|------------------------|
| South Africa North | 13.65.86.57, 104.214.70.191 |
| South Africa West | 13.65.86.57, 104.214.70.191 |

## Action Required
We suggest inventorying what connectors and connections you are using on what regions, then determine whether any of them are filtered by firewall configuration.

For any connection going through a firewall, please ask your firewall/network administrator or your business partner to update the filtering list before 08/31/2020.

If you are using Integration Service Enviornment, you will need to go through the same process because Logic Apps in ISE could be using the multi-tenant connectors.
