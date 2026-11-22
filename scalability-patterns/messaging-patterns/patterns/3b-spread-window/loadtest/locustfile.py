"""Locust load generator for pattern 3b: sends ~1 KB JSON orders as scheduled messages.

The whole drop is sent in SEND_SECONDS, but each message gets a ScheduledEnqueueTimeUtc so
Service Bus releases the drop evenly across SPREAD_WINDOW_SECONDS after the test starts.
Send time t maps to release offset t * SPREAD_WINDOW_SECONDS / SEND_SECONDS, and the
messages of one batch are spaced evenly inside their slot.

Each Locust user sends BATCH_SIZE messages per task and runs
BATCHES_PER_USER_PER_SECOND tasks per second, so the target rate is
users x BATCH_SIZE x BATCHES_PER_USER_PER_SECOND messages per second per engine.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE                  Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE or SB_TOPIC          Destination entity (queue wins if both are set)
  AZURE_CLIENT_ID               Client ID of the engine user-assigned identity
  PATTERN_ID                    Written into each message
  BATCH_SIZE                    Messages per batch (default 10)
  BATCHES_PER_USER_PER_SECOND   Pacing per user (default 1)
  SESSION_COUNT                 If > 0, set session_id to one of N sessions (default 0)
  SPREAD_WINDOW_SECONDS         Release window length (default 600)
  SEND_SECONDS                  Planned send duration (default 60)
  USE_CLI_CREDENTIAL            "1" to use the Azure CLI login (local runs only)
"""

import json
import os
import random
import time
import uuid
from datetime import datetime, timedelta, timezone

from azure.identity import AzureCliCredential, ManagedIdentityCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from locust import User, constant_throughput, events, task

NAMESPACE = os.environ["SB_NAMESPACE"]
QUEUE = os.environ.get("SB_QUEUE", "")
TOPIC = os.environ.get("SB_TOPIC", "")
PATTERN_ID = os.environ.get("PATTERN_ID", "unknown")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "10"))
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "1"))
SESSION_COUNT = int(os.environ.get("SESSION_COUNT", "0"))
WINDOW_SECONDS = float(os.environ.get("SPREAD_WINDOW_SECONDS", "600"))
SEND_SECONDS = float(os.environ.get("SEND_SECONDS", "60"))
STRETCH = WINDOW_SECONDS / SEND_SECONDS
TEST_START = {"utc": None, "mono": None}


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    TEST_START["utc"] = datetime.now(timezone.utc)
    TEST_START["mono"] = time.monotonic()


def window_start():
    if TEST_START["utc"] is None:
        on_test_start(None)
    return TEST_START["utc"], TEST_START["mono"]


REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_order(scheduled_for):
    """Build an order of about 1 KB."""
    order_id = str(uuid.uuid4())
    return {
        "orderId": order_id,
        "pattern": PATTERN_ID,
        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
        "scheduledForUtc": scheduled_for.isoformat(),
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
            start_utc, start_mono = window_start()
            elapsed = time.monotonic() - start_mono
            slot = 1.0 / RATE
            for index in range(BATCH_SIZE):
                offset = min((elapsed + slot * index / BATCH_SIZE) * STRETCH, WINDOW_SECONDS)
                scheduled_for = start_utc + timedelta(seconds=offset)
                order = make_order(scheduled_for)
                body = json.dumps(order)
                size += len(body)
                message = ServiceBusMessage(
                    body,
                    content_type="application/json",
                    message_id=order["orderId"],
                    application_properties={"pattern": PATTERN_ID},
                    scheduled_enqueue_time_utc=scheduled_for,
                )
                if SESSION_COUNT > 0:
                    message.session_id = f"session-{random.randint(1, SESSION_COUNT)}"
                batch.add_message(message)
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
