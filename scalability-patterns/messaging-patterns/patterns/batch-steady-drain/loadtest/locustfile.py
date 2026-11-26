"""Locust burst generator: sends ~1 KB JSON order messages to Service Bus in a spike.

Load shape (BurstShape, shared by patterns 2a and 2b so their charts line up):
  1. Baseline: BASELINE_USERS users for BASELINE_SECONDS, each sending
     BASELINE_BATCH_SIZE messages per task (a low, steady trickle).
  2. Burst: BURST_USERS users for BURST_SECONDS, each sending BATCH_SIZE messages
     per task. Burst rate = BURST_USERS x BATCH_SIZE x BATCHES_PER_USER_PER_SECOND.
  3. Quiet: 0 users for QUIET_SECONDS, then the test stops. The queue drains afterwards.
The shape overrides users, spawn-rate and run-time in locust.conf.

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
  BASELINE_USERS, BASELINE_SECONDS, BASELINE_BATCH_SIZE, BURST_USERS, BURST_SECONDS,
  QUIET_SECONDS                 Load shape (see above)
  SESSION_COUNT                 If > 0, set session_id to one of N sessions (default 0)
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
SESSION_COUNT = int(os.environ.get("SESSION_COUNT", "0"))
BASELINE_USERS = int(os.environ.get("BASELINE_USERS", "1"))
BASELINE_SECONDS = int(os.environ.get("BASELINE_SECONDS", "60"))
BASELINE_BATCH_SIZE = int(os.environ.get("BASELINE_BATCH_SIZE", "5"))
BURST_USERS = int(os.environ.get("BURST_USERS", "5"))
BURST_SECONDS = int(os.environ.get("BURST_SECONDS", "120"))
QUIET_SECONDS = int(os.environ.get("QUIET_SECONDS", "60"))

# Test start time, recorded on every process (master and workers) so the phase is
# known even when the shape runs on a different process.
STARTED = {"at": time.time()}


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    STARTED["at"] = time.time()


def current_phase():
    elapsed = time.time() - STARTED["at"]
    if elapsed < BASELINE_SECONDS:
        return "baseline"
    if elapsed < BASELINE_SECONDS + BURST_SECONDS:
        return "burst"
    return "quiet"
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
        phase = current_phase()
        try:
            batch = self.sender.create_message_batch()
            count = BASELINE_BATCH_SIZE if phase == "baseline" else BATCH_SIZE
            for _ in range(count):
                order = make_order()
                body = json.dumps(order)
                size += len(body)
                message = ServiceBusMessage(
                    body,
                    content_type="application/json",
                    message_id=order["orderId"],
                    application_properties={"pattern": PATTERN_ID},
                )
                if SESSION_COUNT > 0:
                    message.session_id = f"session-{random.randint(1, SESSION_COUNT)}"
                batch.add_message(message)
            self.sender.send_messages(batch)
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_batch_{self.entity}_{phase}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )


class BurstShape(LoadTestShape):
    """Baseline trickle, then a short burst, then quiet. Returns None to stop the test."""

    def tick(self):
        elapsed = self.get_run_time()
        if elapsed < BASELINE_SECONDS:
            return (BASELINE_USERS, BASELINE_USERS)
        if elapsed < BASELINE_SECONDS + BURST_SECONDS:
            return (BURST_USERS, BURST_USERS)
        if elapsed < BASELINE_SECONDS + BURST_SECONDS + QUIET_SECONDS:
            return (0, BURST_USERS)
        return None

