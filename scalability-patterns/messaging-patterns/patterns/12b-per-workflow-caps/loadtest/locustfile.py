"""Locust load generator for mixed priority: a steady urgent stream and a bulk burst.

HighSender users send BATCH_SIZE messages per second each to SB_QUEUE_HIGH for the whole run.
LowSender users wait BURST_START_SEC, then send BURST_MESSAGES in total to SB_QUEUE_LOW as
fast as they can (LOW_BATCH_SIZE per batch), then stop sending.

If the run is shorter than twice BURST_START_SEC (a smoke run), the burst starts at a third of
the run time and sends SMOKE_BURST_MESSAGES instead.

Environment variables (set by loadtest.yaml / params.json loadTest.env):
  SB_NAMESPACE, SB_QUEUE_HIGH, SB_QUEUE_LOW, AZURE_CLIENT_ID, PATTERN_ID
  BATCH_SIZE, BATCHES_PER_USER_PER_SECOND   Urgent pacing per HighSender user
  HIGH_USERS, LOW_USERS                     Users per class (users in locust.conf must equal the sum)
  LOW_BATCH_SIZE, BURST_START_SEC, BURST_MESSAGES, SMOKE_BURST_MESSAGES
  USE_CLI_CREDENTIAL                        "1" to use the Azure CLI login (local runs only)
"""

import json
import os
import random
import time
import uuid
from datetime import datetime, timezone

from azure.identity import AzureCliCredential, ManagedIdentityCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from locust import User, constant, constant_throughput, events, task

NAMESPACE = os.environ["SB_NAMESPACE"]
QUEUE_HIGH = os.environ.get("SB_QUEUE_HIGH", "orders-high")
QUEUE_LOW = os.environ.get("SB_QUEUE_LOW", "orders-low")
PATTERN_ID = os.environ.get("PATTERN_ID", "unknown")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "2"))
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "1"))
HIGH_USERS = int(os.environ.get("HIGH_USERS", "1"))
LOW_USERS = int(os.environ.get("LOW_USERS", "5"))
LOW_BATCH_SIZE = int(os.environ.get("LOW_BATCH_SIZE", "50"))
BURST = {
    "start": float(os.environ.get("BURST_START_SEC", "180")),
    "messages": int(os.environ.get("BURST_MESSAGES", "12000")),
}
SMOKE_BURST_MESSAGES = int(os.environ.get("SMOKE_BURST_MESSAGES", "500"))
STATE = {"t0": time.time()}
REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    STATE["t0"] = time.time()
    run_time = getattr(environment.parsed_options, "run_time", None) if environment.parsed_options else None
    if run_time and run_time < 2 * BURST["start"]:
        BURST["start"] = run_time / 3
        BURST["messages"] = SMOKE_BURST_MESSAGES


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_order(priority):
    """Build an order of about 1 KB."""
    order_id = str(uuid.uuid4())
    return {
        "orderId": order_id,
        "pattern": PATTERN_ID,
        "priority": priority,
        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
        "currency": "USD",
        "customer": {
            "id": f"cust-{random.randint(1, 50000)}",
            "firstName": "Avery",
            "lastName": "Contoso",
            "email": "avery@example.com",
            "region": random.choice(REGIONS),
        },
        "item": {"sku": random.choice(SKUS), "quantity": random.randint(1, 20), "unitPrice": round(random.uniform(1, 500), 2)},
        "lines": [
            {"line": n, "sku": random.choice(SKUS), "qty": random.randint(1, 5), "note": "x" * 40}
            for n in range(6)
        ],
    }


class _Sender(User):
    abstract = True
    queue = ""
    priority = ""

    def on_start(self):
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = self.client.get_queue_sender(self.queue)

    def on_stop(self):
        self.sender.close()
        self.client.close()

    def send(self, count):
        start = time.perf_counter()
        error = None
        size = 0
        try:
            batch = self.sender.create_message_batch()
            for _ in range(count):
                order = make_order(self.priority)
                body = json.dumps(order)
                size += len(body)
                batch.add_message(ServiceBusMessage(
                    body,
                    content_type="application/json",
                    message_id=order["orderId"],
                    application_properties={"pattern": PATTERN_ID, "priority": self.priority},
                ))
            self.sender.send_messages(batch)
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_{self.queue}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )


class HighSender(_Sender):
    fixed_count = HIGH_USERS
    wait_time = constant_throughput(RATE)
    queue = QUEUE_HIGH
    priority = "high"

    @task
    def send_batch(self):
        self.send(BATCH_SIZE)


class LowSender(_Sender):
    fixed_count = LOW_USERS
    wait_time = constant(0)
    queue = QUEUE_LOW
    priority = "low"

    def on_start(self):
        super().on_start()
        self.remaining = BURST["messages"] // max(LOW_USERS, 1)

    @task
    def send_batch(self):
        if time.time() - STATE["t0"] < BURST["start"] or self.remaining <= 0:
            time.sleep(1)
            return
        count = min(LOW_BATCH_SIZE, self.remaining)
        self.send(count)
        self.remaining -= count
