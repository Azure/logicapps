"""Locust load generator for 5a-claim-check.

Each task builds one large JSON order (sizes rotate through PAYLOAD_SIZES_KB),
uploads it to Blob Storage, then sends a small Service Bus message that holds
only the blob reference. Both calls use the engine's user-assigned identity.
The reported response time covers the upload plus the send.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  SB_NAMESPACE, SB_QUEUE, AZURE_CLIENT_ID, PATTERN_ID, BATCHES_PER_USER_PER_SECOND
  PAYLOAD_SIZES_KB   Comma-separated payload sizes in KB (default 1024,2560,5120)
  BLOB_ACCOUNT       Storage account name (setup.ps1 writes it into params.json)
  BLOB_CONTAINER     Container for claim blobs (default claims)
  USE_CLI_CREDENTIAL "1" to use the Azure CLI login (local runs only)
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
from azure.storage.blob import BlobServiceClient, ContentSettings
from locust import User, constant_throughput, events, task

NAMESPACE = os.environ["SB_NAMESPACE"]
QUEUE = os.environ.get("SB_QUEUE", "orders")
PATTERN_ID = os.environ.get("PATTERN_ID", "unknown")
RATE = float(os.environ.get("BATCHES_PER_USER_PER_SECOND", "1"))
SIZES_KB = [int(size) for size in os.environ.get("PAYLOAD_SIZES_KB", "1024,2560,5120").split(",")]
REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]
_size_counter = itertools.count()


def make_credential():
    if os.environ.get("USE_CLI_CREDENTIAL") == "1":
        return AzureCliCredential()
    return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])


def make_order(size_kb):
    """Build an order whose JSON body is about size_kb kilobytes."""
    order = {
        "orderId": str(uuid.uuid4()),
        "pattern": PATTERN_ID,
        "sentAtUtc": datetime.now(timezone.utc).isoformat(),
        "payloadKb": size_kb,
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
        "lines": [],
    }
    line_template = {"line": 0, "sku": "sku-alpha", "qty": 1, "note": "x" * 80}
    line_bytes = len(json.dumps(line_template)) + 2
    count = max(1, (size_kb * 1024 - len(json.dumps(order))) // line_bytes)
    order["lines"] = [
        {"line": n, "sku": SKUS[n % len(SKUS)], "qty": 1 + n % 5, "note": "x" * 80} for n in range(count)
    ]
    return order


def next_size_kb():
    return SIZES_KB[next(_size_counter) % len(SIZES_KB)]

BLOB_ACCOUNT = os.environ["BLOB_ACCOUNT"]
BLOB_CONTAINER = os.environ.get("BLOB_CONTAINER", "claims")


class ClaimCheckSender(User):
    wait_time = constant_throughput(RATE)

    def on_start(self):
        self.credential = make_credential()
        self.client = ServiceBusClient(NAMESPACE, self.credential)
        self.sender = self.client.get_queue_sender(QUEUE)
        self.blobs = BlobServiceClient(f"https://{BLOB_ACCOUNT}.blob.core.windows.net", credential=self.credential)
        self.container = self.blobs.get_container_client(BLOB_CONTAINER)

    def on_stop(self):
        self.sender.close()
        self.client.close()
        self.blobs.close()

    @task
    def send_claim(self):
        size_kb = next_size_kb()
        order = make_order(size_kb)
        body = json.dumps(order)
        blob_name = f"{order['orderId']}.json"
        start = time.perf_counter()
        error = None
        try:
            self.container.upload_blob(
                blob_name,
                body.encode("utf-8"),
                overwrite=True,
                content_settings=ContentSettings(content_type="application/json"),
            )
            claim = {
                "orderId": order["orderId"],
                "container": BLOB_CONTAINER,
                "blobName": blob_name,
                "sizeBytes": len(body),
                "payloadKb": size_kb,
                "sentAtUtc": order["sentAtUtc"],
                "pattern": PATTERN_ID,
            }
            self.sender.send_messages(
                ServiceBusMessage(
                    json.dumps(claim),
                    content_type="application/json",
                    message_id=order["orderId"],
                    application_properties={"pattern": PATTERN_ID, "payloadKb": size_kb},
                )
            )
        except Exception as ex:  # report every failure to Locust
            error = ex
        events.request.fire(
            request_type="servicebus",
            name=f"claim_{size_kb}kb",
            response_time=(time.perf_counter() - start) * 1000,
            response_length=len(body),
            exception=error,
            context={},
        )
