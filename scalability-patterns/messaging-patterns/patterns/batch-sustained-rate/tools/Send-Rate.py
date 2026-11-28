"""Sends ~1 KB orders to a Service Bus queue at fixed rates for a schedule of phases.

Usage:
  python Send-Rate.py --namespace <fqdn> --schedule warm:200:300,steady:1000:900,stretch:2000:600
      [--processes 16] [--queue orders] [--pattern runa] [--log phases.json]

Each process paces its share of the rate in 100 ms ticks and stamps sentAtUtc just before
sending. The parent refreshes the Azure CLI token into a file that workers read.
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from multiprocessing import Process, Value

KIT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))
sys.path.insert(0, os.path.join(KIT_ROOT, "scripts"))

TICK = 0.1
MAX_BATCH_BYTES = 240 * 1024


class FileCredential:
    """Reads the token the parent keeps fresh in a JSON file."""

    def __init__(self, path):
        self.path = path

    def get_token(self, *scopes, **kwargs):
        from azure.core.credentials import AccessToken
        with open(self.path, encoding="utf-8") as handle:
            data = json.load(handle)
        return AccessToken(data["token"], data["expires_on"])


def write_token(path):
    from azure.identity import AzureCliCredential
    access = AzureCliCredential(process_timeout=60).get_token("https://servicebus.azure.net/.default")
    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump({"token": access.token, "expires_on": access.expires_on}, handle)
    os.replace(temp, path)


def worker(namespace, queue, pattern, schedule, share, start_at, sent, token_path):
    from azure.servicebus import ServiceBusClient, ServiceBusMessage
    from importlib import import_module

    make_order = import_module("Send-TestMessages").make_order
    with ServiceBusClient(namespace, FileCredential(token_path)) as client, client.get_queue_sender(queue) as sender:
        while time.time() < start_at:
            time.sleep(0.01)
        phase_start = start_at
        for _, rate, seconds in schedule:
            per_second = rate * share
            phase_end = phase_start + seconds
            done = 0
            while True:
                now = time.time()
                if now >= phase_end:
                    break
                target = int(per_second * (now - phase_start))
                deficit = min(target - done, int(per_second) + 1)
                if deficit > 0:
                    batch = sender.create_message_batch(max_size_in_bytes=MAX_BATCH_BYTES)
                    added = 0
                    while added < deficit:
                        order = make_order(pattern)
                        message = ServiceBusMessage(
                            json.dumps(order),
                            content_type="application/json",
                            message_id=order["orderId"],
                            application_properties={"pattern": pattern},
                        )
                        try:
                            batch.add_message(message)
                        except ValueError:
                            break
                        added += 1
                    sender.send_messages(batch)
                    done += added
                    with sent.get_lock():
                        sent.value += added
                else:
                    time.sleep(max(0.0, min(TICK, phase_end - time.time())))
            phase_start = phase_end


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--schedule", required=True)
    parser.add_argument("--processes", type=int, default=16)
    parser.add_argument("--queue", default="orders")
    parser.add_argument("--pattern", default="runa")
    parser.add_argument("--log", default="phases.json")
    args = parser.parse_args()

    schedule = []
    for item in args.schedule.split(","):
        name, rate, seconds = item.split(":")
        schedule.append((name, float(rate), float(seconds)))

    token_path = os.path.abspath(args.log + ".token")
    write_token(token_path)
    sent = Value("q", 0)
    start_at = time.time() + 5
    workers = [
        Process(target=worker, args=(args.namespace, args.queue, args.pattern, schedule, 1.0 / args.processes, start_at, sent, token_path))
        for _ in range(args.processes)
    ]
    for process in workers:
        process.start()

    phases = []
    boundary = start_at
    for name, rate, seconds in schedule:
        phases.append({"name": name, "rate": rate, "startUtc": datetime.fromtimestamp(boundary, timezone.utc).isoformat(),
                       "endUtc": datetime.fromtimestamp(boundary + seconds, timezone.utc).isoformat()})
        boundary += seconds

    last_refresh = time.time()
    last_report = time.time()
    last_sent = 0
    phase_index = 0
    phase_counts = {}
    while any(process.is_alive() for process in workers):
        time.sleep(1)
        now = time.time()
        if now - last_refresh > 1800:
            try:
                write_token(token_path)
                last_refresh = now
            except Exception as ex:  # keep sending with the old token and retry next second
                print(f"token refresh failed: {ex}", flush=True)
        elapsed = now - start_at
        cumulative = 0
        current = None
        for name, rate, seconds in schedule:
            if elapsed < cumulative + seconds:
                current = name
                break
            cumulative += seconds
        if now - last_report >= 10:
            value = sent.value
            print(f"{datetime.now(timezone.utc).isoformat()} phase={current} sent={value:,} rate10s={(value - last_sent) / (now - last_report):,.0f}/s", flush=True)
            if current:
                phase_counts.setdefault(current, 0)
            last_sent = value
            last_report = now

    failed = [process.exitcode for process in workers if process.exitcode]
    total = sent.value
    with open(args.log, "w", encoding="utf-8") as handle:
        json.dump({"phases": phases, "totalSent": total, "failedWorkers": len(failed)}, handle, indent=2)
    os.remove(token_path)
    print(f"Done: {total:,} sent; failed workers {len(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
