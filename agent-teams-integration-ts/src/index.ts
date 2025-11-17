// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

import { A2AClient } from "@a2a-js/sdk/client";
import { Message, Task } from "@a2a-js/sdk";
import { v4 as uuidv4 } from "uuid";
import { startServer } from '@microsoft/agents-hosting-express'
import { AgentApplication, MemoryStorage, MessageFactory, TurnContext, TurnState } from '@microsoft/agents-hosting'

// DTOs for parsing the auth links payload
interface AuthLinkItem {
  ApiDetails?: ApiDetails;
  Link?: string;
  FirstPartyLoginUri?: string;
  Status?: string;
}

interface ApiDetails {
  ApiDisplayName?: string;
  ApiIconUri?: string;
  ApiBrandColor?: string;
}

class AutoSignInDemo extends AgentApplication<TurnState> {
  private readonly agentUrl: string;

  constructor() {
    super({
      storage: new MemoryStorage(),
      authorization: {
        logicapp: { text: 'Sign in to Logic Apps agent', title: 'Logic Apps Sign In' },
      }
    });

    if (!process.env['agent_url']) {
      throw new Error('Please set the agent_url environment variable to the agent base URL.');
    }

    // Set the agent URL - you may want to make this configurable
    this.agentUrl = process.env['agent_url'];

    this.authorization.onSignInSuccess(this._signinSuccess);
    this.authorization.onSignInFailure(this._signinFailure);
    this.onMessage('-signout', this._logout);
    this.onActivity('message', this._message, ['logicapp']);
  }

  private _logout = async (context: TurnContext, state: TurnState): Promise<void> => {
    await this.authorization.signOut(context, state);
    await context.sendActivity(MessageFactory.text('You have signed out'));
  }

  private _signinSuccess = async (context: TurnContext, state: TurnState, authId?: string): Promise<void> => {
    await context.sendActivity(MessageFactory.text(`User signed in successfully in ${authId}`));
  }

  private _signinFailure = async (context: TurnContext, state: TurnState, authId?: string, err?: string): Promise<void> => {
    await context.sendActivity(MessageFactory.text(`Sign In: Failed to login to '${authId}': ${err}`));
  }

  private _message = async (context: TurnContext, state: TurnState): Promise<void> => {
    let token: string;
    
    try {
      const userTokenResponse = await this.authorization.getToken(context, 'logicapp');
      if (!userTokenResponse?.token) {
        await context.sendActivity(MessageFactory.text('Authentication required. Please sign in first.'));
        return;
      }
      token = userTokenResponse.token;
    } catch (error) {
      await context.sendActivity(MessageFactory.text(`Could not get bearer token: ${error instanceof Error ? error.message : 'Unknown error'}`));
      return;
    }

    const fetchWithCustomHeaders: typeof fetch = async (url, init) => {
      const headers = new Headers(init?.headers);
      headers.set("Authorization", `Bearer ${token}`);
      
      // The agent uses ContextId to manage conversation state. ContextId is generated server-side
      // per A2A protocol. You can either catch those client-side after first-message & pass back in
      // explicitly, or you can leverage this experimental flag below. This flag will map the message
      // to the latest run with the same client tracking ID.
      headers.set("x-ms-enable-client-tracking-id-to-context", "enabled");
      headers.set("x-ms-client-tracking-id", context.activity.conversation!.id);
      
      const newInit = { ...init, headers };
      console.log(`Sending request to ${url}`);
      return fetch(url, newInit);
    };

    try {
      const client = await A2AClient.fromCardUrl(
        `${this.agentUrl}/.well-known/agent-card.json`,
        { fetchImpl: fetchWithCustomHeaders }
      );

      let initialTask: Task;
      try {
        const response = await client.sendMessage({
          message: {
            messageId: uuidv4(),
            role: "user",
            parts: [{ kind: "text", text: context.activity.text || "" }],
            kind: "message"
          }
        });

        if ("error" in response) {
          await context.sendActivity(MessageFactory.text(`Error sending message to agent: ${response.error.message}`));
          return;
        }

        initialTask = (response as any).result as Task;
      } catch (error) {
        await context.sendActivity(MessageFactory.text(`Error sending message to agent: ${error instanceof Error ? error.name : 'Unknown'}: ${error instanceof Error ? error.message : 'Unknown error'}`));
        return;
      }

      let finalTask: Task;
      try {
        finalTask = await this.pollTaskAsync(
          client,
          initialTask.id,
          1000, // 1 second poll interval
          180000 // 3 minute timeout
        );
      } catch (error) {
        if (error instanceof Error) {
          if (error.name === 'TimeoutError') {
            await context.sendActivity(MessageFactory.text(`Task ${initialTask.id} did not complete within timeout.`));
          } else {
            await context.sendActivity(MessageFactory.text(`The agent encountered an error. Debugging information: task ${initialTask.id}: ${error.message}`));
          }
        }
        return;
      }

      if (finalTask.status.state === 'auth-required') {
        await context.sendActivity(MessageFactory.text('Task needs authentication. Please follow the upcoming instructions. Sign-in requests will always be preceded by this message.'));
        
        const authTextPart = finalTask.status.message?.parts.find(part => part.kind === "text");
        const authText = authTextPart && "text" in authTextPart ? authTextPart.text : '';

        const markdown = this.tryBuildAuthLinksMarkdown(authText);
        if (markdown) {
          await context.sendActivity(MessageFactory.text(markdown));
        } else {
          // Fallback to original text if we couldn't parse the links
          await context.sendActivity(MessageFactory.text(authText));
        }
        return;
      }

      const artifactTextPart = finalTask.status.message?.parts.find(part => part.kind === "text");
      const artifactText = artifactTextPart && "text" in artifactTextPart ? artifactTextPart.text : 'Task completed successfully.';
      await context.sendActivity(MessageFactory.text(artifactText));

    } catch (error) {
      const errorMessage = error instanceof Error 
        ? `Error sending message to agent: ${error.name}: ${error.message}` 
        : 'Unknown error occurred while sending message to agent';
      await context.sendActivity(MessageFactory.text(errorMessage));
    }
  }

  private async pollTaskAsync(
    client: A2AClient,
    taskId: string,
    pollInterval: number = 1000,
    timeout: number = 30000
  ): Promise<Task> {
    const startTime = Date.now();

    while (true) {
      let current: Task | null = null;
      let retryCount = 5;

      // Retry logic for getting task status
      while (retryCount > 0) {
        try {
          const response = await client.getTask({
            id: taskId
          });
          if ("error" in response) {
            throw new Error(response.error.message);
          }
          current = response.result;
          break;
        } catch (error) {
          retryCount--;
          if (retryCount <= 0) {
            throw error;
          }
          await this.delay(200);
        }
      }

      if (!current) {
        throw new Error(`Failed to get task ${taskId}`);
      }

      if (this.isCompletedOrAuthRequired(current)) {
        return current;
      }

      if (Date.now() - startTime > timeout) {
        const timeoutError = new Error(`Task ${taskId} polling exceeded ${timeout}ms.`);
        timeoutError.name = 'TimeoutError';
        throw timeoutError;
      }

      await this.delay(pollInterval);
    }
  }

  private isCompletedOrAuthRequired(task: Task): boolean {
  return (
    (task.status.message != null && 
     (task.status.state === 'completed' || task.status.state === 'failed')) ||
    task.status.state === 'canceled' ||
    task.status.state === 'rejected' ||
    task.status.state === 'auth-required'
  );
}

  private async delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // Parses the auth prompt text for a JSON array of link descriptors and builds a markdown list of hyperlinks.
  private tryBuildAuthLinksMarkdown(authPrompt: string): string | null {
    if (!authPrompt) {
      return null;
    }

    // Find the JSON array portion, e.g. "...: [ { ... }, { ... } ]."
    const start = authPrompt.indexOf('[');
    const end = authPrompt.lastIndexOf(']');
    if (start < 0 || end <= start) {
      return null;
    }

    const json = authPrompt.substring(start, end + 1);
    let items: AuthLinkItem[];
    
    try {
      items = JSON.parse(json);
    } catch {
      return null;
    }

    if (!items || items.length === 0) {
      return null;
    }

    const lines = ['Please authenticate using the following link(s) and message when you\'re done:'];
    console.log(items);
    for (const item of items) {
      const name = item.ApiDetails?.ApiDisplayName ||
                   this.tryGetHost(item.Link!) ||
                   'Authentication Link';
      const status = item.Status ? ` — ${item.Status}` : '';
      lines.push(`- [${this.escapeInlineMarkdown(name)}](${item.Link})${status}`);
    }

    return lines.join('\n');
  }

  private tryGetHost(link: string): string | null {
    try {
      return new URL(link).hostname;
    } catch {
      return null;
    }
  }

  private escapeInlineMarkdown(text: string): string {
    return text
      .replace(/\[/g, '\\[')
      .replace(/\]/g, '\\]')
      .replace(/\(/g, '\\(')
      .replace(/\)/g, '\\)');
  }
}

startServer(new AutoSignInDemo());