"""Checks per-key processing order for pattern 6a from the Cosmos documents.

Each processed message wrote one document with id "<key>-<seq>", pk = key and the UTC time
the workflow processed it (processedAtUtc). For every key this script sorts the documents
by processedAtUtc and counts:

  inversions  adjacent pairs where a lower seq was processed after a higher seq
  gaps        seq numbers between 1 and the key's max seq that have no document
  redelivered documents whose deliveryCount is above 1
  ties        adjacent pairs with the same processedAtUtc (order cannot be proved)

Usage:
  python check-ordering.py <cosmos-endpoint> <startUtc> <endUtc> [output.json]

Auth uses the Azure CLI login (the deployer has Cosmos data contributor).
"""

import json
import os
import sys
from collections import defaultdict

# CLI2 Python ignores PYTHONPATH, so add the kit's library folders here.
KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
for folder in ("pylib", "pylib-cosmos"):
    sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", folder))
for name in [name for name in sys.modules if name == "azure" or name.startswith("azure.")]:
    del sys.modules[name]

from azure.cosmos import CosmosClient  # noqa: E402
from azure.identity import AzureCliCredential  # noqa: E402

PATTERN = "6a-strict-order"


def main():
    endpoint, start, end = sys.argv[1], sys.argv[2], sys.argv[3]
    output = sys.argv[4] if len(sys.argv) > 4 else None
    container = (
        CosmosClient(endpoint, AzureCliCredential())
        .get_database_client("msgpat")
        .get_container_client("items")
    )
    query = (
        "SELECT c.key, c.seq, c.processedAtUtc, c.deliveryCount, c.runId FROM c "
        "WHERE c.pattern = @pattern AND c.processedAtUtc >= @start AND c.processedAtUtc <= @end"
    )
    rows = list(
        container.query_items(
            query,
            parameters=[
                {"name": "@pattern", "value": PATTERN},
                {"name": "@start", "value": start},
                {"name": "@end", "value": end},
            ],
            enable_cross_partition_query=True,
        )
    )
    by_key = defaultdict(list)
    for row in rows:
        by_key[row["key"]].append(row)

    inversions = gaps = ties = redelivered = 0
    keys_with_inversions = []
    for key, docs in by_key.items():
        docs.sort(key=lambda doc: doc["processedAtUtc"])
        key_inversions = 0
        for previous, current in zip(docs, docs[1:]):
            if current["processedAtUtc"] == previous["processedAtUtc"]:
                ties += 1
            if int(current["seq"]) < int(previous["seq"]):
                key_inversions += 1
        seqs = {int(doc["seq"]) for doc in docs}
        gaps += max(seqs) - len(seqs)
        redelivered += sum(1 for doc in docs if int(doc.get("deliveryCount") or 1) > 1)
        inversions += key_inversions
        if key_inversions:
            keys_with_inversions.append({"key": key, "inversions": key_inversions})

    result = {
        "pattern": PATTERN,
        "windowStartUtc": start,
        "windowEndUtc": end,
        "documents": len(rows),
        "keys": len(by_key),
        "runs": len({row["runId"] for row in rows}),
        "inversions": inversions,
        "keysWithInversions": len(keys_with_inversions),
        "gaps": gaps,
        "redeliveredDocuments": redelivered,
        "processedAtTies": ties,
        "worstKeys": sorted(keys_with_inversions, key=lambda item: -item["inversions"])[:10],
    }
    text = json.dumps(result, indent=2)
    print(text)
    if output:
        with open(output, "w", encoding="utf-8") as handle:
            handle.write(text)


if __name__ == "__main__":
    main()
