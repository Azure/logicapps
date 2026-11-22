"""Sends ordered test messages for pattern 6 from your machine (smoke tests only).

Sends --keys keys x --per-key messages. Each key's seq starts at 1, and the script sends
the keys round-robin so the broker receives every key in sequence order, the same shape
the Locust engines send. Uses the Azure CLI login.

Usage:
  python send-ordered.py <namespace-fqdn> <pattern-id> [--keys 20] [--per-key 10]
      [--queue orders] [--sessions 1]
"""

import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

from azure.identity import AzureCliCredential  # noqa: E402
from azure.servicebus import ServiceBusClient, ServiceBusMessage  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("namespace")
    parser.add_argument("pattern")
    parser.add_argument("--keys", type=int, default=20)
    parser.add_argument("--per-key", type=int, default=10)
    parser.add_argument("--queue", default="orders")
    parser.add_argument("--sessions", type=int, default=1)
    args = parser.parse_args()
    tag = uuid.uuid4().hex[:6]
    keys = [f"{tag}-k{n:03d}" for n in range(args.keys)]
    with ServiceBusClient(args.namespace, AzureCliCredential()) as client:
        with client.get_queue_sender(args.queue) as sender:
            batch = sender.create_message_batch()
            for seq in range(1, args.per_key + 1):
                for key in keys:
                    body = {
                        "orderId": str(uuid.uuid4()),
                        "key": key,
                        "seq": seq,
                        "pattern": args.pattern,
                        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
                        "note": "x" * 700,
                    }
                    message = ServiceBusMessage(
                        json.dumps(body),
                        content_type="application/json",
                        message_id=body["orderId"],
                        application_properties={"pattern": args.pattern, "key": key, "seq": seq},
                    )
                    if args.sessions:
                        message.session_id = key
                    try:
                        batch.add_message(message)
                    except ValueError:
                        sender.send_messages(batch)
                        batch = sender.create_message_batch()
                        batch.add_message(message)
            sender.send_messages(batch)
    print(f"Sent {args.keys * args.per_key} messages, run tag {tag}.")


if __name__ == "__main__":
    main()
