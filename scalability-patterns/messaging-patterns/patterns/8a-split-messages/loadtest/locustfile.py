"""Locust load generator for pattern 8 (fan out): each message is one envelope with N items.

Each Locust user sends BATCH_SIZE envelopes per task and runs BATCHES_PER_USER_PER_SECOND
tasks per second. Each envelope carries ITEMS_PER_MESSAGE items, so the item rate is
users x BATCH_SIZE x BATCHES_PER_USER_PER_SECOND x ITEMS_PER_MESSAGE per engine.

About BAD_ITEM_PERCENT % of items get quantity "bad". The shared order.liquid map writes
quantity unquoted, so these items make the process-order child return 500. Use them to
compare failure isolation between 8a (one run per item) and 8b (one run per envelope).

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE                  Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE                      Destination queue
  AZURE_CLIENT_ID               Client ID of the engine user-assigned identity
  PATTERN_ID                    Written into each envelope and item
  BATCH_SIZE                    Envelopes per Service Bus batch (default 1)
  BATCHES_PER_USER_PER_SECOND   Pacing per user (default 1)
  ITEMS_PER_MESSAGE             Items per envelope, at most 100 (default 50)
  BAD_ITEM_PERCENT              Percent of items made invalid (default 4)
  USE_CLI_CREDENTIAL            "1" to use the Azure CLI login (local runs only)
"""

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
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "1"))
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "1"))
ITEMS_PER_MESSAGE = min(int(os.environ.get("ITEMS_PER_MESSAGE", "50")), 100)
BAD_ITEM_PERCENT = float(os.environ.get("BAD_ITEM_PERCENT", "4"))
REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_item(batch_id, index, sent_at):
    """Build one item of about 350 bytes. Bad items carry quantity "bad"."""
    bad = random.random() * 100 < BAD_ITEM_PERCENT
    item_id = f"{batch_id}-{index:03d}"
    return {
        "itemId": item_id,
        "orderId": item_id,
        "batchId": batch_id,
        "pattern": PATTERN_ID,
        "sentAtUtc": sent_at,
        "currency": "USD",
        "customer": {
            "id": f"cust-{random.randint(1, 50000)}",
            "firstName": "Avery",
            "lastName": "Contoso",
            "email": "avery@example.com",
            "region": random.choice(REGIONS),
        },
        "item": {
            "sku": random.choice(SKUS),
            "quantity": "bad" if bad else random.randint(1, 20),
            "unitPrice": round(random.uniform(1, 500), 2),
        },
        "lines": [],
    }


def make_envelope():
    batch_id = str(uuid.uuid4())
    sent_at = datetime.now(timezone.utc).isoformat()
    items = [make_item(batch_id, n, sent_at) for n in range(ITEMS_PER_MESSAGE)]
    return {"batchId": batch_id, "pattern": PATTERN_ID, "sentAtUtc": sent_at, "items": items}


class ServiceBusSender(User):
    wait_time = constant_throughput(RATE)

    def on_start(self):
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = self.client.get_queue_sender(QUEUE)

    def on_stop(self):
        self.sender.close()
        self.client.close()

    @task
    def send_batch(self):
        start = time.perf_counter()
        error = None
        size = 0
        try:
            batch = self.sender.create_message_batch()
            for _ in range(BATCH_SIZE):
                envelope = make_envelope()
                bad = sum(1 for item in envelope["items"] if item["item"]["quantity"] == "bad")
                body = json.dumps(envelope)
                size += len(body)
                batch.add_message(
                    ServiceBusMessage(
                        body,
                        content_type="application/json",
                        message_id=envelope["batchId"],
                        application_properties={
                            "pattern": PATTERN_ID,
                            "itemCount": ITEMS_PER_MESSAGE,
                            "badItemCount": bad,
                        },
                    )
                )
            self.sender.send_messages(batch)
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_envelope_{QUEUE}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )
