"""Sends a few ~1 KB order messages to a pattern's Service Bus entity from your machine.

Use it for a smoke test after Deploy-Pattern.ps1. It signs in with the Azure CLI login,
which Deploy-Pattern.ps1 grants Azure Service Bus Data Owner on the namespace.

Usage:
  python scripts/Send-TestMessages.py --pattern 1a-max-throughput [--count 20] [--queue orders]
      [--topic name] [--sessions 0]

Requires: pip install azure-servicebus azure-identity (or the kit's .tools/pylib).
"""

import argparse
import json
import os
import random
import sys
import uuid
from datetime import datetime, timezone

KIT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

from azure.identity import AzureCliCredential  # noqa: E402
from azure.servicebus import ServiceBusClient, ServiceBusMessage  # noqa: E402
from azure.servicebus.exceptions import MessageSizeExceededError  # noqa: E402


def make_order(pattern):
    """Build an order of about 1 KB, the same shape the Locust engines send."""
    return {
        "orderId": str(uuid.uuid4()),
        "pattern": pattern,
        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
        "currency": "USD",
        "customer": {
            "id": f"cust-{random.randint(1, 50000)}",
            "firstName": "Avery",
            "lastName": "Contoso",
            "email": "avery@example.com",
            "region": random.choice(["westus", "eastus", "northeurope"]),
        },
        "item": {
            "sku": random.choice(["sku-alpha", "sku-bravo"]),
            "quantity": random.randint(1, 20),
            "unitPrice": round(random.uniform(1, 500), 2),
        },
        "lines": [{"line": n, "sku": "sku-alpha", "qty": 1, "note": "x" * 40} for n in range(6)],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pattern", required=True)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--queue")
    parser.add_argument("--topic")
    parser.add_argument("--sessions", type=int, default=0)
    args = parser.parse_args()

    pattern_dir = os.path.join(KIT_ROOT, "patterns", args.pattern)
    with open(os.path.join(pattern_dir, "params.json"), encoding="utf-8") as handle:
        load_test = json.load(handle).get("loadTest", {})
    with open(os.path.join(KIT_ROOT, "results", args.pattern, "deployment.json"), encoding="utf-8-sig") as handle:
        namespace = json.load(handle)["serviceBusFqdn"]

    topic = args.topic or load_test.get("env", {}).get("SB_TOPIC")
    queue = args.queue or (None if topic else load_test.get("queueName", "orders"))
    sessions = args.sessions or int(load_test.get("env", {}).get("SESSION_COUNT", 0))

    with ServiceBusClient(namespace, AzureCliCredential()) as client:
        sender = client.get_queue_sender(queue) if queue else client.get_topic_sender(topic)
        with sender:
            batch = sender.create_message_batch()
            for _ in range(args.count):
                order = make_order(args.pattern)
                message = ServiceBusMessage(
                    json.dumps(order),
                    content_type="application/json",
                    message_id=order["orderId"],
                    application_properties={"pattern": args.pattern},
                )
                if sessions > 0:
                    message.session_id = f"session-{random.randint(1, sessions)}"
                try:
                    batch.add_message(message)
                except MessageSizeExceededError:
                    # A Standard batch holds at most 256 KB; send it and start a new one.
                    sender.send_messages(batch)
                    batch = sender.create_message_batch()
                    batch.add_message(message)
            sender.send_messages(batch)
    print(f"Sent {args.count} messages to {namespace}/{queue or topic}.")


if __name__ == "__main__":
    main()

