"""Sends test items for pattern 9b from your machine (smoke tests only).

Sends --items item messages, using the Azure CLI login and the same message shape as the
Locust test. Item ids are <tag>-1-<seq>, so check-windows.py treats them as one user.

Usage:
  python send-items.py <namespace-fqdn> [--items 100] [--queue items]
"""

import argparse
import os
import sys
import uuid

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "loadtest"))

from azure.identity import AzureCliCredential  # noqa: E402
from azure.servicebus import ServiceBusClient  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("namespace")
    parser.add_argument("--items", type=int, default=100)
    parser.add_argument("--queue", default="items")
    args = parser.parse_args()
    os.environ.setdefault("SB_NAMESPACE", args.namespace)
    os.environ.setdefault("SB_QUEUE", args.queue)
    os.environ.setdefault("PATTERN_ID", "9b-time-window")

    # Locust is installed only in the load-test engine; stub it so the message builder imports.
    import types

    stub = types.ModuleType("locust")
    stub.User = object
    stub.constant_throughput = lambda rate: None
    stub.events = None
    stub.task = lambda function: function
    sys.modules.setdefault("locust", stub)
    from locustfile import make_item_message  # noqa: E402

    tag = uuid.uuid4().hex[:6]
    with ServiceBusClient(args.namespace, AzureCliCredential()) as client:
        with client.get_queue_sender(args.queue) as sender:
            batch = []
            for seq in range(1, args.items + 1):
                batch.append(make_item_message(f"{tag}-1-{seq}"))
                if len(batch) == 10:
                    sender.send_messages(batch)
                    batch = []
            if batch:
                sender.send_messages(batch)
    print(f"Sent {args.items} items to '{args.queue}', tag {tag}.")


if __name__ == "__main__":
    main()
