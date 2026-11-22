"""Draws PNG charts from a results run folder written by Export-Results.ps1.

Usage:
    python scripts/New-Charts.py results/<pattern>/<runId>

Charts (each is skipped if its CSV is missing):
    throughput.png       workflow runs completed per minute, succeeded and failed
    run-latency.png      workflow run duration p50/p95/p99 per minute
    e2e-latency.png      send-to-completion latency p50/p95/p99 per minute
    queue-backlog.png    Service Bus active messages, incoming and completed per minute
    instances.png        Logic App instances reporting telemetry per minute
    failures.png         failed runs, failed actions, failed triggers and exceptions per minute
"""

import csv
import json
import os
import sys
from datetime import datetime

# The Azure CLI Python ignores PYTHONPATH (it has a ._pth file), so add the kit's library folder here.
KIT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402


def read_csv(folder, name):
    path = os.path.join(folder, name + ".csv")
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def parse_time(value):
    value = value.strip().replace("Z", "+00:00")
    if "." in value:
        head, tail = value.split(".", 1)
        offset = ""
        for sign in ("+", "-"):
            if sign in tail:
                fraction, offset = tail.split(sign, 1)
                offset = sign + offset
                break
        else:
            fraction = tail
        value = head + "." + fraction[:6] + offset
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        # Older exports wrote PowerShell's en-US format, for example '11/22/2026 6:17:00 AM' (UTC).
        return datetime.strptime(value, "%m/%d/%Y %I:%M:%S %p")


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def series(rows, column):
    return [number(row.get(column)) for row in rows]


def save(figure, axis, folder, name, title, ylabel, subtitle):
    axis.set_title(title)
    axis.set_ylabel(ylabel)
    axis.set_xlabel("Time (UTC)")
    axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axis.grid(True, alpha=0.3)
    axis.legend(loc="best")
    figure.suptitle(subtitle, fontsize=9, y=0.995)
    figure.autofmt_xdate()
    figure.tight_layout()
    path = os.path.join(folder, name + ".png")
    figure.savefig(path, dpi=120)
    plt.close(figure)
    print("wrote " + path)


def line_chart(folder, rows, name, title, ylabel, columns, subtitle, time_column="minute"):
    if not rows:
        return
    rows = sorted(rows, key=lambda row: row[time_column])
    times = [parse_time(row[time_column]) for row in rows]
    figure, axis = plt.subplots(figsize=(10, 4.5))
    for column, label in columns:
        if column in rows[0]:
            axis.plot(times, series(rows, column), marker=".", label=label)
    save(figure, axis, folder, name, title, ylabel, subtitle)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    folder = sys.argv[1]
    subtitle = os.path.basename(os.path.normpath(folder))
    summary_path = os.path.join(folder, "summary.json")
    if os.path.exists(summary_path):
        with open(summary_path, encoding="utf-8-sig") as handle:
            summary = json.load(handle)
        subtitle = "{} | {} | target {} msg/s".format(
            summary.get("pattern"), summary.get("runId"), summary.get("targetMessagesPerSecond"))

    line_chart(folder, read_csv(folder, "runs-per-minute"), "throughput", "Workflow runs completed per minute",
               "runs / minute", [("runs", "completed"), ("succeeded", "succeeded"), ("failed", "failed")], subtitle)

    duration_rows = read_csv(folder, "run-duration-percentiles")
    workflows = sorted({row["workflowName"] for row in duration_rows})
    if duration_rows:
        figure, axis = plt.subplots(figsize=(10, 4.5))
        for workflow in workflows:
            rows = sorted((row for row in duration_rows if row["workflowName"] == workflow), key=lambda row: row["minute"])
            times = [parse_time(row["minute"]) for row in rows]
            for column in ("p50", "p95", "p99"):
                axis.plot(times, series(rows, column), marker=".", label="{} {}".format(workflow, column))
        save(figure, axis, folder, "run-latency", "Workflow run duration", "milliseconds", subtitle)

    line_chart(folder, read_csv(folder, "end-to-end-latency"), "e2e-latency",
               "End-to-end latency (sent by Locust to process-order finished)", "milliseconds",
               [("p50", "p50"), ("p95", "p95"), ("p99", "p99")], subtitle)

    bus_rows = read_csv(folder, "servicebus-metrics")
    if bus_rows:
        figure, (top, bottom) = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
        for entity in sorted({row["entity"] for row in bus_rows}):
            rows = sorted((row for row in bus_rows if row["entity"] == entity), key=lambda row: row["minute"])
            times = [parse_time(row["minute"]) for row in rows]
            top.plot(times, series(rows, "activeMessages"), marker=".", label=entity + " active (max)")
            bottom.plot(times, series(rows, "incomingMessages"), marker=".", label=entity + " incoming")
            bottom.plot(times, series(rows, "completeMessages"), marker=".", label=entity + " completed")
        top.set_title("Service Bus backlog")
        top.set_ylabel("messages")
        top.grid(True, alpha=0.3)
        top.legend(loc="best")
        save(figure, bottom, folder, "queue-backlog", "Service Bus messages per minute", "messages / minute", subtitle)

    line_chart(folder, read_csv(folder, "instances-per-minute"), "instances", "Logic App instances",
               "instances", [("instances", "instances")], subtitle)

    line_chart(folder, read_csv(folder, "failures"), "failures", "Failures per minute", "count",
               [("failedRuns", "failed runs"), ("failedActions", "failed actions"),
                ("failedTriggers", "failed triggers"), ("exceptions", "exceptions")], subtitle)


if __name__ == "__main__":
    main()
