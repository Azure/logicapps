#!/bin/bash
set -ux

echo 'Create Service Principal...'

# create service principal
export SP_INFO=$(az ad sp create-for-rbac --skip-assignment -n $SP_NAME)
export CLIENT_ID=$(echo $SP_INFO | jq .appId  -r)
export OBJECT_ID=$(az ad app show --id $CLIENT_ID --query 'id' -o tsv)
export CLIENT_SECRET=$(echo $SP_INFO | jq .password  -r)
export TENANT_ID=$(echo $SP_INFO | jq .tenant  -r)

echo 'Deploying resources logic app hosting resources...'

# az bicep build --file main.bicep
# # add the 'kind=v2' to our tablestorage connector; only way to do this right now
# sed -i 's/"name": "tablestorage",/"name": "tablestorage","kind":"V2",/g' main.json

az deployment group create \
  --name $DEPLOYMENT_NAME-logicapp \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters appName=$APP_NAME \
    storageAccountName=$STORAGE_ACCOUNT \
    spClientSecret=$CLIENT_SECRET \
    spTenantId=$TENANT_ID \
    spObjectId=$OBJECT_ID \
    spClientId=$CLIENT_ID \
    customLocationId=$CUSTOM_LOCATION_ID \
    appServicePlanName=$APP_SERVICE_PLAN \
    kubeEnvironmentName=$KUBE_ENVIRONMENT_NAME \
    appServiceIP=$STATIC_IP

echo 'Deploying Logic App code...'
pushd ../src
func azure functionapp publish $APP_NAME --node
popd

az storage entity insert --account-name $STORAGE_ACCOUNT --if-exists replace -t ratings -e \
    PartitionKey=3 \
    RowKey=5 \
    createDate=6/28/2021 \
    productId=3 \
    productId@odata.type=Edm.Int32 \
    publishDate=00/00/0000 \
    publishDate@odata.type=Edm.String \
    rating=1 \
    rating@odata.type=Edm.Int32 \
    ratingId=5 \
    ratingId@odata.type=Edm.Int32 \
    userName="Frank Jones" \
    userNotes="Did not enjoy this!"

echo "Logic App deployed to: https://ms.portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$APP_NAME/appServices"
echo "Storage account available at: https://ms.portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT/storageexplorer"
echo 'Done!'

set +ux