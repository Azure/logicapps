export BASENAME="{basename}"
export LOCATION="eastus"
export RESOURCE_GROUP=$BASENAME
export APP_NAME=$BASENAME
export DEPLOYMENT_NAME="${BASENAME}-Deployment"
export STORAGE_ACCOUNT=$(echo $BASENAME | tr -dc '[:alnum:]\n\r' | tr '[:upper:]' '[:lower:]')
export STORAGE_NAME_VALID=$(az storage account check-name -n ${STORAGE_ACCOUNT} --query "nameAvailable" -o tsv)
[[ $STORAGE_NAME_VALID == false ]] && echo "Storage name is not valid">&2
export SP_NAME="${BASENAME}-sp"
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AKS_NAME="${BASENAME}-aks"
export STATIC_IP_NAME="${BASENAME}-ip"
export EXTENSION_NAME="${BASENAME}-appsvc-ext"
export APP_SERVICE_NAMESPACE="appservice-ns"
export KUBE_ENV_NAME="${BASENAME}-kube"
export CUSTOM_LOCATION_NAME="${BASENAME}-location"
export APP_SERVICE_PLAN="${BASENAME}-appservice-plan"
export KUBE_ENVIRONMENT_NAME="${BASENAME}-kube-appservice"

