using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using Microsoft.SemanticKernel.Plugins.OpenApi;
using System.Net.Http.Headers;
using static System.Environment;
using Microsoft.Identity.Client;


var builder = Kernel.CreateBuilder();

// // Add logging  
// builder.Services.AddLogging(b => b.AddConsole().SetMinimumLevel(LogLevel.Error));

//Add Permission Filter
#pragma warning disable SKEXP0001
builder.Services.AddSingleton<IFunctionInvocationFilter, PermissionFilter>();



builder.Services.AddAzureOpenAIChatCompletion(
    deploymentName: "sk-demo-model",
    modelId: "gpt-4o",
    endpoint: "https://prompflowai.openai.azure.com/",
    apiKey: "6b2da012a7f94a4693f9065f87079e5e"
    );
var kernel = builder.Build();



string ClientId = "14e85732-1840-43c9-a03a-219a3cb21d59";
string Authority = $"https://login.microsoftonline.com/72f988bf-86f1-41af-91ab-2d7cd011db47";
string[] Scopes = new string[] { "api://14e85732-1840-43c9-a03a-219a3cb21d59/SkLogicApp" };

var app = PublicClientApplicationBuilder.Create(ClientId)
            .WithAuthority(Authority)
            .WithDefaultRedirectUri() // Uses http://localhost for a console app
            .Build();

AuthenticationResult authResult = null;
try
{
    authResult = await app.AcquireTokenInteractive(Scopes).ExecuteAsync();
}
catch (MsalException ex)
{
    Console.WriteLine("An error occurred acquiring the token: " + ex.Message);
}

//import Logic App as a function
#pragma warning disable SKEXP0040
#pragma warning disable SKEXP0042 // Type is for evaluation purposes only and is subject to change or removal in future updates. Suppress this diagnostic to proceed.
await kernel.ImportPluginFromOpenApiAsync(
        pluginName: "pstest",
        uri: new Uri("{https://{logic-app-name}.azurewebsites.net}/swagger.json"),
        executionParameters: new OpenApiFunctionExecutionParameters()
            {
                HttpClient = new HttpClient()
                {
                    DefaultRequestHeaders =
                    {
                        Authorization = new AuthenticationHeaderValue("Bearer", authResult.AccessToken)
                    }
                }


            }
    );
#pragma warning restore SKEXP0042 // Type is for evaluation purposes only and is subject to change or removal in future updates. Suppress this diagnostic to proceed.



// Enable planning
//tell OpenAI it is ok to import the function
var settings = new OpenAIPromptExecutionSettings(){ToolCallBehavior = ToolCallBehavior.AutoInvokeKernelFunctions};


//Get chat completion service
var chatService = kernel.GetRequiredService<IChatCompletionService>();

//Create chat history
ChatHistory chat = new();
ChatHistory chatMessages = new ChatHistory("""
    You are a friendly assistant who likes to follow the rules. You will complete required steps
    and request approval before taking any consequential actions. If the user doesn't provide
    enough information for you to complete a task, you will keep asking questions until you have
    enough information to complete the task.
    """);

while (true){
   Console.Write("Q:");

   chat.AddUserMessage(Console.ReadLine());

   //add the kernel and settings to the chat service
   var r = await chatService.GetChatMessageContentAsync(chat, settings, kernel);
   Console.WriteLine("A:" + r);
   chat.Add(r); // add response to chat history


}

#pragma warning disable SKEXP0001
class PermissionFilter : IFunctionInvocationFilter
{

    public async Task OnFunctionInvocationAsync(FunctionInvocationContext context, Func<FunctionInvocationContext, Task> next)
    {
        Console.WriteLine($"Allow {context.Function.Name} to be invoked? If so, answer with 'y'");

        if (Console.ReadLine() == "y")
        {
        // Perform some actions before function invocation
        await next(context);
        }
        else{
            throw new Exception("Function invocation not allowed");
        }


    }
}


     
