"""Purges a pattern's Service Bus queue (and its dead-letter queue) from your machine.

The kit has no queue reset script, so this sample carries one. It signs in with the
Azure CLI login, which Deploy-Pattern.ps1 grants Azure Service Bus Data Owner.
Stop the Logic App first if you do not want it to keep receiving.

Usage:
  python patterns/batch-trickle/tools/Clear-Queue.py --pattern batch-trickle [--queue orders]
"""

import argparse
import json
import os
import sys

KIT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

from azure.identity import AzureCliCredential  # noqa: E402
from azure.servicebus import ServiceBusClient, ServiceBusReceiveMode, ServiceBusSubQueue  # noqa: E402


def drain(client, queue, sub_queue):
    """Receives and deletes messages until the queue is empty."""
    total = 0
    with client.get_queue_receiver(
        queue_name=queue, sub_queue=sub_queue, receive_mode=ServiceBusReceiveMode.RECEIVE_AND_DELETE
    ) as receiver:
        while True:
            batch = receiver.receive_messages(max_message_count=500, max_wait_time=5)
            if not batch:
                return total
            total += len(batch)
            if total % 5000 < len(batch):
                print(f"  removed {total}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pattern", required=True)
    parser.add_argument("--queue", default="orders")
    args = parser.parse_args()
    with open(os.path.join(KIT_ROOT, "results", args.pattern, "deployment.json"), encoding="utf-8-sig") as handle:
        namespace = json.load(handle)["serviceBusFqdn"]
    with ServiceBusClient(namespace, AzureCliCredential()) as client:
        active = drain(client, args.queue, None)
        dead = drain(client, args.queue, ServiceBusSubQueue.DEAD_LETTER)
    print(f"Removed {active} active and {dead} dead-letter messages from '{args.queue}'.")


if __name__ == "__main__":
    main()
