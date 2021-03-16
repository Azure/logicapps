FROM mcr.microsoft.com/azure-functions/node:3.0

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
     AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
     FUNCTIONS_V2_COMPATIBILITY_MODE=true

COPY . /home/site/wwwroot

RUN cd /home/site/wwwroot