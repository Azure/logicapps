"""Draws the steady-drain chart for one batch-steady-drain run.

Usage:
    python patterns/batch-steady-drain/tools/New-DrainChart.py <runFolder> <outputPng>

Panels share the time axis (UTC):
    1. Incoming rate (Service Bus incoming msg/s) vs. rate into the batch store and processing rate.
    2. Backlog: Service Bus active messages, ingress runs waiting, and messages held in the batch store.
    3. Release size: messages started by each once-a-second release, with the 200 cap.
    4. Logic App instances.
    5. Plan CPU and memory (%).

Inputs: servicebus-metrics.csv, instances-per-minute.csv and plan-metrics.csv from the kit
export scripts, and custom/timeline-per-minute.json and custom/timeline-per-second.json
from Run-Queries.ps1.
"""

import csv
import json
import os
import sys
from datetime import datetime

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

RELEASE_CAP = 200


def parse_time(value):
    """Parses an ISO 8601 UTC timestamp."""
    text = value.replace("Z", "").split(".")[0]
    return datetime.strptime(text, "%Y-%m-%dT%H:%M:%S")


def read_csv(path):
    """Reads a CSV file, or returns an empty list when it is missing."""
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def read_json(path):
    """Reads a JSON file, or returns an empty list when it is missing."""
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig") as handle:
        return json.load(handle)


def number(value):
    """Converts an export value to float, treating blanks as zero."""
    try:
        return float(value) if value not in (None, "") else 0.0
    except ValueError:
        return 0.0


def main():
    run_folder, output = sys.argv[1], sys.argv[2]
    sb_rows = read_csv(os.path.join(run_folder, "servicebus-metrics.csv"))
    plan_rows = read_csv(os.path.join(run_folder, "plan-metrics.csv"))
    minutes = read_json(os.path.join(run_folder, "custom", "timeline-per-minute.json"))
    seconds = read_json(os.path.join(run_folder, "custom", "timeline-per-second.json"))

    sb_time = [parse_time(row["minute"]) for row in sb_rows]
    sb_incoming = [number(row["incomingMessages"]) / 60 for row in sb_rows]
    sb_active = [number(row["activeMessages"]) for row in sb_rows]
    sb_completed = [number(row["completeMessages"]) for row in sb_rows]

    minute_time = [parse_time(row["minute"]) for row in minutes]
    pushed = [number(row.get("pushed")) for row in minutes]
    processed = [number(row.get("processed")) for row in minutes]
    instances = [number(row.get("instances")) for row in minutes]

    # NOTE(rohithah): Ingress completes the Service Bus message before Send_to_batch finishes, so the
    # backlog moves from the queue into waiting ingress runs and then into the batch store.
    completed_by_minute = dict(zip(sb_time, sb_completed))
    waiting_ingress, batch_store = [], []
    completed_total = pushed_total = processed_total = 0.0
    for when, push, done in zip(minute_time, pushed, processed):
        completed_total += completed_by_minute.get(when, 0.0)
        pushed_total += push
        processed_total += done
        waiting_ingress.append(max(completed_total - pushed_total, 0.0))
        batch_store.append(max(pushed_total - processed_total, 0.0))

    release_time = [parse_time(row["s"]) for row in seconds if number(row.get("started")) > 0]
    release_size = [number(row["started"]) for row in seconds if number(row.get("started")) > 0]

    plan_time = [parse_time(row["minute"]) for row in plan_rows]
    cpu = [number(row["cpuMax"]) for row in plan_rows]
    memory = [number(row["memoryMax"]) for row in plan_rows]

    figure, axes = plt.subplots(5, 1, figsize=(12, 15), sharex=True)
    figure.suptitle("batch-steady-drain: 60,800-message burst, release every 1 s (cap 200)", fontsize=13)

    axes[0].plot(sb_time, sb_incoming, color="#D83B01", label="Incoming to queue (msg/s)")
    axes[0].plot(minute_time, [value / 60 for value in pushed], color="#5C2D91", label="Into batch store (msg/s)")
    axes[0].plot(minute_time, [value / 60 for value in processed], color="#107C10", linewidth=2, label="Processed (msg/s)")
    axes[0].axhline(RELEASE_CAP, color="grey", linestyle="--", linewidth=1, label="Release cap (200 msg/s)")
    axes[0].set_yscale("symlog", linthresh=1)
    axes[0].set_ylim(0, 1000)
    axes[0].set_ylabel("msg/s (log)")
    axes[0].legend(loc="upper right", fontsize=8)
    axes[0].set_title("Incoming rate vs. processing rate (per-minute average)", fontsize=10)

    axes[1].stackplot(
        minute_time,
        [dict(zip(sb_time, sb_active)).get(when, 0.0) for when in minute_time],
        waiting_ingress,
        batch_store,
        colors=["#0078D4", "#FFB900", "#5C2D91"],
        labels=["Service Bus active", "Waiting in ingress runs", "Held in batch store"],
        alpha=0.8,
    )
    axes[1].set_ylabel("messages")
    axes[1].legend(loc="upper left", fontsize=8)
    axes[1].set_title("Backlog (not yet processed)", fontsize=10)

    axes[2].bar(release_time, release_size, width=1 / 86400 * 20, color="#107C10")
    axes[2].axhline(RELEASE_CAP, color="grey", linestyle="--", linewidth=1, label="messageCountLimit 200")
    axes[2].set_ylabel("messages")
    axes[2].legend(loc="upper right", fontsize=8)
    axes[2].set_title("Release size (messages started per second)", fontsize=10)

    axes[3].step(minute_time, instances, where="post", color="#0078D4")
    axes[3].set_ylim(0, 5.5)
    axes[3].set_ylabel("instances")
    axes[3].set_title("Logic App instances (plan max 5)", fontsize=10)

    axes[4].plot(plan_time, cpu, color="#D83B01", label="CPU max %")
    axes[4].plot(plan_time, memory, color="#0078D4", label="Memory max %")
    axes[4].set_ylim(0, 105)
    axes[4].set_ylabel("%")
    axes[4].legend(loc="lower right", fontsize=8)
    axes[4].set_title("Plan CPU and memory", fontsize=10)

    axes[4].xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axes[4].set_xlabel("UTC")
    for axis in axes:
        axis.grid(alpha=0.3)
    figure.tight_layout(rect=(0, 0, 1, 0.97))
    figure.savefig(output, dpi=110)
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
