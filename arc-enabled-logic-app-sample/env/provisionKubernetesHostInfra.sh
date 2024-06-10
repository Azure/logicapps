#!/bin/bash
set -ux

# create a compliant AKS cluster and a public static IP address

# create a resource group
az group create -n $RESOURCE_GROUP -l $LOCATION

# create AKS cluster
az deployment group create --name "${DEPLOYMENT_NAME}-aks" -g $RESOURCE_GROUP --template-file  aks.bicep  --parameters clusterName=$AKS_NAME

NODE_RG=$(az deployment group show  -g $RESOURCE_GROUP -n "${DEPLOYMENT_NAME}-aks" -o tsv --query properties.outputs.nodeResourceGroup.value)

#create static IP
az deployment group create -g $NODE_RG  --name "${DEPLOYMENT_NAME}-IP"  --template-file ipAddress.bicep --parameters staticIpName=$STATIC_IP_NAME

export STATIC_IP=$(az deployment group show  -g $NODE_RG  -n "${DEPLOYMENT_NAME}-IP" -o tsv --query properties.outputs.staticIp.value)

# get AKS credentials
az aks get-credentials -g $RESOURCE_GROUP -n $AKS_NAME --admin

# onboard the cluster to Arc
az connectedk8s connect -g $RESOURCE_GROUP -n $AKS_NAME

# get the Connected Cluster Id
export CONNECTED_CLUSTER_ID=$(az connectedk8s show -n $AKS_NAME -g $RESOURCE_GROUP --query id -o tsv)

# install the App Service extension on the Arc cluster
az k8s-extension create \
    -g $RESOURCE_GROUP \
    --name $EXTENSION_NAME \
    --cluster-type connectedClusters \
    -c $AKS_NAME \
    --extension-type 'Microsoft.Web.Appservice' \
    --release-train stable \
    --auto-upgrade-minor-version true \
    --scope cluster \
    --release-namespace $APP_SERVICE_NAMESPACE \
    --configuration-settings "Microsoft.CustomLocation.ServiceAccount=default" \
    --configuration-settings "appsNamespace=${APP_SERVICE_NAMESPACE}" \
    --configuration-settings "clusterName=${KUBE_ENV_NAME}" \
    --configuration-settings "loadBalancerIp=${STATIC_IP}" \
    --configuration-settings "buildService.storageClassName=default" \
    --configuration-settings "buildService.storageAccessMode=ReadWriteOnce" \
    --configuration-settings "customConfigMap=${APP_SERVICE_NAMESPACE}/kube-environment-config" \
    --configuration-settings "envoy.annotations.service.beta.kubernetes.io/azure-load-balancer-resource-group=${RESOURCE_GROUP}" \
    --configuration-settings "keda.enabled=true"

# extract an ID of the installed App Service extension
EXTENSION_ID=$(az k8s-extension show --cluster-type connectedClusters -c $AKS_NAME -g $RESOURCE_GROUP --name $EXTENSION_NAME --query id -o tsv)
# wait for the extension to fully install before proceeding.
az resource wait --ids $EXTENSION_ID --custom "properties.installState!='Pending'" --api-version "2020-07-01-preview"

# create a custom location in the region selected for the resource group that houses the resources
az customlocation create -g $RESOURCE_GROUP -n $CUSTOM_LOCATION_NAME --host-resource-id $CONNECTED_CLUSTER_ID --namespace $APP_SERVICE_NAMESPACE -c $EXTENSION_ID

# extract an ID of the created custom location
export CUSTOM_LOCATION_ID=$(az customlocation show -g $RESOURCE_GROUP -n $CUSTOM_LOCATION_NAME --query id -o tsv)

set +ux