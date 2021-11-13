// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.

namespace TestFramework
{
    using System;
    using System.Linq;
    using System.Net.Http;
    using System.Net.Http.Formatting;
    using System.Threading;
    using System.Web.Http;
    using Microsoft.AspNetCore;
    using Microsoft.AspNetCore.Builder;
    using Microsoft.AspNetCore.Hosting;
    using Microsoft.AspNetCore.Http;
    using Microsoft.AspNetCore.Http.Features;
    using Microsoft.AspNetCore.Mvc;
    using Microsoft.AspNetCore.ResponseCompression;
    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.DependencyInjection.Extensions;
    using Microsoft.Extensions.Hosting;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Primitives;

    /// <summary>
    /// The mock HTTP host.
    /// </summary>
    public class MockHttpHost : IDisposable
    {
        /// <summary>
        /// The web host.
        /// </summary>
        public IWebHost Host { get; set; }

        /// <summary>
        /// The request handler.
        /// </summary>
        public Func<HttpRequestMessage, HttpResponseMessage> RequestHandler { get; set; }

        /// <summary>
        /// Initializes a new instance of the <see cref="MockHttpHost"/> class.
        /// </summary>
        public MockHttpHost(string url = null)
        {
            this.Host = WebHost
                .CreateDefaultBuilder()
                .UseSetting(key: WebHostDefaults.SuppressStatusMessagesKey, value: "true")
                .ConfigureLogging(config => config.ClearProviders())
                .ConfigureServices(services =>
                {
                    services.AddSingleton<MockHttpHost>(this);
                })
                .UseStartup<Startup>()
                .UseUrls(url ?? TestEnvironment.FlowV2MockTestHostUri)
                .Build();

            this.Host.Start();
        }

        /// <summary>
        /// Disposes the resources.
        /// </summary>
        public void Dispose()
        {
            this.Host.StopAsync().Wait();
        }

        private class Startup
        {
            /// <summary>
            /// Gets or sets the request pipeline manager.
            /// </summary>
            private MockHttpHost Host { get; set; }

            public Startup(MockHttpHost host)
            {
                this.Host = host;
            }

            /// <summary>
            /// Configure the services.
            /// </summary>
            /// <param name="services">The services.</param>
            public void ConfigureServices(IServiceCollection services)
            {
                services
                    .Configure<IISServerOptions>(options =>
                    {
                        options.AllowSynchronousIO = true;
                    })
                    .AddResponseCompression(options =>
                    {
                        options.EnableForHttps = true;
                        options.Providers.Add<GzipCompressionProvider>();
                    })
                    .AddMvc(options =>
                    {
                        options.EnableEndpointRouting = true;
                    })
                    .SetCompatibilityVersion(CompatibilityVersion.Version_3_0);
            }

            /// <summary>
            /// Configures the application.
            /// </summary>
            /// <param name="app">The application.</param>
            public void Configure(IApplicationBuilder app)
            {
                app.UseResponseCompression();

                app.Use(async (context, next) =>
                {
                    var syncIOFeature = context.Features.Get<IHttpBodyControlFeature>();
                    if (syncIOFeature != null)
                    {
                        syncIOFeature.AllowSynchronousIO = true;
                    }

                    using (var request = GetHttpRequestMessage(context))
                    using (var responseMessage = this.Host.RequestHandler(request))
                    {
                        var response = context.Response;

                        response.StatusCode = (int)responseMessage.StatusCode;

                        var responseHeaders = responseMessage.Headers;

                        // Ignore the Transfer-Encoding header if it is just "chunked".
                        // We let the host decide about whether the response should be chunked or not.
                        if (responseHeaders.TransferEncodingChunked == true &&
                            responseHeaders.TransferEncoding.Count == 1)
                        {
                            responseHeaders.TransferEncoding.Clear();
                        }

                        foreach (var header in responseHeaders)
                        {
                            response.Headers.Append(header.Key, header.Value.ToArray());
                        }

                        if (responseMessage.Content != null)
                        {
                            var contentHeaders = responseMessage.Content.Headers;

                            // Copy the response content headers only after ensuring they are complete.
                            // We ask for Content-Length first because HttpContent lazily computes this
                            // and only afterwards writes the value into the content headers.
                            var unused = contentHeaders.ContentLength;

                            foreach (var header in contentHeaders)
                            {
                                response.Headers.Append(header.Key, header.Value.ToArray());
                            }

                            await responseMessage.Content.CopyToAsync(response.Body).ConfigureAwait(false);
                        }
                    }
                });
            }
        }

        /// <summary>
        /// Gets the http request message.
        /// </summary>
        /// <param name="httpContext">The http context.</param>
        public static HttpRequestMessage GetHttpRequestMessage(HttpContext httpContext)
        {
            var feature = httpContext.Features.Get<HttpRequestMessageFeature>();
            if (feature == null)
            {
                feature = new HttpRequestMessageFeature(httpContext);
                httpContext.Features.Set(feature);
            }

            return feature.HttpRequestMessage;
        }
    }
}
