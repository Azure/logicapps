"""Locust ramp generator: sends ~1 KB JSON order messages to Service Bus at a rate that
steps up and down, so the batch trigger's fixed release rate is tested above and below
its limit.

Load shape (RampShape): STEPS is a comma-separated list of users:seconds pairs, run in
order. Each user sends BATCH_SIZE messages per task and runs BATCHES_PER_USER_PER_SECOND
tasks per second, so a step's rate is users x BATCH_SIZE x BATCHES_PER_USER_PER_SECOND
messages per second per engine. The default steps give 10, 30, 50, 100, 150, 100, 50 and
10 messages per second over 15 minutes. The shape overrides users, spawn-rate and
run-time in locust.conf.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE                  Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE or SB_TOPIC          Destination entity (queue wins if both are set)
  AZURE_CLIENT_ID               Client ID of the engine user-assigned identity
  PATTERN_ID                    Written into each message
  BATCH_SIZE                    Messages per batch (default 10)
  BATCHES_PER_USER_PER_SECOND   Pacing per user (default 1)
  STEPS                         Load shape, users:seconds pairs (see above)
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
from locust import LoadTestShape, User, constant_throughput, events, task

NAMESPACE = os.environ["SB_NAMESPACE"]
QUEUE = os.environ.get("SB_QUEUE", "")
TOPIC = os.environ.get("SB_TOPIC", "")
PATTERN_ID = os.environ.get("PATTERN_ID", "unknown")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "10"))
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "1"))
STEPS = [
    (int(users), int(seconds))
    for users, seconds in (
        step.split(":")
        for step in os.environ.get(
            "STEPS", "1:60,3:120,5:60,10:120,15:180,10:120,5:120,1:120"
        ).split(",")
    )
]

REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_order():
    """Build an order of about 1 KB."""
    order_id = str(uuid.uuid4())
    return {
        "orderId": order_id,
        "pattern": PATTERN_ID,
        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
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
            "quantity": random.randint(1, 20),
            "unitPrice": round(random.uniform(1, 500), 2),
        },
        "lines": [
            {"line": n, "sku": random.choice(SKUS), "qty": random.randint(1, 5), "note": "x" * 40}
            for n in range(6)
        ],
    }


class ServiceBusSender(User):
    wait_time = constant_throughput(RATE)

    def on_start(self):
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = (
            self.client.get_queue_sender(QUEUE) if QUEUE else self.client.get_topic_sender(TOPIC)
        )
        self.entity = QUEUE or TOPIC

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
                order = make_order()
                body = json.dumps(order)
                size += len(body)
                batch.add_message(
                    ServiceBusMessage(
                        body,
                        content_type="application/json",
                        message_id=order["orderId"],
                        application_properties={"pattern": PATTERN_ID},
                    )
                )
            self.sender.send_messages(batch)
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_batch_{self.entity}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )


class RampShape(LoadTestShape):
    """Runs each users:seconds step in turn. Returns None to stop the test."""

    def tick(self):
        elapsed = self.get_run_time()
        for users, seconds in STEPS:
            if elapsed < seconds:
                return (users, max(users, 1))
            elapsed -= seconds
        return None