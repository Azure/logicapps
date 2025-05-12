using Microsoft.Azure.WebJobs.Extensions.DurableTask;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.DurableTask;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Microsoft.Azure.Workflows.ServiceProviders.FileSystem.Entities;
using Microsoft.Azure.Workflows.WebJobs.Extensions.Run;
using Microsoft.Azure.Workflows.Data.Entities;
using Newtonsoft.Json.Linq;
using Microsoft.AspNetCore.Mvc;
using System.Net;
using System.Threading.Tasks;
using System.Net.Http;
using System.Net.Http.Json;
using System.Collections.Generic;
using System.Linq;

using LogicApps.Connectors.ServiceProviders.Openai;
using LogicApps.Connectors.ServiceProviders.Azureaisearch;
using LogicApps.Connectors.Managed.Outlook;

namespace Company.Function.ServiceProviderSDKs
{
    public static class WorkflowOrchestrator
    {
        [FunctionName("RecommendCoffeeOrchestrator")]
        public static async Task<string> RunOrchestrator(
            [OrchestrationTrigger] IDurableOrchestrationContext context, ILogger log)
        {

            var triggerInput = context.GetInput<WhenAHTTPRequestIsReceivedInput>();
            //log.LogInformation("Starting Recommend coffee orchestrator.");

            List<string> CoffeeArray = new();
            foreach (ItemsItemType forEachElement in triggerInput.Items)
            {
                string composeResult = forEachElement.ProductName;
                CoffeeArray.Add(composeResult);
            }
            //log.LogInformation("CoffeeArray json : {result}", JsonSerializer.Serialize(CoffeeArray));
            string composeProductListResult = string.Join(',', CoffeeArray);

            var getAnEmbeddingInput = new GetSingleEmbeddingInput
            { 
                DeploymentId = "text-embeddings", 
                Input = JsonSerializer.Serialize(CoffeeArray)
            };

            var embeddingResponse = await context.GetSingleEmbeddingAsync(
                connectionId: "openai",
                input: getAnEmbeddingInput);

            //log.LogInformation("Embedding response : {result}", JsonSerializer.Serialize(embeddingResponse));

            var searchVectorsInput = new VectorSearchInput 
            { 
                IndexName = "fourthcoffeeorders", 
                KNearestNeighbors = 4, 
                SearchVector = new VectorSearchInputSearchVectorType
                { 
                    FieldName = "embeddings", 
                    Vector = embeddingResponse.Embedding
                } 
            };

            var searchVectorsHttpOutput = await context.VectorSearchAsync("azureaisearch", searchVectorsInput);
            // log.LogInformation("Vector search output : {result}", searchVectorsHttpOutputStr);

            log.LogInformation("Vector search output : {result}", searchVectorsHttpOutput.First()["content"].ToString());

            var chatCompletionInput = new GetChatCompletionsInput
            {
                DeploymentId = "gpt-4o",
                Temperature = 1,
                Messages = [
                    new GetChatCompletionsInputMessagesTypeItem
                    {
                        Role = "System",
                        Content = "You are an AI assistant with deep expertise in recommending coffee based on historical sales data. Focus on identifying orders where customers have purchased the same coffee as in the incoming order, and recommend additional coffee types that were frequently bought together. Prioritize recommendations from orders that include multiple products, ensuring that your suggestions are based on actual purchasing patterns. Be specific in recommending complementary coffee types that align with the customer's preferences." + 
                        searchVectorsHttpOutput.First()["content"].ToString() + ". Please ensure that the following list of coffees are not included in the recommendations as they have already interested in them " + composeProductListResult.ToString() + ". But, please only include recommendations based upon previous Fourth Coffee purchases. There should be 3 recommendations at most. Return a json structure that returns a list of products only so that another system can read the response. call the list productreccommendations"
                    },
                    new GetChatCompletionsInputMessagesTypeItem
                    {
                        Role = "User",
                        Content = "[\"Light Roast\"]"
                    }
                ]
            };

            var openAIResult = await context.GetChatCompletionsAsync(
                connectionId: "openai",
                input: chatCompletionInput);


            var msgResponse = openAIResult.Content.ToString().Replace("```json", "").Replace("```", "").Trim();
            if (msgResponse.StartsWith("{"))
            {
            }
            else
            {
                msgResponse = "{" + openAIResult.Content.ToString().Replace("```json", "").Replace("```", "").ToString() + "}";
            }

            var message = new ClientSendHtmlMessage
            {
                To = "koustephen@microsoft.com",
                Subject = "Hello from Codeful",
                Body = "Chat response: " + msgResponse
            };

            await context.SendEmailV2Async("office365", message);

            log.LogInformation("openAI result : {result}", msgResponse);

            return msgResponse;
        }

        [FunctionName("RecommendCoffee")]
        public static async Task<HttpResponseMessage> HttpStart(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequestMessage req,
            [DurableClient] IDurableOrchestrationClient starter,
            ILogger log)
        {
            /*
            var content = await req.Content.ReadAsStringAsync();
            using var requestStream = await req.Content.ReadAsStreamAsync();
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            };
            var workflowInput = await JsonSerializer.DeserializeAsync<WhenAHTTPRequestIsReceivedInput>(requestStream, options);
            */
            var workflowInput = new WhenAHTTPRequestIsReceivedInput
            {
                OrderID = "order1235",
                Customer = new CustomerType 
                {
                    Name = "Stephen Kou",
                    Address = "1 Main street",
                    Contact = "4083180914"
                },
                Items = [
                    new ItemsItemType { ProductName = "Sprite", Qty = 2, Price = 3.33 },
                    new ItemsItemType { ProductName = "Coca-Cola", Qty = 2, Price = 3.33 }
                ],
                Total = 12.33M
            };

            log.LogInformation("Workflow Input = '{workflowInput}'.", JsonSerializer.Serialize(workflowInput));

            string instanceId = await starter.StartNewAsync("RecommendCoffeeOrchestrator", workflowInput);

            log.LogInformation("Started orchestration with ID = '{instanceId}'.", instanceId);

            DurableOrchestrationStatus status;
            do
            {
                status = await starter.GetStatusAsync(instanceId);
                await Task.Delay(1000); // Wait for 1 second before checking the status again
            } while (status.RuntimeStatus == OrchestrationRuntimeStatus.Running || 
                    status.RuntimeStatus == OrchestrationRuntimeStatus.Pending);

            if (status.RuntimeStatus == OrchestrationRuntimeStatus.Completed)
            {
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(status.Output.ToString(), System.Text.Encoding.UTF8, "application/json")
                };
            }

            return new HttpResponseMessage(HttpStatusCode.InternalServerError)
            {
                Content = new StringContent("Orchestration did not complete successfully.")
            };
        }
    }

    public class CustomerType
    {
        public string Name { get; set; }
        public string Address { get; set; }
        public string Contact { get; set; }
    }

    public class ItemsItemType
    {
        public string ProductName { get; set; }
        public int Qty { get; set; }
        public double Price { get; set; }
    }

    public class WhenAHTTPRequestIsReceivedInput
    {
        public string OrderID { get; set; }
        public CustomerType Customer { get; set; }
        public ItemsItemType[] Items { get; set; }
        public decimal Total { get; set; }
    }

}
 