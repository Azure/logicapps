// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

namespace TestFramework
{
    using System;
    using System.Collections.Generic;
    using System.Net.Http;
    using System.Threading;
    using Microsoft.AspNetCore.Http;

    /// <summary>
    /// Http request message feature.
    /// </summary>
    public class HttpRequestMessageFeature
    {
        /// <summary>
        /// The request message.
        /// </summary>
        private HttpRequestMessage httpRequestMessage;

        /// <summary>
        /// Gets or sets the http context.
        /// </summary>
        private HttpContext HttpContext { get; set; }

        /// <summary>
        /// Gets or sets the http request message.
        /// </summary>
        public HttpRequestMessage HttpRequestMessage
        {
            get => this.httpRequestMessage ?? Interlocked.CompareExchange(ref this.httpRequestMessage, HttpRequestMessageFeature.CreateHttpRequestMessage(this.HttpContext), null) ?? this.httpRequestMessage;

            set
            {
                var oldValue = this.httpRequestMessage;
                if (Interlocked.Exchange(ref this.httpRequestMessage, value) != oldValue)
                {
                    oldValue?.Dispose();
                }
            }
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="HttpRequestMessageFeature"/> class.
        /// </summary>
        /// <param name="httpContext">The http request message feature.</param>
        public HttpRequestMessageFeature(HttpContext httpContext)
        {
            this.HttpContext = httpContext;
        }

        /// <summary>
        /// Creates the http request message.
        /// </summary>
        /// <param name="httpContext">The http context.</param>
        private static HttpRequestMessage CreateHttpRequestMessage(HttpContext httpContext)
        {
            HttpRequestMessage message = null;
            try
            {
                var httpRequest = httpContext.Request;
                var uriString =
                    httpRequest.Scheme + "://" +
                    httpRequest.Host +
                    httpRequest.PathBase +
                    httpRequest.Path +
                    httpRequest.QueryString;

                message = new HttpRequestMessage(new HttpMethod(httpRequest.Method), uriString);

                // This allows us to pass the message through APIs defined in legacy code and then
                // operate on the HttpContext inside.
                message.Properties[nameof(HttpContext)] = httpContext;

                message.Content = new StreamContent(httpRequest.Body);

                foreach (var header in httpRequest.Headers)
                {
                    // Every header should be able to fit into one of the two header collections.
                    // Try message.Headers first since that accepts more of them.
                    if (!message.Headers.TryAddWithoutValidation(header.Key, (IEnumerable<string>)header.Value))
                    {
                        var added = message.Content.Headers.TryAddWithoutValidation(header.Key, (IEnumerable<string>)header.Value);
                    }
                }

                return message;
            }
            catch (Exception)
            {
                message?.Dispose();
                throw;
            }
        }
    }
}
