// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information

namespace TestFramework
{
    using System;
    using System.Collections.Generic;
    using Newtonsoft.Json;

    /// <summary>
    /// Flow callback URL definition.
    /// </summary>
    public class CallbackUrlDefinition
    {
        /// <summary>
        /// Gets or sets the value.
        /// </summary>
        [JsonProperty]
        public Uri Value { get; set; }

        /// <summary>
        /// Gets or sets the method.
        /// </summary>
        [JsonProperty]
        public string Method { get; set; }

        /// <summary>
        /// Gets or sets the base path.
        /// </summary>
        [JsonProperty]
        public Uri BasePath { get; set; }

        /// <summary>
        /// Gets or sets the relative path.
        /// </summary>
        [JsonProperty]
        public string RelativePath { get; set; }

        /// <summary>
        /// Gets or sets relative path parameters.
        /// </summary>
        [JsonProperty]
        public List<string> RelativePathParameters { get; set; }

        /// <summary>
        /// Gets or sets queries.
        /// </summary>
        [JsonProperty]
        public Dictionary<string, string> Queries { get; set; }
    }
}
