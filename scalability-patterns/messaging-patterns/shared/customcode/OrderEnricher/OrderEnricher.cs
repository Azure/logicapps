//------------------------------------------------------------
// Logic Apps messaging benchmark kit - custom code sample.
//------------------------------------------------------------

namespace MsgPat.CustomCode
{
    using System;
    using System.Threading.Tasks;
    using Microsoft.Azure.Functions.Extensions.Workflows;
    using Microsoft.Azure.Functions.Worker;
    using Microsoft.Extensions.Logging;

    /// <summary>
    /// Enriches a transformed order with a computed price. Called from the process-order workflow.
    /// </summary>
    public class OrderEnricher
    {
        /// <summary>
        /// The logger.
        /// </summary>
        private readonly ILogger<OrderEnricher> _logger;

        /// <summary>
        /// Initializes a new instance of the <see cref="OrderEnricher"/> class.
        /// </summary>
        /// <param name="loggerFactory">The logger factory.</param>
        public OrderEnricher(ILoggerFactory loggerFactory)
        {
            this._logger = loggerFactory.CreateLogger<OrderEnricher>();
        }

        /// <summary>
        /// Computes the order total, tax and a priority tier.
        /// </summary>
        /// <param name="orderId">The order id.</param>
        /// <param name="quantity">The total item quantity.</param>
        /// <param name="unitPrice">The average unit price.</param>
        /// <param name="region">The customer region.</param>
        [Function("OrderEnricher")]
        public Task<EnrichmentResult> Run([WorkflowActionTrigger] string orderId, int quantity, double unitPrice, string region)
        {
            var subtotal = Math.Round(quantity * unitPrice, 2);
            var taxRate = string.Equals(region, "EU", StringComparison.OrdinalIgnoreCase) ? 0.20 : 0.08;
            var discount = quantity >= 10 ? 0.05 : 0.0;
            var total = Math.Round(subtotal * (1 - discount) * (1 + taxRate), 2);

            this._logger.LogInformation("MsgPatOrderEnricher order {OrderId} subtotal {Subtotal} total {Total}.", orderId, subtotal, total);

            return Task.FromResult(new EnrichmentResult
            {
                OrderId = orderId,
                Subtotal = subtotal,
                TaxRate = taxRate,
                Discount = discount,
                Total = total,
                Tier = total > 500 ? "gold" : total > 100 ? "silver" : "bronze",
                EnrichedAtUtc = DateTime.UtcNow,
            });
        }

        /// <summary>
        /// The enrichment output.
        /// </summary>
        public class EnrichmentResult
        {
            /// <summary>Gets or sets the order id.</summary>
            public string OrderId { get; set; }

            /// <summary>Gets or sets the subtotal.</summary>
            public double Subtotal { get; set; }

            /// <summary>Gets or sets the tax rate.</summary>
            public double TaxRate { get; set; }

            /// <summary>Gets or sets the discount rate.</summary>
            public double Discount { get; set; }

            /// <summary>Gets or sets the total.</summary>
            public double Total { get; set; }

            /// <summary>Gets or sets the tier.</summary>
            public string Tier { get; set; }

            /// <summary>Gets or sets the enrichment time.</summary>
            public DateTime EnrichedAtUtc { get; set; }
        }
    }
}
