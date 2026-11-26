"""Draws the charts for one limit-concurrent-runs run.

Usage:
    python patterns/limit-concurrent-runs/tools/New-LimitCharts.py <runFolder>

Writes these files into the run folder:
    concurrency.png             Runs in flight each second, with the limit of 10.
    incoming-vs-processing.png  Service Bus incoming msg/min, runs ended per minute and queue backlog.
    instances-cpu-memory.png    Logic App instances and plan CPU and memory (%).

Inputs: servicebus-metrics.csv, runs-per-minute.csv, instances-per-minute.csv and plan-metrics.csv
from the kit export scripts, and custom/concurrency-per-second.json from Run-Queries.ps1.
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

LIMIT = 10


def parse_time(value):
    """Parses an ISO 8601 UTC timestamp."""
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def read_csv(folder, name):
    """Reads a CSV file from the run folder."""
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def number(value):
    """Converts a CSV cell to a float, treating blanks as zero."""
    return float(value) if value not in (None, "") else 0.0


def format_axis(axis):
    """Applies the shared time-axis format."""
    axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axis.grid(alpha=0.3)


def main():
    folder = sys.argv[1]

    with open(os.path.join(folder, "custom", "concurrency-per-second.json"), encoding="utf-8-sig") as handle:
        seconds = json.load(handle)
    sec_times = [parse_time(row["sec"]) for row in seconds]
    in_flight = [row["appInFlight"] for row in seconds]
    fig, axis = plt.subplots(figsize=(11, 4))
    axis.step(sec_times, in_flight, where="post", label="Runs in flight (app)")
    axis.axhline(LIMIT, color="red", linestyle="--", label=f"Limit ({LIMIT})")
    axis.set_ylim(0, LIMIT + 4)
    axis.set_ylabel("Runs in flight")
    axis.set_title("Concurrent runs per second (exact start/end sweep)")
    axis.legend(loc="upper right")
    format_axis(axis)
    fig.tight_layout()
    fig.savefig(os.path.join(folder, "concurrency.png"), dpi=110)
    plt.close(fig)

    bus = [row for row in read_csv(folder, "servicebus-metrics.csv") if row["entity"] == "orders"]
    runs = read_csv(folder, "runs-per-minute.csv")
    fig, (top, bottom) = plt.subplots(2, 1, figsize=(11, 7), sharex=True)
    top.plot([parse_time(row["minute"]) for row in bus], [number(row["incomingMessages"]) for row in bus],
             marker=".", label="Incoming (Service Bus msg/min)")
    top.plot([parse_time(row["minute"]) for row in runs], [number(row["runs"]) for row in runs],
             marker=".", label="Processed (runs ended/min)")
    top.set_ylabel("Per minute")
    top.set_title("Incoming vs processing rate")
    top.legend()
    format_axis(top)
    bottom.plot([parse_time(row["minute"]) for row in bus], [number(row["activeMessages"]) for row in bus],
                color="tab:purple", label="Active messages")
    bottom.set_ylabel("Queue backlog")
    bottom.legend()
    format_axis(bottom)
    fig.tight_layout()
    fig.savefig(os.path.join(folder, "incoming-vs-processing.png"), dpi=110)
    plt.close(fig)

    instances = read_csv(folder, "instances-per-minute.csv")
    plan = read_csv(folder, "plan-metrics.csv")
    plan_times = [parse_time(row["minute"]) for row in plan]
    fig, (top, bottom) = plt.subplots(2, 1, figsize=(11, 7), sharex=True)
    top.step([parse_time(row["minute"]) for row in instances], [number(row["instances"]) for row in instances],
             where="post", label="Instances")
    top.set_ylim(0, 4)
    top.set_ylabel("Instances")
    top.set_title("Logic App instances")
    format_axis(top)
    bottom.plot(plan_times, [number(row["cpuAvg"]) for row in plan], label="CPU avg %")
    bottom.plot(plan_times, [number(row["cpuMax"]) for row in plan], linestyle=":", label="CPU max %")
    bottom.plot(plan_times, [number(row["memoryAvg"]) for row in plan], label="Memory avg %")
    bottom.set_ylim(0, 100)
    bottom.set_ylabel("Percent")
    bottom.set_title("Plan CPU and memory")
    bottom.legend()
    format_axis(bottom)
    fig.tight_layout()
    fig.savefig(os.path.join(folder, "instances-cpu-memory.png"), dpi=110)
    plt.close(fig)


if __name__ == "__main__":
    main()
