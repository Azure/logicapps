# Overview
This prototype was built on https://github.com/microsoft/Agents/tree/main/samples/dotnet/auto-signin. Teams integration leverages Azure Bot Service, which needs a messaging endpoint that implements the bot framework activity protocol. The code in this repository is an ASP.NET service that implements the protocol by proxying messages between Azure Bot Service and LA. Therefore this repository contains proxying business logic that will be simplified later.

# Setup steps

## Logic App
Create a standard LA with an agent loop. Use the default easy auth settings that create an app registration on your behalf. You can change the identity (e.g. allow any identity) as needed.
When the AAD app is created, ensure you add "https://token.botframework.com/.auth/web/redirect" to Web Redirect URIs.

Ensure EnableA2AClientTrackingIdToContextId is enabled in host.json or by default (depending on deployment timeline)

## Azure Bot Service
Create an Azure Bot resource in the portal. Allow it to create its AAD app for you. This app represents the bot identity. Note down BOT_CLIENT_ID, BOT_TENANT_ID, and create a BOT_SECRET for later.

Create a new OAuth connection setting:
- name: logicapp
- service provider: Azure Active Directory v2
- client id: the app ID created by LA Easy Auth setup
- client secret: for accessing the app ID mentioned above (create a new secret)
- token exchange URL: leave this blank
- tenant id: tenant id of above client id
- scopes: api://{{above client id}}/user_impersonation (you can copy this from the referenced AAD app "Expose an API" section which should be prefilled)

Save the OAuth connection. Open it again and click "test". This should let you log in and if successful, will give you a token.

## Bot backend
- Clone this repository.
- Open appsettings.json and fill in BOT_CLIENT_ID, BOT_TENANT_ID, BOT_SECRET
- Open the relevant LA workflow and click on the trigger. You should see an agent URL. Copy that into LOGICAPP_AGENT_URL
- Now run the project.
- Expose the local service using ngrok or devtunnel. For example: `.\devtunnel.exe host -p 3978 --allow-anonymous`
- Note the URL exposed by devtunnels and append the suffix `\api\messages` to form the full messaging endpoint
- Go to Azure Bot Service, configuration, and put in the full messaging endpoint there

Now you can "test in web chat" in Azure Bot Service - you should be able to interact with the agent. Ensure sign-in works and messages are flowing through

## Expose in teams
- Go to "channels" in the bot service and add Microsoft Teams. Default settings are OK.
- Open `manifest.json` in this repository. Update all {{placeholders}}
- Compress appManifest folder into a zip file
- Open Teams > apps > manage apps > upload a custom app
- Upload the zip file
- It should allow you to open the app
- You should then be able to chat with the app

## Deploying
- All messages are proxied through your local devtunnel for faster dev. This way you can change any business logic if needed.
- But you may want this in the cloud instead. For this, you can follow publishing from VS Studio instructions (there is a wizard) as this is just a ASP.NET app.
- Then ensure the messaging endpoint is changed in bot service to point to your web app.
- App settings can be changed in the web app as well (e.g. to switch target workflows)
