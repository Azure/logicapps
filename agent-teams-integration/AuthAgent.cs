// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using A2A;
using AutoSignIn.Infrastructure;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.App;
using Microsoft.Agents.Builder.App.UserAuth;
using Microsoft.Agents.Builder.State;
using Microsoft.Agents.Builder.UserAuth;
using Microsoft.Agents.Core.Models;
using Microsoft.Extensions.Options;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace AutoSignIn;
public class AuthAgent : AgentApplication
{
    private readonly string _agentUrl;

    public AuthAgent(AgentApplicationOptions options, IOptions<WorkflowOptions> workflowOptions) : base(options)
    {
        var wf = workflowOptions.Value;
        _agentUrl = wf.AgentUrl.TrimEnd('/');

        OnConversationUpdate(ConversationUpdateEvents.MembersAdded, WelcomeMessageAsync);

        // Handles the user sending a SignOut command using the specific keywords '-signout'
        OnMessage("-signout", async (turnContext, turnState, cancellationToken) =>
        {
            await UserAuthorization.SignOutUserAsync(turnContext, turnState, cancellationToken: cancellationToken);
            await turnContext.SendActivityAsync("You have signed out", cancellationToken: cancellationToken);
        }, rank: RouteRank.Last);

        OnActivity(ActivityTypes.Message, OnMessageAsync, rank: RouteRank.Last);

        UserAuthorization.OnUserSignInFailure(OnUserSignInFailure);
    }

    private async Task WelcomeMessageAsync(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
    {
        foreach (ChannelAccount member in turnContext.Activity.MembersAdded)
        {
            if (member.Id != turnContext.Activity.Recipient.Id)
            {
                StringBuilder sb = new();
                sb.AppendLine("Hello!");
                await turnContext.SendActivityAsync(MessageFactory.Text(sb.ToString()), cancellationToken);
                sb.Clear();
            }
        }
    }

    private async Task OnMessageAsync(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
    {
        string token;
        try
        {
            token = await UserAuthorization.GetTurnTokenAsync(turnContext, UserAuthorization.DefaultHandlerName);
        }
        catch (Exception ex)
        {
            await turnContext.SendActivityAsync($"Could not get bearer token: {ex.Message}", cancellationToken: cancellationToken);
            return;
        }

        var httpClient = new HttpClient(new A2ATimestampRewriteHandler
        {
            InnerHandler = new HttpClientHandler()
        });

        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        
        // The agent uses ContextId to manage conversation state. ContextId is generated server-side
        // per A2A protocol. You can either catch those client-side after first-message & pass back in
        // explicitly, or you can leverage this experimental flag below. This flag will map the message
        // to the latest run with the same client tracking ID.
        httpClient.DefaultRequestHeaders.Add("x-ms-enable-client-tracking-id-to-context", "enabled");
        httpClient.DefaultRequestHeaders.Add("x-ms-client-tracking-id", turnContext.Activity.Conversation.Id);

        try
        {
            var a2aClient = new A2AClient(new Uri($"{_agentUrl}/"), httpClient);
            AgentTask initialTask;
            try
            {
                var agentMessage = new AgentMessage
                {
                    Role = MessageRole.User,
                    Parts = [new TextPart { Text = turnContext.Activity.Text }],
                    MessageId = Guid.NewGuid().ToString(),
                };

                initialTask = (AgentTask)await a2aClient.SendMessageAsync(new MessageSendParams
                {
                    Message = agentMessage
                });
            }
            catch (Exception ex)
            {
                await turnContext.SendActivityAsync($"Error sending message to agent: {ex.GetType().Name}: {ex.Message} {ex.InnerException}", cancellationToken: cancellationToken);
                return;
            }

            AgentTask finalTask;
            try
            {
                finalTask = await PollTaskAsync(
                    a2aClient,
                    initialTask.Id,
                    pollInterval: TimeSpan.FromSeconds(1),
                    timeout: TimeSpan.FromSeconds(180),
                    cancellationToken: cancellationToken);
            }
            catch (OperationCanceledException)
            {
                await turnContext.SendActivityAsync("Task polling canceled.", cancellationToken: cancellationToken);
                return;
            }
            catch (TimeoutException)
            {
                await turnContext.SendActivityAsync($"Task {initialTask.Id} did not complete within timeout.", cancellationToken: cancellationToken);
                return;
            }
            catch (Exception ex)
            {
                await turnContext.SendActivityAsync($"The agent encountered an error. Debugging information: task {initialTask.Id}: {ex.Message}", cancellationToken: cancellationToken);
                return;
            }

            if (finalTask.Status.State == TaskState.AuthRequired)
            {
                await turnContext.SendActivityAsync("Task needs authentication. Please follow the upcoming instructions. Sign-in requests will always be preceded by this message.", cancellationToken: cancellationToken);
                string authText = finalTask.Status.Message?.Parts.OfType<TextPart>().FirstOrDefault()?.Text!;

                if (TryBuildAuthLinksMarkdown(authText, out var markdown))
                {
                    await turnContext.SendActivityAsync(markdown, cancellationToken: cancellationToken);
                }
                else
                {
                    // Fallback to original text if we couldn't parse the links
                    await turnContext.SendActivityAsync(authText, cancellationToken: cancellationToken);
                }
                return;
            }

            string artifactText = finalTask.Status.Message?.Parts.OfType<TextPart>().FirstOrDefault()?.Text!;
            await turnContext.SendActivityAsync(artifactText, cancellationToken: cancellationToken);
        }
        catch (Exception ex)
        {
            await turnContext.SendActivityAsync($"Error sending message to agent: {ex.GetType().Name}: {ex.Message} {ex.InnerException} {ex.StackTrace}", cancellationToken: cancellationToken);
        }
    }

    private static async Task<AgentTask> PollTaskAsync(
        A2AClient client,
        string taskId,
        TimeSpan? pollInterval = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var interval = pollInterval ?? TimeSpan.FromSeconds(1);
        var max = timeout ?? TimeSpan.FromSeconds(30);
        var sw = Stopwatch.StartNew();

        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var retryCount = 5;
            AgentTask? current = null;
            while (retryCount > 0 && !cancellationToken.IsCancellationRequested)
            {
                retryCount--;
                try
                {
                    current = await client.GetTaskAsync(taskId, cancellationToken);
                    break;
                }
                catch (Exception)
                {
                    if (retryCount <= 0)
                        throw;
                    await Task.Delay(200, cancellationToken);
                }
            }

            if (IsCompletedOrAuthRequired(current))
                return current;

            if (sw.Elapsed > max)
                throw new TimeoutException($"Task {taskId} polling exceeded {max}.");

            await Task.Delay(interval, cancellationToken);
        }

        static bool IsCompletedOrAuthRequired(AgentTask task) =>
            (task.Status.Message != null && (task.Status.State == TaskState.Completed || task.Status.State == TaskState.Failed))
            || task.Status.State == TaskState.Canceled
            || task.Status.State == TaskState.Rejected
            || task.Status.State == TaskState.AuthRequired;
    }

    private async Task OnUserSignInFailure(ITurnContext turnContext, ITurnState turnState, string handlerName, SignInResponse response, IActivity initiatingActivity, CancellationToken cancellationToken)
    {
        await turnContext.SendActivityAsync($"Sign In: Failed to login to '{handlerName}': {response.Cause}/{response.Error!.Message}", cancellationToken: cancellationToken);
    }

    // Parses the auth prompt text for a JSON array of link descriptors and builds a markdown list of hyperlinks.
    private static bool TryBuildAuthLinksMarkdown(string authPrompt, out string markdown)
    {
        markdown = string.Empty;
        if (string.IsNullOrWhiteSpace(authPrompt))
            return false;

        // Find the JSON array portion, e.g. "...: [ { ... }, { ... } ]."
        int start = authPrompt.IndexOf('[');
        int end = authPrompt.LastIndexOf(']');
        if (start < 0 || end <= start)
            return false;

        var json = authPrompt.Substring(start, end - start + 1);
        List<AuthLinkItem>? items;
        try
        {
            items = JsonSerializer.Deserialize<List<AuthLinkItem>>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch
        {
            return false;
        }

        if (items == null || items.Count == 0)
            return false;

        var sb = new StringBuilder();
        sb.AppendLine("Please authenticate using the following link(s) and message when you're done:");
        foreach (var item in items)
        {
            if (string.IsNullOrWhiteSpace(item.Link))
                continue;

            var name = item.ApiDetails?.ApiDisplayName
                       ?? item.DisplayName
                       ?? TryGetHost(item.Link)
                       ?? "Authentication Link";

            if (!Uri.TryCreate(item.Link, UriKind.Absolute, out var uri))
                continue;

            var status = string.IsNullOrWhiteSpace(item.Status) ? string.Empty : $" — {item.Status}";
            sb.AppendLine($"- [{EscapeInlineMarkdown(name)}]({uri}){status}");
        }

        markdown = sb.ToString();
        return true;

        static string? TryGetHost(string? link)
            => Uri.TryCreate(link ?? string.Empty, UriKind.Absolute, out var u) ? u.Host : null;

        static string EscapeInlineMarkdown(string text)
            => text.Replace("[", "\\[").Replace("]", "\\]").Replace("(", "\\(").Replace(")", "\\)");
    }

    // DTOs for parsing the auth links payload
    private sealed class AuthLinkItem
    {
        public ApiDetails? ApiDetails { get; set; }
        public string? Link { get; set; }
        public string? FirstPartyLoginUri { get; set; }
        public string? DisplayName { get; set; }
        public string? Status { get; set; }
    }

    private sealed class ApiDetails
    {
        public string? ApiDisplayName { get; set; }
        public string? ApiIconUri { get; set; }
        public string? ApiBrandColor { get; set; }
    }
}
