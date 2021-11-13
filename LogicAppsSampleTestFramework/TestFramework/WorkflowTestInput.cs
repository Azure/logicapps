// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information

namespace TestFramework
{
    /// <summary>
    /// Function test Input
    /// </summary>
    public class WorkflowTestInput
    {
        /// <summary>
        /// Gets or sets the function name.
        /// </summary>
        public string FunctionName { get; set; }

        /// <summary>
        /// Gets or sets the flow definition.
        /// </summary>
        public string FlowDefinition { get; set; }

        /// <summary>
        /// Gets or sets the file name.
        /// </summary>
        public string Filename { get; set; }

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="functionName">Function name</param>
        /// <param name="flowDefinition">Flow definition</param>
        /// <param name="fileName">File name.</param>
        public WorkflowTestInput(string functionName = null, string flowDefinition = null, string fileName = null)
        {
            this.FunctionName = functionName;
            this.FlowDefinition = flowDefinition;
            this.Filename = fileName ?? "workflow.json";
        }
    }
}
