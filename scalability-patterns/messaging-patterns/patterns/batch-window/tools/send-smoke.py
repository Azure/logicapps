"""Sends a few test orders for the batch-window pattern from your machine (smoke tests only).

Uses the Azure CLI login and the same message shape as the Locust test.

Usage:
  python send-smoke.py <namespace-fqdn> [--count 40] [--queue orders]
"""

import argparse
import os
import sys
import types

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

# Locust is installed only in the load-test engine; stub it so the message builder imports.
_stub = types.ModuleType("locust")
_stub.User = object
_stub.constant_throughput = lambda rate: None
_stub.events = None
_stub.task = lambda function: function
sys.modules["locust"] = _stub


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("namespace")
    parser.add_argument("--count", type=int, default=40)
    parser.add_argument("--queue", default="orders")
    args = parser.parse_args()
    os.environ.setdefault("SB_NAMESPACE", args.namespace)
    os.environ.setdefault("SB_QUEUE", args.queue)
    os.environ.setdefault("PATTERN_ID", "batch-window")
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "loadtest"))

    import json

    from azure.identity import AzureCliCredential
    from azure.servicebus import ServiceBusClient, ServiceBusMessage
    from locustfile import make_order

    with ServiceBusClient(args.namespace, AzureCliCredential()) as client:
        with client.get_queue_sender(args.queue) as sender:
            messages = []
            for _ in range(args.count):
                order = make_order()
                messages.append(
                    ServiceBusMessage(
                        json.dumps(order),
                        content_type="application/json",
                        message_id=order["orderId"],
                    )
                )

            sender.send_messages(messages)

    print(f"Sent {args.count} messages to {args.queue}.")


if __name__ == "__main__":
    main()
