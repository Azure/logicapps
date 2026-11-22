"""Locust generator for pattern 9a (fan-in, group by key): sends whole orders as line messages.

Each task sends one order as LINE_COUNT messages in one batch. Every line message carries
session_id = orderId, so all lines of one order go to the same Service Bus session, plus
lineNo (1..LINE_COUNT), lineCount and the order's first send time (sentAtUtc). The
consumer must collect all LINE_COUNT lines of each order; check-groups.py verifies that in
Cosmos.

Each user sends one order per task and runs BATCHES_PER_USER_PER_SECOND tasks per second,
so the target rate is users x LINE_COUNT x BATCHES_PER_USER_PER_SECOND messages per
second. BATCH_SIZE is ignored; set it to LINE_COUNT in params.json so the kit's rate
arithmetic matches.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE                  Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE                      Destination queue (session-enabled)
  AZURE_CLIENT_ID               Client ID of the engine user-assigned identity
  PATTERN_ID                    Written into each message
  BATCHES_PER_USER_PER_SECOND   Orders per user per second (default 0.25)
  LINE_COUNT                    Line messages per order (default 10)
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
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "0.25"))
LINE_COUNT = int(os.environ.get("LINE_COUNT", "10"))

# A short tag per test run keeps orders from different runs apart in Cosmos.
RUN_TAG = uuid.uuid4().hex[:6]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_order_messages(order_id, line_count):
    """Build the line messages of one order, each about 1 KB."""
    sent_at = datetime.now(timezone.utc).isoformat()
    messages = []
    for line_no in range(1, line_count + 1):
        body = json.dumps(
            {
                "orderId": order_id,
                "lineNo": line_no,
                "lineCount": line_count,
                "pattern": PATTERN_ID,
                "sentAtUtc": sent_at,
                "amount": round(random.uniform(1, 500), 2),
                "item": {"sku": random.choice(SKUS), "quantity": random.randint(1, 20)},
                "note": "x" * 800,
            }
        )
        messages.append(
            ServiceBusMessage(
                body,
                content_type="application/json",
                message_id=f"{order_id}-{line_no}",
                session_id=order_id,
                application_properties={"pattern": PATTERN_ID, "orderId": order_id, "lineNo": line_no},
            )
        )
    return messages


class OrderSender(User):
    wait_time = constant_throughput(RATE)

    def on_start(self):
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = self.client.get_queue_sender(QUEUE)

    def on_stop(self):
        self.sender.close()
        self.client.close()

    @task
    def send_order(self):
        start = time.perf_counter()
        error = None
        size = 0
        try:
            order_id = f"{RUN_TAG}-{uuid.uuid4().hex[:12]}"
            batch = self.sender.create_message_batch()
            for message in make_order_messages(order_id, LINE_COUNT):
                size += len(str(message))
                batch.add_message(message)
            self.sender.send_messages(batch)
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"send_order_{QUEUE}",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=size,
            exception=error,
            context={},
        )
