"""Fills a pattern's Service Bus queue with a large backlog before a scale-out test.

Each worker process has its own client and sends full batches of ~1 KB orders, the same
shape as Send-TestMessages.py. It signs in with the Azure CLI login.

Usage:
  python scripts/Preload-Queue.py --pattern 1a-max-throughput --count 2000000 [--processes 16]
      [--queue orders] [--namespace <fqdn>]

Requires: pip install azure-servicebus azure-identity (or the kit's .tools/pylib).
"""

import argparse
import json
import os
import sys
import time
from multiprocessing import Process, Value

KIT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


MAX_BATCH_BYTES = 240 * 1024


class StaticCredential:
    """Returns a token fetched once by the parent, so workers do not each start the Azure CLI."""

    def __init__(self, token, expires_on):
        self.token = token
        self.expires_on = expires_on

    def get_token(self, *scopes, **kwargs):
        from azure.core.credentials import AccessToken
        return AccessToken(self.token, self.expires_on)


def send(namespace, queue, pattern, count, sent, token, expires_on):
    """Sends count messages in full batches and adds each batch to the shared counter."""
    from azure.servicebus import ServiceBusClient, ServiceBusMessage
    from importlib import import_module

    make_order = import_module("Send-TestMessages").make_order
    remaining = count
    with ServiceBusClient(namespace, StaticCredential(token, expires_on)) as client, client.get_queue_sender(queue) as sender:
        while remaining > 0:
            batch = sender.create_message_batch(max_size_in_bytes=MAX_BATCH_BYTES)
            added = 0
            while added < remaining:
                order = make_order(pattern)
                message = ServiceBusMessage(
                    json.dumps(order),
                    content_type="application/json",
                    message_id=order["orderId"],
                    application_properties={"pattern": pattern},
                )
                try:
                    batch.add_message(message)
                except ValueError:
                    break
                added += 1
            sender.send_messages(batch)
            remaining -= added
            with sent.get_lock():
                sent.value += added


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pattern", required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--processes", type=int, default=16)
    parser.add_argument("--queue", default="orders")
    parser.add_argument("--namespace")
    args = parser.parse_args()

    namespace = args.namespace
    if not namespace:
        with open(os.path.join(KIT_ROOT, "results", args.pattern, "deployment.json"), encoding="utf-8-sig") as handle:
            namespace = json.load(handle)["serviceBusFqdn"]

    from azure.identity import AzureCliCredential
    access = AzureCliCredential(process_timeout=60).get_token("https://servicebus.azure.net/.default")
    sent = Value("q", 0)
    share, extra = divmod(args.count, args.processes)
    workers = [
        Process(target=send, args=(namespace, args.queue, args.pattern, share + (1 if index < extra else 0), sent, access.token, access.expires_on))
        for index in range(args.processes)
    ]
    started = time.time()
    for worker in workers:
        worker.start()
    while any(worker.is_alive() for worker in workers):
        time.sleep(10)
        elapsed = time.time() - started
        print(f"{sent.value:,} sent in {elapsed:,.0f} s ({sent.value / elapsed:,.0f} msg/s)", flush=True)
    for worker in workers:
        worker.join()
    failed = [worker.exitcode for worker in workers if worker.exitcode]
    print(f"Done: {sent.value:,} of {args.count:,} sent to {namespace}/{args.queue}.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
