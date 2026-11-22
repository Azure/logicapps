"""Checks window completeness for pattern 9b in Cosmos.

Reads every window document (docType = window) written between <startUtc> and <endUtc>,
expands their item lists and reports:
  - windows, items per window, receive calls per window
  - duplicate items (the same itemId in more than one window, or twice in one window)
  - missing items: gaps in each sender's sequence <tag>-<user>-<seq> (1..max seen),
    plus, with --expected N, the difference between N and the distinct items found
  - lag from an item's send time to the window write (p50/p95/max), and from the first
    item of each window to its write
  - aggregated items per second over the span of window writes

Usage:
  python check-windows.py <cosmos-endpoint> <startUtc> <endUtc> [out.json] [--expected N]
"""

import json
import os
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
for folder in ("pylib", "pylib-cosmos"):
    sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", folder))

from azure.cosmos import CosmosClient  # noqa: E402
from azure.identity import AzureCliCredential  # noqa: E402


def parse_time(value):
    text = value.replace("Z", "+00:00")
    if "." in text:
        head, rest = text.split(".", 1)
        digits = "".join(ch for ch in rest if ch.isdigit())
        zone = rest[len(digits):]
        text = f"{head}.{digits[:6]}{zone}"
    return datetime.fromisoformat(text)


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def summary(values):
    return {
        "count": len(values),
        "p50": percentile(values, 0.5),
        "p95": percentile(values, 0.95),
        "max": max(values) if values else None,
        "mean": round(statistics.mean(values), 2) if values else None,
    }


def main():
    args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    expected = None
    if "--expected" in sys.argv:
        expected = int(sys.argv[sys.argv.index("--expected") + 1])
        args = [arg for arg in args if arg != str(expected)]
    endpoint, start_utc, end_utc = args[0], args[1], args[2]
    out_path = args[3] if len(args) > 3 else None

    client = CosmosClient(endpoint, AzureCliCredential())
    container = client.get_database_client("msgpat").get_container_client("items")
    query = (
        "SELECT * FROM c WHERE c.docType = 'window' AND c.pattern = '9b-time-window' "
        "AND c.writtenAtUtc >= @start AND c.writtenAtUtc <= @end"
    )
    windows = list(
        container.query_items(
            query,
            parameters=[{"name": "@start", "value": start_utc}, {"name": "@end", "value": end_utc}],
            enable_cross_partition_query=True,
        )
    )

    occurrences = Counter()
    by_sender = defaultdict(set)
    item_lag = []
    window_lag = []
    window_sizes = []
    receive_calls = []
    redelivered = 0
    write_times = []
    for window in windows:
        written = parse_time(window["writtenAtUtc"])
        write_times.append(written)
        items = window.get("items") or []
        window_sizes.append(len(items))
        receive_calls.append(window.get("receiveCalls"))
        sent_times = []
        for item in items:
            item_id = item.get("itemId") or ""
            occurrences[item_id] += 1
            parts = item_id.rsplit("-", 2)
            if len(parts) == 3 and parts[2].isdigit():
                by_sender[f"{parts[0]}-{parts[1]}"].add(int(parts[2]))
            if (item.get("deliveryCount") or 1) > 1:
                redelivered += 1
            if item.get("sentAtUtc"):
                sent = parse_time(item["sentAtUtc"])
                sent_times.append(sent)
                item_lag.append((written - sent).total_seconds())
        if sent_times:
            window_lag.append((written - min(sent_times)).total_seconds())

    duplicates = {item_id: count for item_id, count in occurrences.items() if count > 1}
    gaps = 0
    gap_examples = []
    for sender, sequence in by_sender.items():
        for missing in set(range(1, max(sequence) + 1)) - sequence:
            gaps += 1
            if len(gap_examples) < 20:
                gap_examples.append(f"{sender}-{missing}")

    span = (max(write_times) - min(write_times)).total_seconds() if len(write_times) > 1 else None
    distinct = len(occurrences)
    result = {
        "startUtc": start_utc,
        "endUtc": end_utc,
        "windows": len(windows),
        "itemsTotal": sum(window_sizes),
        "distinctItems": distinct,
        "expectedItems": expected,
        "missingVsExpected": (expected - distinct) if expected is not None else None,
        "sequenceGaps": gaps,
        "gapExamples": gap_examples,
        "duplicateItems": len(duplicates),
        "duplicateExamples": dict(list(duplicates.items())[:20]),
        "redeliveredItems": redelivered,
        "senders": len(by_sender),
        "itemsPerWindow": summary(window_sizes),
        "receiveCallsPerWindow": summary([value for value in receive_calls if value is not None]),
        "itemSendToWindowWriteSeconds": summary(item_lag),
        "firstItemToWindowWriteSeconds": summary(window_lag),
        "firstWriteUtc": min(write_times).isoformat() if write_times else None,
        "lastWriteUtc": max(write_times).isoformat() if write_times else None,
        "aggregatedItemsPerSecondOverWriteSpan": round(distinct / span, 2) if span else None,
    }
    text = json.dumps(result, indent=2)
    print(text)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as handle:
            handle.write(text)


if __name__ == "__main__":
    main()
