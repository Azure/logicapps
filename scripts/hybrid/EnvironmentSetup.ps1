
param (
    	[string]$LOCATION,
    	[string]$GROUP_NAME,
   	[string]$SUBSCRIPTION,
	[string]$KUBE_CLUSTER_NAME,
	[string]$LOGANALYTICS_WORKSPACE_NAME
)

$EXTENSION_NAME_ACA="logicapps-aca-extension"
$NAMESPACE="logicapps-aca-ns"
$CONNECTED_ENVIRONMENT_NAME="connected-environment-"+$KUBE_CLUSTER_NAME
$CUSTOM_LOCATION_NAME="custom-location-"+$KUBE_CLUSTER_NAME

#Change the below value, if you would like to provide different name for your connected cluster
$CONNECTED_CLUSTER_NAME= $KUBE_CLUSTER_NAME

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $User = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $User).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw "Please run this script as an administrator"
}

function Write-ColorOutput($ForegroundColor)
{
    Write-Output ""
    # save the current color
    $fc = $host.UI.RawUI.ForegroundColor

    # set the new color
    $host.UI.RawUI.ForegroundColor = $ForegroundColor

    # output
    if ($args) {
        Write-Output $args
    }
    else {
        $input | Write-Output
    }

    # restore the original color
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput green ("Preparing to login to your Azure account")

# Log into Azure
az login

# Set Azure subscription
Write-ColorOutput green ("using the subscription '$SUBSCRIPTION'.")
az account set --subscription $SUBSCRIPTION

#Write-ColorOutput green ("creating or using the resource group '$GROUP_NAME'.")
#az group create --name $GROUP_NAME --location $LOCATION

# installing kubectl
Write-ColorOutput green ("installing kubectl")
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco install kubernetes-cli -y

 

Write-ColorOutput green ("Getting the AKS credentials for kubectl access")
az aks get-credentials --resource-group $GROUP_NAME --name $KUBE_CLUSTER_NAME --admin

Write-ColorOutput green ("Merging the kubeconfig")
kubectl get ns

# Install helm
Write-ColorOutput green ("Installing helm.")
choco install kubernetes-helm

# Install SMB driver
Write-ColorOutput green ("Installing SMB CSI driver on the cluster.")
helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts
helm install csi-driver-smb csi-driver-smb/csi-driver-smb --namespace kube-system --version v1.15.0

# Install Azurefile driver
#Write-ColorOutput green ("Installing Azurefile CSI driver on the cluster.")
#helm repo add azurefile-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/charts
#helm install azurefile-csi-driver azurefile-csi-driver/azurefile-csi-driver --namespace kube-system --version v1.30.2

# add required cli extensions
Write-ColorOutput green ("adding az extension connectedk8s")
az extension add --name connectedk8s  --upgrade --yes

Write-ColorOutput green ("adding az extension k8s-extension")
az extension add --name k8s-extension --upgrade --yes

Write-ColorOutput green ("adding az extension customlocation")
az extension add --name customlocation --upgrade --yes

Write-ColorOutput green ("adding az extension containerapp")
az extension add --name containerapp --upgrade --yes

# register required providers

Write-ColorOutput green ("registering namespace Microsoft.Kubernetes")
az provider register --namespace Microsoft.Kubernetes --wait

Write-ColorOutput green ("registering namespace Microsoft.ExtendedLocation")
az provider register --namespace Microsoft.ExtendedLocation --wait

Write-ColorOutput green ("registering namespace Microsoft.KubernetesConfiguration")
az provider register --namespace Microsoft.KubernetesConfiguration --wait

Write-ColorOutput green ("registering namespace Microsoft.App")
az provider register --namespace Microsoft.App --wait

Write-ColorOutput green ("registering namespace Microsoft.OperationalInsights")
az provider register --namespace Microsoft.OperationalInsights --wait


# This script creates an Azure Arc resource to connect a Kubernetes cluster to Azure
# Documentation: https://aka.ms/AzureArcK8sDocs

# Create connected cluster
Write-ColorOutput green ("Creating or using connected cluster '$CONNECTED_CLUSTER_NAME'.")
az connectedk8s connect --name $CONNECTED_CLUSTER_NAME --resource-group $GROUP_NAME --location $LOCATION


# create log ananlytics workspace
Write-ColorOutput green ("Creating or using log analytics workspace '$LOGANALYTICS_WORKSPACE_NAME'.")
az monitor log-analytics workspace create `
    --resource-group $GROUP_NAME `
    --workspace-name $LOGANALYTICS_WORKSPACE_NAME
 
$LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show `
    --resource-group $GROUP_NAME `
    --workspace-name $LOGANALYTICS_WORKSPACE_NAME `
    --query customerId `
    --output tsv)
$LOG_ANALYTICS_WORKSPACE_ID_ENC=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($LOG_ANALYTICS_WORKSPACE_ID))# Needed for the next step
$LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys `
    --resource-group $GROUP_NAME `
    --workspace-name $LOGANALYTICS_WORKSPACE_NAME `
    --query primarySharedKey `
    --output tsv)
$LOG_ANALYTICS_KEY_ENC=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($LOG_ANALYTICS_KEY))


# install ACA extension
Write-ColorOutput green ("Start installing ACA extension under namespace '$NAMESPACE'.")
az k8s-extension create `
    --resource-group $GROUP_NAME `
    --name $EXTENSION_NAME_ACA `
    --cluster-type connectedClusters `
    --cluster-name $CONNECTED_CLUSTER_NAME `
    --extension-type 'Microsoft.App.Environment' `
    --release-train stable `
    --auto-upgrade-minor-version true `
    --scope cluster `
    --release-namespace $NAMESPACE `
    --configuration-settings "Microsoft.CustomLocation.ServiceAccount=default" `
    --configuration-settings "appsNamespace=${NAMESPACE}" `
    --configuration-settings "clusterName=${CONNECTED_ENVIRONMENT_NAME}" `
    --configuration-settings "keda.enabled=true" `
    --configuration-settings "keda.logicAppsScaler.enabled=true" `
    --configuration-settings "keda.logicAppsScaler.replicaCount=1" `
    --configuration-settings "containerAppController.api.functionsServerEnabled=true" `
    --configuration-settings "functionsProxyApiConfig.enabled=true" `
    --configuration-settings "envoy.annotations.service.beta.kubernetes.io/azure-load-balancer-resource-group=${GROUP_NAME}" `
    --configuration-settings "logProcessor.appLogs.destination=log-analytics" `
    --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.customerId=${LOG_ANALYTICS_WORKSPACE_ID_ENC}" `
    --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.sharedKey=${LOG_ANALYTICS_KEY_ENC}" `
    --configuration-settings "logProcessor.appLogs.destination=log-analytics"



$EXTENSION_ID_ACA=$(az k8s-extension show `
    --cluster-type connectedClusters `
    --cluster-name $CONNECTED_CLUSTER_NAME `
    --resource-group $GROUP_NAME `
    --name $EXTENSION_NAME_ACA `
    --query id `
    --output tsv) 

# Create Custom location
$CUSTOM_LOCATION_NAME="custom-location-"+$GROUP_NAME
$CONNECTED_CLUSTER_ID=$(az connectedk8s show --resource-group $GROUP_NAME --name $CONNECTED_CLUSTER_NAME --query id --output tsv)

Write-ColorOutput green ("Creating custom location '$CUSTOM_LOCATION_NAME'.")
az customlocation create `
    --resource-group $GROUP_NAME `
    --name $CUSTOM_LOCATION_NAME `
    --host-resource-id $CONNECTED_CLUSTER_ID `
    --namespace $NAMESPACE `
    --cluster-extension-ids $EXTENSION_ID_ACA `
    --location $LOCATION

az customlocation show --resource-group $GROUP_NAME --name $CUSTOM_LOCATION_NAME

$CUSTOM_LOCATION_ID=$(az customlocation show `
    --resource-group $GROUP_NAME `
    --name $CUSTOM_LOCATION_NAME `
    --query id `
    --output tsv)
 
# create connected environment
Write-ColorOutput green ("Creating connected environment '$CONNECTED_ENVIRONMENT_NAME'.")
az containerapp connected-env create `
    --resource-group $GROUP_NAME `
    --name $CONNECTED_ENVIRONMENT_NAME `
    --custom-location $CUSTOM_LOCATION_ID `
    --location $LOCATION
 
