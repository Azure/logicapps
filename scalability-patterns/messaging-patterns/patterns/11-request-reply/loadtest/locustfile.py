"""Locust load generator for pattern 11: HTTP request-reply over Service Bus.

Each user POSTs a ~1 KB order to the rr-front callback URL and waits for the reply.
A user sends at most one request per second, so while latency stays under 1 s the
request rate equals the user count. The stepped shape below raises the user count
in stages to find where latency or errors rise.

Environment variables (set by loadtest.yaml / Invoke-LoadTest.ps1):
  CALLBACK_URL     Signed callback URL of the rr-front Request trigger
  STAGES           Comma-separated "users:seconds" steps, e.g. "5:120,10:120"
  REQUEST_TIMEOUT  Client timeout in seconds (default 240)
  PATTERN_ID       Written into each order
"""

import os
import random
import uuid
from datetime import datetime, timezone
from urllib.parse import urlsplit

from locust import HttpUser, LoadTestShape, constant_pacing, events, task

CALLBACK_URL = os.environ["CALLBACK_URL"]
PATTERN_ID = os.environ.get("PATTERN_ID", "11-request-reply")
TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT", "240"))
STAGES = [
    (int(users), int(seconds))
    for users, seconds in (step.split(":") for step in os.environ.get("STAGES", "5:120").split(","))
]
REGIONS = ["westus", "eastus", "northeurope", "westeurope", "southeastasia"]
SKUS = ["sku-alpha", "sku-bravo", "sku-charlie", "sku-delta"]
_parts = urlsplit(CALLBACK_URL)
HOST = f"{_parts.scheme}://{_parts.netloc}"
PATH = f"{_parts.path}?{_parts.query}"


def make_order():
    """Build an order of about 1 KB."""
    return {
        "orderId": str(uuid.uuid4()),
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


def report_correlation_error(message):
    """Record a reply that does not belong to the request as a separate Locust failure."""
    events.request.fire(
        request_type="check",
        name="correlation",
        response_time=0,
        response_length=0,
        exception=AssertionError(message),
        context={},
    )


class RequestReplyCaller(HttpUser):
    host = HOST
    wait_time = constant_pacing(1)

    @task
    def call(self):
        with self.client.post(
            PATH,
            json=make_order(),
            name="rr-front",
            timeout=TIMEOUT,
            catch_response=True,
        ) as response:
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")
                return
            try:
                body = response.json()
            except ValueError:
                response.failure("Body is not JSON")
                return
            request_id = body.get("requestId")
            reply = body.get("reply") or {}
            if not request_id or (
                body.get("correlationId") != request_id or
                body.get("replySessionId") != request_id or
                reply.get("messageId") != request_id
            ):
                report_correlation_error(f"requestId '{request_id}' got correlationId '{body.get('correlationId')}'")
            response.success()


class SteppedShape(LoadTestShape):
    """Hold each "users:seconds" stage in turn, then stop."""

    def tick(self):
        elapsed = self.get_run_time()
        for users, seconds in STAGES:
            if elapsed < seconds:
                return users, max(users, 10)
            elapsed -= seconds
        return None
