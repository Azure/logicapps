# Serverless Lab: Build a Social Dashboard

This lab will go over building a social dashboard using Azure Serverless technologies.  You can listen to any search term on Twitter and plot the sentiment, location, and key phrases of that tweet in real-time.

## Pre-requisites

All of the lab will take place within the Azure Portal.  So the only thing you need is an Azure account.

## Getting started with the Logic App

1. In the Azure Portal, click the **New** button, and under **Web + Mobile** select **Logic App**
1. Give your logic app any name, resource group, and region that you want.  Click **Create**
    * I recommend pinning the logic app to your dashboard for quick access later
1. Once the logic app has deployed, open it to view the designer
1. Click the **Blank Logic App** template to start from blank

### Adding the trigger to twitter

Now that we are in the logic app designer, we can set the trigger for this app.  In this case we want to listen to new tweets from Twitter.

1. Click the **Twitter** connector and the **When a new tweet is posted** trigger
1. Login with a twitter account to access the twitter search API
1. Configure the trigger for a search term to listen  
    ![Twitter trigger][1]
1. Add a **New Step** and **Add an action**, notice all of connectors to different services
1. Add the **Text Analytics** connector and **Detect Sentiment** operation to detect the sentimet of the tweet.  It can have any name you want
    * You can sign up for a key here - but note it does sometimes take 10 minutes for key to activate: [Azure Portal create subscription](https://ms.portal.azure.com/#create/Microsoft.CognitiveServices)
1. Select to add the **Tweet text** as the text to analyze
1. Add the **Key Phrases** operation as well, and grab from the **Tweet text**

At this point in our application we are listening to tweets, and getting the key phrases and sentiment of the tweet.  Now let's add in a simple Azure Function to return a plain list of Key Phrases.

## Adding an Azure Function

1. In a new tab, go to **New** and select **Compute** to create a Function App
1. Give it a name, resource group, etc. (Consumption plan is fine)
    * Again I recommend pinning to the dashboard
1. Click to add a new function, choose to make it a **Webhook + API**, and select **C#**
1. Once the new function app is created, replace the code with the following:


``` csharp
#r "Newtonsoft.Json"

using System;
using System.Net;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

public static async Task<HttpResponseMessage> Run(HttpRequestMessage req, TraceWriter log)
{
    log.Info("C# HTTP trigger function processed a request.");

    // Get the phrases array
    var phrases = await req.Content.ReadAsAsync<JArray>();
    // Join the array with a comma
    var joinedPhrases = string.Join(", ", phrases.ToObject<string[]>());
    // Return the response
    return req.CreateResponse(HttpStatusCode.OK, joinedPhrases);
}
```

You can even test it with the following Request body:

``` json
["Some", "Phrases", "Here"]
```

Which should produce `"Some, Phrases, Here"`

## Create a streaming dataset in Power BI to populate tweets

Follow the steps [here](https://powerbi.microsoft.com/en-us/documentation/powerbi-service-real-time-streaming/) to create a Streaming dataset in Power BI.  **Be sure to enable historic analysis** or else you will not see the columns in the designer.

Give the following columns:

|Name|Type|
|--|--|
|Tweet Text|String|
|Tweeted By|String|
|Score|Number|
|Key Phrases|String|
|Created at|DateTime|
|Location|String|

## Calling the Azure Function from the Logic App

Switching back over to the Logic App designer

1. Add a new step and select the Azure Functions connector
1. Select the function app just created.  The function will likely be named `HttpTriggerCSharp1`
1. Select to send in the **Key Phrases** list  
    ![Function config][2]  

    Last but not least, we need to add the outputs to a Power BI Dataset.  

1. Add a new step with the Power BI **Add rows to a dataset** operation
1. Sign in with your Power BI account
1. Select **My workspace** for a workspace, the dataset that corresponds with your account number, and the **Tweets** table
    * Notice that the designer has automatically prompted for the columns of this table
1. Fill out the connector like the following picture.  Note for key phrases we are using the output of our Azure Function  
    ![Power BI Config][3]

That's it - now we can save it and open in Power BI.

## Viewing the results

Go to https://app.powerbi.com and login with the same username and password as you did for the Power BI connector.  Find your dashboard and see the tweets as they come in.

<!-- Image references -->
[1]: ./images/twitterConfig.png
[2]: ./images/functionConfig.png
[3]: ./images/powerbiConfig.png