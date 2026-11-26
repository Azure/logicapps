"""Draws the child-type comparison charts from the CSVs in this folder."""
import csv
import os
import sys
from collections import defaultdict
from datetime import datetime

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
A_END = datetime(2026, 11, 26, 0, 12)
B_START = datetime(2026, 11, 25, 23, 20)
LABELS = {
    "orders-stateless-child": "A parent (stateless child)",
    "process-order": "A child (stateless)",
    "orders-stateful-child": "B parent (stateful child)",
    "process-order-stateful": "B child (stateful)",
}
COLORS = {
    "orders-stateless-child": "tab:blue",
    "process-order": "tab:cyan",
    "orders-stateful-child": "tab:red",
    "process-order-stateful": "tab:orange",
}


def parse_time(value):
    try:
        return datetime.strptime(value, "%m/%d/%Y %I:%M:%S %p")
    except ValueError:
        return datetime.fromisoformat(value.replace("Z", "").split(".")[0].split("+")[0])


def read(name):
    with open(os.path.join(HERE, name), newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def series(rows, value_column, group_column="wf"):
    grouped = defaultdict(list)
    for row in rows:
        if row.get(value_column) in (None, ""):
            continue
        grouped[row.get(group_column, "all")].append((parse_time(row["minute"]), float(row[value_column])))
    for key in grouped:
        grouped[key].sort()
    return grouped


def finish(axis, title, ylabel, path):
    axis.set_title(title)
    axis.set_ylabel(ylabel)
    axis.set_xlabel("UTC")
    axis.axvspan(B_START, A_END, color="grey", alpha=0.12, label="A and B overlap")
    axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axis.grid(alpha=0.3)
    axis.legend(fontsize=8)
    axis.figure.autofmt_xdate()
    axis.figure.tight_layout()
    axis.figure.savefig(os.path.join(OUT, path), dpi=110)
    plt.close(axis.figure)


def line_chart(data, keys, title, ylabel, path, scale=1.0):
    _, axis = plt.subplots(figsize=(10, 4.5))
    for key in keys:
        if key in data:
            times, values = zip(*data[key])
            axis.plot(times, [value * scale for value in values], label=LABELS.get(key, key), color=COLORS.get(key))
    finish(axis, title, ylabel, path)


ends = series(read("run-ends-per-minute.csv"), "ends")
line_chart(ends, ["orders-stateless-child", "orders-stateful-child", "process-order", "process-order-stateful"],
           "Completed runs per second", "runs/s", "processing-rate.png", scale=1 / 60)

latency = read("e2e-latency-per-minute.csv")
_, axis = plt.subplots(figsize=(10, 4.5))
for key, data in (("p50", series(latency, "p50")), ("p95", series(latency, "p95"))):
    for workflow in ("orders-stateless-child", "orders-stateful-child"):
        if workflow in data:
            times, values = zip(*data[workflow])
            axis.plot(times, values, label=f"{LABELS[workflow]} {key}", color=COLORS[workflow],
                      linestyle="-" if key == "p50" else "--")
finish(axis, "End-to-end latency (send to last tracked action)", "seconds", "e2e-latency.png")

durations = series(read("run-duration-per-minute.csv"), "p50")
line_chart(durations, ["process-order", "process-order-stateful"], "Child run duration p50", "seconds",
           "child-run-duration.png")

instances = series(read("instances-per-minute.csv"), "instances", group_column="none")
line_chart(instances, ["all"], "App instances reporting telemetry", "instances", "instances.png")

plan = read("plan-metrics.csv")
_, axis = plt.subplots(figsize=(10, 4.5))
for metric, color in (("CpuPercentage", "tab:green"), ("MemoryPercentage", "tab:purple")):
    points = sorted((parse_time(row["minute"]), float(row[metric])) for row in plan if row.get(metric))
    if points:
        times, values = zip(*points)
        axis.plot(times, values, label=metric, color=color)
finish(axis, "Plan CPU and memory (average)", "percent", "cpu-memory.png")

storage = read("storage-transactions.csv")
points = sorted((parse_time(row["minute"]), float(row["transactions"])) for row in storage if row.get("transactions"))
if points:
    _, axis = plt.subplots(figsize=(10, 4.5))
    times, values = zip(*points)
    axis.plot(times, values, label="Transactions per minute", color="tab:brown")
    finish(axis, "Storage account transactions", "transactions/min", "storage-transactions.png")
