//------------------------------------------------------------
// Copyright (c) Microsoft Corporation.  All rights reserved.
//------------------------------------------------------------

namespace Tests.Flow.Functions
{
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Microsoft.Azure.Functions.Extensions.Workflows.WorkflowActionTrigger;
    using Microsoft.Azure.WebJobs;
    /// <summary>
    /// The flow invoked function.
    /// </summary>
    public static class FlowInvokedFunctionTest
    {
        /// <summary>
        /// Run method.
        /// </summary>
        /// <param name="parameter1">The parameter 1.</param>
        /// <param name="parameter2">The parameter 2.</param>
        [FunctionName("FlowInvokedFunction")]
        public static Task<Wrapper> Run([WorkflowActionTrigger] string parameter1, int parameter2)
        {
            var result = new Wrapper
            {
                RandomProperty = new Dictionary<string, object>(){
                    ["parameter1"] = parameter1,
                    ["parameter2"] = parameter2
                }
            };

            return Task.FromResult(result); 
        }

        /// <summary>
        /// The wrapper.
        /// </summary>
        public class Wrapper
        {
            /// <summary>
            /// Gets or sets the .NET Framework worker output.
            /// </summary>
            public Dictionary<string, object> RandomProperty { get; set; }
        }
    }
 }
