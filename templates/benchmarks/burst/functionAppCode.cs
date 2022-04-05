using System;
using System.IO;
using System.Linq;
using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using System.Threading.Tasks;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace Company.Function
{
    public static class retail_stubdp
    {
        [FunctionName("retail_stubdp")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            string ean = req.Query["ean"];

            return new OkObjectResult(new RetailStubResponse
            {
                Skus = new List<string>{ $"sku-{ean}" }
            });
        }
    }
    public class RetailStubResponse
{
    public List<string> Skus { get; set; }
}

}