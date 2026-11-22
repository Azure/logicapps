"""Locust generator for pattern 6 (ordered per key): sends ~1 KB JSON order updates.

Each message belongs to one key (an order id) and carries a per-key sequence number that
starts at 1 and increases by one. Each Locust user owns a disjoint set of keys and sends
them in round-robin order, one batch at a time, so the broker receives every key's
messages in sequence order. Any reordering seen downstream comes from the consumer.

Each user sends BATCH_SIZE messages per task and runs BATCHES_PER_USER_PER_SECOND tasks
per second, so the target rate is users x BATCH_SIZE x BATCHES_PER_USER_PER_SECOND
messages per second. Run with one engine: key ownership is per process.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE                  Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE                      Destination queue
  AZURE_CLIENT_ID               Client ID of the engine user-assigned identity
  PATTERN_ID                    Written into each message
  BATCH_SIZE                    Messages per batch (default 10)
  BATCHES_PER_USER_PER_SECOND   Pacing per user (default 1)
  KEY_COUNT                     Number of keys across all users (default 100)
  TOTAL_USERS                   Users in the test; must match locust.conf (default 20)
  USE_SESSIONS                  "1" to set session_id = key (6a); "0" for 6b (default here)
  USE_CLI_CREDENTIAL            "1" to use the Azure CLI login (local runs only)
"""

import itertools
import json
import os
import random
import time
import uuid
from datetime import datetime, timezone

from azure.identity import AzureCliCredential, ManagedIdentityCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from locust import User, constant_throughput, events, task

NAMESPACE = os.environ["SB_NAMESPACE"]
QUEUE = os.environ["SB_QUEUE"]
PATTERN_ID = os.environ.get("PATTERN_ID", "unknown")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "10"))
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "1"))
KEY_COUNT = int(os.environ.get("KEY_COUNT", "100"))
TOTAL_USERS = int(os.environ.get("TOTAL_USERS", "20"))
USE_SESSIONS = os.environ.get("USE_SESSIONS", "0") == "1"

# A short tag per test run keeps keys from different runs apart in Cosmos.
RUN_TAG = uuid.uuid4().hex[:6]
USER_INDEX = itertools.count()
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_update(key, seq):
    """Build an order update of about 1 KB."""
    return {
        "orderId": str(uuid.uuid4()),
        "key": key,
        "seq": seq,
        "pattern": PATTERN_ID,
        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
        "status": random.choice(["created", "paid", "packed", "shipped"]),
        "item": {"sku": random.choice(SKUS), "quantity": random.randint(1, 20)},
        "lines": [
            {"line": n, "sku": random.choice(SKUS), "qty": random.randint(1, 5), "note": "x" * 60}
            for n in range(8)
        ],
    }


class OrderedSender(User):
    wait_time = constant_throughput(RATE)

    def on_start(self):
        index = next(USER_INDEX) % TOTAL_USERS
        self.keys = [f"{RUN_TAG}-k{n:03d}" for n in range(index, KEY_COUNT, TOTAL_USERS)]
        self.seq = {key: 0 for key in self.keys}
        self.cursor = 0
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = self.client.get_queue_sender(QUEUE)

    def on_stop(self):
        self.sender.close()
        self.client.close()

    @task
    def send_batch(self):
        if not self.keys:
            return
        start = time.perf_counter()
        error = None
        size = 0
        try:
            batch = self.sender.create_message_batch()
            for _ in range(BATCH_SIZE):
                key = self.keys[self.cursor % len(self.keys)]
                self.cursor += 1
                self.seq[key] += 1
                update = make_update(key, self.seq[key])
                body = json.dumps(update)
                size += len(body)
                message = ServiceBusMessage(
                    body,
                    content_type="application/json",
                    message_id=update["orderId"],
                    application_properties={"pattern": PATTERN_ID, "key": key, "seq": self.seq[key]},
                )
                if USE_SESSIONS:
                    message.session_id = key
                batch.add_message(message)
            self.sender.send_messages(batch)
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_batch_{QUEUE}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )
