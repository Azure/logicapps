// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

namespace TestCases
{
    using System.Net.Http;
    using System.Net;
    using Microsoft.VisualStudio.TestTools.UnitTesting;
    using Newtonsoft.Json.Linq;
    using System.IO;
    using System.Linq;
    using TestFramework;

    /// <summary>
    /// The test cases
    /// </summary>
    [TestClass]
    public class TestCases
    {
        /// <summary>
        /// Simple request-response workflow test.
        /// </summary>
        [TestMethod]
        public void RequestResponse()
        {
            var workflowName = "requestresponseworkflow";
            var workflowDefinition = File.ReadAllText($"TestFiles\\{workflowName}.json");

            using (new WorkflowTestHost(new WorkflowTestInput[] { new WorkflowTestInput(workflowName, workflowDefinition) }))
            using (var client = new HttpClient())
            {
                // Get workflow callback URL.
                var response = client.PostAsync(TestEnvironment.GetTriggerCallbackRequestUri(flowName: workflowName, triggerName: "manual"), null).Result;
                Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

                // Run the workflow.
                response = client.PostAsync(response.Content.ReadAsAsync<CallbackUrlDefinition>().Result.Value, null).Result;
                Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

                // Check workflow response.
                Assert.AreEqual("Hello from Logic Apps!", response.Content.ReadAsStringAsync().Result);

                // Check workflow run status.
                response = client.GetAsync(TestEnvironment.GetRunsRequestUriWithManagementHost(flowName: workflowName)).Result;
                var responseContent = response.Content.ReadAsAsync<JToken>().Result;
                Assert.AreEqual("Succeeded", responseContent["value"][0]["properties"]["status"].ToString());
                var runId = responseContent["value"].FirstOrDefault()["name"].ToString();

                // Check action result.
                response = client.GetAsync(TestEnvironment.GetRunActionsRequestUri(flowName: workflowName, runName: runId)).Result;
                responseContent = response.Content.ReadAsAsync<JToken>().Result;
                Assert.AreEqual("Succeeded", responseContent["value"].Where(actionResult => actionResult["name"].ToString().Equals("Compose")).FirstOrDefault()["properties"]["status"]);
            }
        }

        /// <summary>
        /// Workflow with mocked Http action.
        /// </summary>
        [TestMethod]
        public void HttpAction()
        {
            var localSettings = $@"
            {{
                ""IsEncrypted"": false,
                ""Values"": {{
                    ""AzureWebJobsStorage"": ""UseDevelopmentStorage=true"",
                    ""FUNCTIONS_WORKER_RUNTIME"": ""node"",
                    ""httpuri"": ""{TestEnvironment.FlowV2MockTestHostUri}""
                }}
            }}
            ";
            var workflowName = "httpactionworkflow";
            var workflowDefinition = File.ReadAllText($"TestFiles\\{workflowName}.json");

            using (new WorkflowTestHost(new WorkflowTestInput[] { new WorkflowTestInput(workflowName, workflowDefinition) }, localSettings: localSettings))
            using (var host = new MockHttpHost())
            using (var client = new HttpClient())
            {
                // Configure mocked response.
                host.RequestHandler = request =>
                {
                    var mockedResponse = new HttpResponseMessage(statusCode: HttpStatusCode.OK)
                    {
                        RequestMessage = request
                    };

                    mockedResponse.Content = new StringContent("Mocked Http Response");
                    return mockedResponse;
                };

                // Get workflow callback URL.
                var response = client.PostAsync(TestEnvironment.GetTriggerCallbackRequestUri(flowName: workflowName, triggerName: "manual"), null).Result;
                Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

                // Run the workflow.
                response = client.PostAsync(response.Content.ReadAsAsync<CallbackUrlDefinition>().Result.Value, null).Result;
                Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

                // Check workflow response.
                Assert.AreEqual("Mocked Http Response", response.Content.ReadAsStringAsync().Result);

                // Check workflow run status.
                response = client.GetAsync(TestEnvironment.GetRunsRequestUriWithManagementHost(flowName: workflowName)).Result;
                var responseContent = response.Content.ReadAsAsync<JToken>().Result;
                Assert.AreEqual("Succeeded", responseContent["value"][0]["properties"]["status"].ToString());
                var runId = responseContent["value"].FirstOrDefault()["name"].ToString();

                // Check action result.
                response = client.GetAsync(TestEnvironment.GetRunActionsRequestUri(flowName: workflowName, runName: runId)).Result;
                responseContent = response.Content.ReadAsAsync<JToken>().Result;
                Assert.AreEqual("Succeeded", responseContent["value"].Where(actionResult => actionResult["name"].ToString().Equals("HTTP")).FirstOrDefault()["properties"]["status"]);
            }
        }

        /// <summary>
        /// Workflow with mocked api connection action.
        /// </summary>
        [TestMethod]
        public void ApiConnectionAction()
        {
            var localSettings = $@"
            {{
                ""IsEncrypted"": false,
                ""Values"": {{
                    ""AzureWebJobsStorage"": ""UseDevelopmentStorage=true"",
                    ""FUNCTIONS_WORKER_RUNTIME"": ""node"",
                    ""arm-connectionRuntimeUrl"": ""{TestEnvironment.FlowV2MockTestHostUri}/apim/arm/foobar"",
                    ""arm-connectionKey"": ""foobar""
                }}
            }}
            ";

            var mockedResourceGroups = @"
{
    ""value"": [   
        {
            ""id"": ""/subscriptions/someSubscription/resourceGroups/someResourceGroup1"",
            ""name"": ""someResourceGroup1"",
            ""location"": ""eastus"",
            ""properties"": {
                ""provisioningState"": ""Succeeded""
            }
        },
        {
            ""id"": ""/subscriptions/someSubscription/resourceGroups/someResourceGroup2"",
            ""name"": ""someResourceGroup2"",
            ""location"": ""westus"",
            ""properties"": {
                ""provisioningState"": ""Succeeded""
            }
        }
    ]
}";
            var workflowName = "apiconnectionactionworkflow";
            var workflowDefinition = File.ReadAllText($"TestFiles\\{workflowName}.json");
            var connections = File.ReadAllText($"TestFiles\\connections.json");

            using (new WorkflowTestHost(new WorkflowTestInput[] { new WorkflowTestInput(workflowName, workflowDefinition) }, localSettings: localSettings, connectionDetails: connections))
            using (var host = new MockHttpHost())
            using (var client = new HttpClient())
            {
                // Configure mocked response.
                host.RequestHandler = request =>
                {
                    var mockedResponse = new HttpResponseMessage(statusCode: HttpStatusCode.OK)
                    {
                        RequestMessage = request
                    };

                    mockedResponse.Content = new StringContent(mockedResourceGroups);
                    return mockedResponse;
                };

                // Get workflow callback URL.
                var response = client.PostAsync(TestEnvironment.GetTriggerCallbackRequestUri(flowName: workflowName, triggerName: "manual"), null).Result;
                Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

                // Run the workflow.
                response = client.PostAsync(response.Content.ReadAsAsync<CallbackUrlDefinition>().Result.Value, null).Result;
                Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

                // Check workflow response.
                Assert.AreEqual(mockedResourceGroups, response.Content.ReadAsStringAsync().Result);

                // Check workflow run status.
                response = client.GetAsync(TestEnvironment.GetRunsRequestUriWithManagementHost(flowName: workflowName)).Result;
                var responseContent = response.Content.ReadAsAsync<JToken>().Result;
                Assert.AreEqual("Succeeded", responseContent["value"][0]["properties"]["status"].ToString());
                var runId = responseContent["value"].FirstOrDefault()["name"].ToString();

                // Check action result.
                response = client.GetAsync(TestEnvironment.GetRunActionsRequestUri(flowName: workflowName, runName: runId)).Result;
                responseContent = response.Content.ReadAsAsync<JToken>().Result;
                Assert.AreEqual("Succeeded", responseContent["value"].Where(actionResult => actionResult["name"].ToString().Equals("List_resource_groups")).FirstOrDefault()["properties"]["status"]);
            }
        }
    }
}
