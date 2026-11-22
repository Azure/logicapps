"""Sends test orders for pattern 9a from your machine (smoke tests only).

Sends --orders orders of --lines line messages, session_id = orderId, using the Azure CLI
login and the same message shape as the Locust test.

Usage:
  python send-orders.py <namespace-fqdn> [--orders 10] [--lines 10] [--queue orders]
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
    parser.add_argument("--orders", type=int, default=10)
    parser.add_argument("--lines", type=int, default=10)
    parser.add_argument("--queue", default="orders")
    args = parser.parse_args()
    os.environ.setdefault("SB_NAMESPACE", args.namespace)
    os.environ.setdefault("SB_QUEUE", args.queue)
    os.environ.setdefault("PATTERN_ID", "9a-group-by-key")

    # Locust is installed only in the load-test engine; stub it so the message builder imports.
    import types

    stub = types.ModuleType("locust")
    stub.User = object
    stub.constant_throughput = lambda rate: None
    stub.events = None
    stub.task = lambda function: function
    sys.modules.setdefault("locust", stub)
    from locustfile import make_order_messages  # noqa: E402

    tag = uuid.uuid4().hex[:6]
    with ServiceBusClient(args.namespace, AzureCliCredential()) as client:
        with client.get_queue_sender(args.queue) as sender:
            for number in range(args.orders):
                sender.send_messages(make_order_messages(f"{tag}-o{number:03d}", args.lines))
    print(f"Sent {args.orders} orders x {args.lines} lines to '{args.queue}', tag {tag}.")


if __name__ == "__main__":
    main()
