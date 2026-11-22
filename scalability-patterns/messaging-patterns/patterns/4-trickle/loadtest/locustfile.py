"""Locust load generator for pattern 4-trickle: low, irregular traffic with an idle gap.

One Locust user sends one ~1 KB order message, waits a random MIN_WAIT_SECONDS..MAX_WAIT_SECONDS,
and repeats. After IDLE_GAP_START_SECONDS it pauses once for IDLE_GAP_SECONDS, so the run captures
the first message after a long idle period. Each send goes to SB_QUEUE (stateful workflow) and,
when set, SB_QUEUE2 (stateless workflow). Both copies carry the same sentAtUtc and the same
sequence number, with distinct message IDs, so the two workflows see identical arrival times.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1 / params.loadTest.env):
  SB_NAMESPACE              Fully qualified namespace, e.g. sb-x.servicebus.windows.net
  SB_QUEUE                  First destination queue
  SB_QUEUE2                 Optional second destination queue
  AZURE_CLIENT_ID           Client ID of the engine user-assigned identity
  PATTERN_ID                Written into each message
  MIN_WAIT_SECONDS          Shortest pause between sends (default 1)
  MAX_WAIT_SECONDS          Longest pause between sends (default 30)
  IDLE_GAP_START_SECONDS    Seconds after start before the idle gap (default 240; 0 disables)
  IDLE_GAP_SECONDS          Length of the idle gap (default 360)
  USE_CLI_CREDENTIAL        "1" to use the Azure CLI login (local runs only)
"""

import json
import os
import random
import time
import uuid
from datetime import datetime, timezone

from azure.identity import AzureCliCredential, ManagedIdentityCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from locust import User, between, events, task

NAMESPACE = os.environ["SB_NAMESPACE"]
QUEUES = [q for q in (os.environ.get("SB_QUEUE", ""), os.environ.get("SB_QUEUE2", "")) if q]
PATTERN_ID = os.environ.get("PATTERN_ID", "unknown")
MIN_WAIT = float(os.environ.get("MIN_WAIT_SECONDS", "1"))
MAX_WAIT = float(os.environ.get("MAX_WAIT_SECONDS", "30"))
GAP_START = float(os.environ.get("IDLE_GAP_START_SECONDS", "240"))
GAP_LENGTH = float(os.environ.get("IDLE_GAP_SECONDS", "360"))
REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_order(sent_at, sequence):
    """Build an order of about 1 KB."""
    return {
        "orderId": str(uuid.uuid4()),
        "pattern": PATTERN_ID,
        "sentAtUtc": sent_at,
        "sequence": sequence,
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


class TrickleSender(User):
    wait_time = between(MIN_WAIT, MAX_WAIT)

    def on_start(self):
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.senders = {queue: self.client.get_queue_sender(queue) for queue in QUEUES}
        self.started = time.monotonic()
        self.gap_done = GAP_START <= 0
        self.sequence = 0

    def on_stop(self):
        for sender in self.senders.values():
            sender.close()
        self.client.close()

    @task
    def send_one(self):
        if not self.gap_done and time.monotonic() - self.started >= GAP_START:
            self.gap_done = True
            time.sleep(GAP_LENGTH)
        self.sequence += 1
        sent_at = datetime.now(timezone.utc).isoformat()
        for queue, sender in self.senders.items():
            start = time.perf_counter()
            error = None
            order = make_order(sent_at, self.sequence)
            body = json.dumps(order)
            try:
                sender.send_messages(
                    ServiceBusMessage(
                        body,
                        content_type="application/json",
                        message_id=order["orderId"],
                        application_properties={"pattern": PATTERN_ID, "sequence": self.sequence},
                    )
                )
            except Exception as ex:  # report every failure to Locust
                error = ex
            events.request.fire(
                request_type="servicebus",
                name=f"send_{queue}",
                response_time=(time.perf_counter() - start) * 1000,
                response_length=len(body),
                exception=error,
                context={},
            )
