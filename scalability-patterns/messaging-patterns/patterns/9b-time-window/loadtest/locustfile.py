"""Locust generator for pattern 9b (fan-in, time window): sends single items to a queue.

Each task sends BATCH_SIZE independent item messages in one Service Bus batch. Each item
carries itemId = <runTag>-<user>-<seq>, where seq counts from 1 per Locust user with no
gaps, so check-windows.py can find missing items from gaps in each user's sequence and
duplicates from repeated ids across window documents in Cosmos.

Target rate = users x BATCH_SIZE x BATCHES_PER_USER_PER_SECOND messages per second.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE                  Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE                      Destination queue
  AZURE_CLIENT_ID               Client ID of the engine user-assigned identity
  PATTERN_ID                    Written into each message
  BATCHES_PER_USER_PER_SECOND   Batches per user per second (default 0.2)
  BATCH_SIZE                    Items per batch (default 10)
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
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "0.2"))
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "10"))

# A short tag per engine process keeps items from different runs apart in Cosmos.
RUN_TAG = uuid.uuid4().hex[:6]
USER_COUNTER = itertools.count(1)


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_item_message(item_id):
    """Build one item message of about 1 KB."""
    body = json.dumps(
        {
            "itemId": item_id,
            "pattern": PATTERN_ID,
            "sentAtUtc": datetime.now(timezone.utc).isoformat(),
            "amount": round(random.uniform(1, 500), 2),
            "note": "x" * 800,
        }
    )
    return ServiceBusMessage(
        body,
        content_type="application/json",
        message_id=item_id,
        application_properties={"pattern": PATTERN_ID},
    )


class ItemSender(User):
    wait_time = constant_throughput(RATE)

    def on_start(self):
        self.user_no = next(USER_COUNTER)
        self.seq = 0
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = self.client.get_queue_sender(QUEUE)

    def on_stop(self):
        self.sender.close()
        self.client.close()

    @task
    def send_items(self):
        start = time.perf_counter()
        error = None
        size = 0
        try:
            batch = self.sender.create_message_batch()
            first_seq = self.seq
            for _ in range(BATCH_SIZE):
                self.seq += 1
                message = make_item_message(f"{RUN_TAG}-{self.user_no}-{self.seq}")
                size += len(str(message))
                batch.add_message(message)
            try:
                self.sender.send_messages(batch)
            except Exception:
                # A failed batch was not sent; reuse its sequence numbers so gaps mean loss.
                self.seq = first_seq
                raise
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_items_{QUEUE}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )
