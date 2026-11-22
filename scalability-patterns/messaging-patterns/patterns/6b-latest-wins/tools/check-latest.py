"""Checks pattern 6b (latest wins per key) from the Cosmos documents.

Each processed message wrote one arrival document (docType "arrival", id
"arr-<key>-<seq>") with the time the For each iteration started (arrivedAtUtc) and the
outcome of the conditional write: created, applied, stale or retry (the Until loop ran
out of attempts). Each key also has one "latest-<key>" document that the workflow only
replaces when the incoming seq is newer, using the document's ETag as If-Match.

For the arrivals in the window this script counts:

  outOfOrderArrivals  arrivals whose seq is lower than a seq already seen for the key
  outcomes            created / applied / stale / retry counts
  etagRetries         extra attempts spent after an ETag (412) or create (409) conflict
  gaps                seq numbers between 1 and the key's max seq with no arrival
  latestMismatches    keys whose latest document does not hold the key's max seq

Usage:
  python check-latest.py <cosmos-endpoint> <startUtc> <endUtc> [output.json]

Auth uses the Azure CLI login (the deployer has Cosmos data contributor).
"""

import json
import os
import sys
from collections import Counter, defaultdict

# CLI2 Python ignores PYTHONPATH, so add the kit's library folders here.
KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
for folder in ("pylib", "pylib-cosmos"):
    sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", folder))
for name in [name for name in sys.modules if name == "azure" or name.startswith("azure.")]:
    del sys.modules[name]

from azure.cosmos import CosmosClient  # noqa: E402
from azure.identity import AzureCliCredential  # noqa: E402

PATTERN = "6b-latest-wins"


def query(container, text, parameters):
    return list(container.query_items(text, parameters=parameters, enable_cross_partition_query=True))


def main():
    endpoint, start, end = sys.argv[1], sys.argv[2], sys.argv[3]
    output = sys.argv[4] if len(sys.argv) > 4 else None
    container = (
        CosmosClient(endpoint, AzureCliCredential())
        .get_database_client("msgpat")
        .get_container_client("items")
    )
    arrivals = query(
        container,
        "SELECT c.key, c.seq, c.arrivedAtUtc, c.outcome, c.attempts, c.deliveryCount, c.runId FROM c "
        "WHERE c.pattern = @pattern AND c.docType = 'arrival' "
        "AND c.processedAtUtc >= @start AND c.processedAtUtc <= @end",
        [{"name": "@pattern", "value": PATTERN}, {"name": "@start", "value": start}, {"name": "@end", "value": end}],
    )
    latest = {
        doc["key"]: int(doc["seq"])
        for doc in query(
            container,
            "SELECT c.key, c.seq FROM c WHERE c.pattern = @pattern AND c.docType = 'latest'",
            [{"name": "@pattern", "value": PATTERN}],
        )
    }

    by_key = defaultdict(list)
    for row in arrivals:
        by_key[row["key"]].append(row)

    out_of_order = gaps = redelivered = 0
    mismatches = []
    for key, docs in by_key.items():
        docs.sort(key=lambda doc: doc["arrivedAtUtc"])
        highest = 0
        for doc in docs:
            seq = int(doc["seq"])
            if seq < highest:
                out_of_order += 1
            highest = max(highest, seq)
        seqs = {int(doc["seq"]) for doc in docs}
        gaps += max(seqs) - len(seqs)
        redelivered += sum(1 for doc in docs if int(doc.get("deliveryCount") or 1) > 1)
        if latest.get(key) != max(seqs):
            mismatches.append({"key": key, "latestSeq": latest.get(key), "maxSeq": max(seqs)})

    outcomes = Counter(row.get("outcome") or "none" for row in arrivals)
    retries = sum(max(int(row.get("attempts") or 1) - 1, 0) for row in arrivals)
    result = {
        "pattern": PATTERN,
        "windowStartUtc": start,
        "windowEndUtc": end,
        "arrivals": len(arrivals),
        "keys": len(by_key),
        "runs": len({row["runId"] for row in arrivals}),
        "outOfOrderArrivals": out_of_order,
        "outcomes": dict(outcomes),
        "staleWritesSkipped": outcomes.get("stale", 0),
        "etagRetries": retries,
        "maxAttempts": max((int(row.get("attempts") or 1) for row in arrivals), default=0),
        "gaps": gaps,
        "redeliveredArrivals": redelivered,
        "latestMismatches": len(mismatches),
        "mismatchSamples": mismatches[:10],
    }
    text = json.dumps(result, indent=2)
    print(text)
    if output:
        with open(output, "w", encoding="utf-8") as handle:
            handle.write(text)


if __name__ == "__main__":
    main()
