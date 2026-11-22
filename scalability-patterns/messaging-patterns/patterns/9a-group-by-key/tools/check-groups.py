"""Checks group completeness and fan-in latency for pattern 9a from the Cosmos documents.

The measured workflow writes one "part" document per received line message, with a unique
id, pk = orderId, lineNo, lineCount, sentAtUtc (the order's send time), processedAtUtc,
runId and batchSize. For every order sent in the window this script counts:

  complete    orders with exactly lineCount distinct lines and no duplicates
  missing     line numbers between 1 and lineCount that have no document
  duplicates  documents beyond the first for the same (orderId, lineNo)
  runs/order  distinct workflow runs that wrote the order's lines (1 = whole group in one run)

Latency per order is the last processedAtUtc minus sentAtUtc, that is, from the first item
sent to the moment the whole group is written. Throughput is documents divided by the span
between the first and last processedAtUtc.

Usage:
  python check-groups.py <cosmos-endpoint> <startUtc> <endUtc> [output.json] [--pattern 9a-group-by-key]

The window filters on sentAtUtc. Auth uses the Azure CLI login.
"""

import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
for folder in ("pylib", "pylib-cosmos"):
    sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", folder))
for name in [name for name in sys.modules if name == "azure" or name.startswith("azure.")]:
    del sys.modules[name]

from azure.cosmos import CosmosClient  # noqa: E402
from azure.identity import AzureCliCredential  # noqa: E402


def parse_time(value):
    """Parse ISO 8601 times with any number of fractional digits."""
    text = value.replace("Z", "+00:00")
    if "." in text:
        head, rest = text.split(".", 1)
        digits = "".join(ch for ch in rest if ch.isdigit())
        zone = rest[len(digits):]
        text = f"{head}.{digits[:6].ljust(6, '0')}{zone}"
    return datetime.fromisoformat(text)


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def main():
    args = [arg for arg in sys.argv[1:]]
    pattern = "9a-group-by-key"
    if "--pattern" in args:
        index = args.index("--pattern")
        pattern = args[index + 1]
        del args[index:index + 2]
    endpoint, start, end = args[0], args[1], args[2]
    output = args[3] if len(args) > 3 else None
    container = (
        CosmosClient(endpoint, AzureCliCredential())
        .get_database_client("msgpat")
        .get_container_client("items")
    )
    query = (
        "SELECT c.orderId, c.lineNo, c.lineCount, c.sentAtUtc, c.processedAtUtc, c.runId, "
        "c.batchSize, c.deliveryCount FROM c WHERE c.pattern = @pattern AND c.docType = 'part' "
        "AND c.sentAtUtc >= @start AND c.sentAtUtc <= @end"
    )
    rows = list(
        container.query_items(
            query,
            parameters=[
                {"name": "@pattern", "value": pattern},
                {"name": "@start", "value": start},
                {"name": "@end", "value": end},
            ],
            enable_cross_partition_query=True,
        )
    )
    by_order = defaultdict(list)
    for row in rows:
        by_order[row["orderId"]].append(row)

    complete = missing = duplicates = 0
    runs_per_order = Counter()
    latencies = []
    incomplete = []
    for order_id, docs in by_order.items():
        expected = int(docs[0].get("lineCount") or 0)
        lines = Counter(int(doc["lineNo"]) for doc in docs)
        order_missing = sum(1 for line in range(1, expected + 1) if line not in lines)
        order_duplicates = sum(count - 1 for count in lines.values())
        missing += order_missing
        duplicates += order_duplicates
        runs_per_order[len({doc["runId"] for doc in docs})] += 1
        if not order_missing and not order_duplicates:
            complete += 1
        else:
            incomplete.append({"orderId": order_id, "missing": order_missing, "duplicates": order_duplicates})
        if not order_missing:
            sent = parse_time(docs[0]["sentAtUtc"])
            done = max(parse_time(doc["processedAtUtc"]) for doc in docs)
            latencies.append((done - sent).total_seconds())

    processed = [parse_time(row["processedAtUtc"]) for row in rows]
    span = (max(processed) - min(processed)).total_seconds() if processed else 0
    batch_sizes = [int(row.get("batchSize") or 0) for row in rows]
    result = {
        "pattern": pattern,
        "sentWindowStartUtc": start,
        "sentWindowEndUtc": end,
        "documents": len(rows),
        "orders": len(by_order),
        "ordersComplete": complete,
        "ordersIncomplete": len(incomplete),
        "missingLines": missing,
        "duplicateLines": duplicates,
        "redeliveredDocuments": sum(1 for row in rows if int(row.get("deliveryCount") or 1) > 1),
        "runs": len({row["runId"] for row in rows}),
        "runsPerOrderHistogram": {str(key): value for key, value in sorted(runs_per_order.items())},
        "batchSizeAvg": round(sum(batch_sizes) / len(batch_sizes), 2) if batch_sizes else None,
        "firstProcessedUtc": min(processed).isoformat() if processed else None,
        "lastProcessedUtc": max(processed).isoformat() if processed else None,
        "aggregatedMessagesPerSecond": round(len(rows) / span, 2) if span else None,
        "groupLatencySeconds": {
            "p50": percentile(latencies, 0.5),
            "p95": percentile(latencies, 0.95),
            "p99": percentile(latencies, 0.99),
            "max": max(latencies) if latencies else None,
        },
        "worstOrders": sorted(incomplete, key=lambda item: -(item["missing"] + item["duplicates"]))[:10],
    }
    text = json.dumps(result, indent=2)
    print(text)
    if output:
        with open(output, "w", encoding="utf-8") as handle:
            handle.write(text)


if __name__ == "__main__":
    main()
