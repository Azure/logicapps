// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

namespace TestFramework
{
    using System;

    /// <summary>
    /// The test setup class.
    /// </summary>
    public class TestEnvironment
    {


        /// <summary>
        /// Flow runtime webhook extension uri base path.
        /// </summary>
        public const string WorkflowExtensionBasePath = "/runtime/webhooks/workflow";

        /// <summary>
        /// Flow runtime webhook extension uri management base path.
        /// </summary>
        public static readonly string FlowExtensionManagementBasePath = $"{WorkflowExtensionBasePath}/api/management";

        /// <summary>
        /// Flow runtime webhook extension uri workflow management base path.
        /// </summary>
        public static readonly string FlowExtensionWorkflowManagementBasePath = $"{FlowExtensionManagementBasePath}/workflows";

        /// <summary>
        /// The edge api version.
        /// </summary>
        public static readonly string EdgePreview20191001ApiVersion = "2019-10-01-edge-preview";

        /// <summary>
        /// The API version 2020-05-01.
        /// </summary>
        public static readonly string EdgePreview20200501ApiVersion = "2020-05-01-preview";

        /// <summary>
        /// The management host name.
        /// </summary>
        public static readonly string ManagementHostName = $"{Environment.MachineName}";

        /// <summary>
        /// The test host uri.
        /// </summary>
        public static readonly string FlowV2TestHostUri = (new UriBuilder(Uri.UriSchemeHttp, Environment.MachineName, 7071).Uri.ToString()).TrimEnd('/');

        /// <summary>
        /// The mock test host uri.
        /// </summary>
        public static readonly string FlowV2MockTestHostUri = (new UriBuilder(Uri.UriSchemeHttp, Environment.MachineName, 7075).Uri.ToString()).TrimEnd('/');

        /// <summary>
        /// The test host uri.
        /// </summary>
        public static readonly string FlowV2TestManagementHostUri = (new UriBuilder(Uri.UriSchemeHttp, TestEnvironment.ManagementHostName, 7071).Uri.ToString()).TrimEnd('/');

        /// <summary>
        /// Flow runtime webhook extension uri management base path.
        /// </summary>
        public static readonly string ManagementBaseUrl = TestEnvironment.FlowV2TestHostUri + FlowExtensionManagementBasePath;

        /// <summary>
        /// Flow runtime webhook extension uri workflow management base path.
        /// </summary>
        public static readonly string ManagementWorkflowBaseUrl = TestEnvironment.FlowV2TestHostUri + FlowExtensionWorkflowManagementBasePath;

        /// <summary>
        /// Flow runtime webhook extension uri workflow management base path with management host.
        /// </summary>
        public static readonly string ManagementWorkflowBaseUrlWithManagementHost = TestEnvironment.FlowV2TestManagementHostUri + FlowExtensionWorkflowManagementBasePath;


        /// <summary>
        /// Gets the trigger callback URI.
        /// </summary>
        /// <param name="flowName">The flow name.</param>
        /// <param name="triggerName">The trigger name.</param>
        public static string GetTriggerCallbackRequestUri(string flowName, string triggerName)
        {
            return string.Format(
                "{0}/{1}/triggers/{2}/listCallbackUrl?api-version={3}",
                TestEnvironment.ManagementWorkflowBaseUrl,
                flowName,
                triggerName,
                TestEnvironment.EdgePreview20191001ApiVersion);
        }

        /// <summary>
        /// Gets the runs request URI with management host.
        /// </summary>
        /// <param name="flowName">The flow name.</param>
        /// <param name="top">The top.</param>
        public static string GetRunsRequestUriWithManagementHost(string flowName, int? top = null)
        {
            return top != null
                ? string.Format(
                    "{0}/{1}/runs?api-version={2}&$top={3}",
                    TestEnvironment.ManagementWorkflowBaseUrlWithManagementHost,
                    flowName,
                    TestEnvironment.EdgePreview20191001ApiVersion,
                    top.Value)
                : string.Format(
                    "{0}/{1}/runs?api-version={2}",
                    TestEnvironment.ManagementWorkflowBaseUrlWithManagementHost,
                    flowName,
                    TestEnvironment.EdgePreview20191001ApiVersion);
        }

        /// <summary>
        /// Gets the run actions URI.
        /// </summary>
        /// <param name="flowName">The flow name.</param>
        /// <param name="runName">The run name.</param>
        public static string GetRunActionsRequestUri(string flowName, string runName)
        {
            return string.Format(
                "{0}/{1}/runs/{2}/actions?api-version={3}",
                TestEnvironment.ManagementWorkflowBaseUrl,
                flowName,
                runName,
                TestEnvironment.EdgePreview20191001ApiVersion);
        }
    }
}
