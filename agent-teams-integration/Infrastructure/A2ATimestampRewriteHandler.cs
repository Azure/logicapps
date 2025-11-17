using System;
using System.Globalization;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace AutoSignIn.Infrastructure;

/// <summary>
/// Normalizes non-ISO timestamps (e.g. M/d/yyyy h:mm:ss tt) in JSON responses
/// into ISO 8601 so System.Text.Json can deserialize DateTimeOffset.
/// Assumes timestamps are UTC or local-to-UTC convertible (adjust if needed).
/// </summary>
public sealed class A2ATimestampRewriteHandler : DelegatingHandler
{
    // Matches: "timestamp": "8/25/2025 8:07:32 AM"
    private static readonly Regex TimestampRegex = new(
        "\"timestamp\"\\s*:\\s*\"(?<dt>\\d{1,2}/\\d{1,2}/\\d{4} \\d{1,2}:\\d{2}:\\d{2} [AP]M)\"",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        HttpResponseMessage response = await base.SendAsync(request, cancellationToken);

        if (response.Content?.Headers.ContentType?.MediaType is not "application/json")
            return response;

        string original = await response.Content.ReadAsStringAsync(cancellationToken);
        if (original.IndexOf("\"timestamp\"", StringComparison.Ordinal) < 0)
            return response;

        string rewritten = TimestampRegex.Replace(original, m =>
        {
            var raw = m.Groups["dt"].Value;

            // Try parse as unspecified => treat as UTC (adjust if you need local).
            if (DateTime.TryParseExact(
                    raw,
                    "M/d/yyyy h:mm:ss tt",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var dt))
            {
                var iso = dt.ToUniversalTime().ToString("o");
                return $"\"timestamp\":\"{iso}\"";
            }

            // Fallback: leave unchanged
            return m.Value;
        });

        if (!ReferenceEquals(original, rewritten))
        {
            response.Content = new StringContent(rewritten, Encoding.UTF8, "application/json");
        }

        return response;
    }
}