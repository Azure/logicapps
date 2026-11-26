"""Draws design A (trigger concurrency) and design B (batch trigger) side by side.

Usage:
    python tools/New-ComparisonCharts.py <runFolderA> <runFolderB> <outputPng>

Each column is one run. Rows share their y-axis so the two columns compare directly.
The time axis is minutes since the first message reached the run's queue.
    1. Process_order actions that ended, averaged per second over 30-second buckets (empty buckets count as zero).
    2. Active messages in the run's queue (backlog) each minute.
    3. Design A: runs in flight each second. Design B: items per batch release, averaged
       over each 10 seconds, with process-batch-item runs in flight on the right axis.
    4. Logic App instances that reported telemetry each minute.
    5. Plan CPU and memory percentage (average across instances).

Inputs come from Export-Results.ps1, Export-PlanMetrics.ps1 and tools/Run-Queries.ps1.
"""

import json
import os
import sys
from collections import defaultdict

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))
sys.path.insert(0, os.path.join(KIT_ROOT, "scripts"))
from importlib import import_module  # noqa: E402

charts = import_module("New-Charts")
plt = charts.plt

RUNS = [
    ("A: trigger concurrency 100", "orders-concurrency", "#0078D4"),
    ("B: batch trigger (1 s, 200)", "orders-batch", "#D83B01"),
]


def read_json(folder, name):
    path = os.path.join(folder, "custom", name + ".json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig") as handle:
        text = handle.read().strip()
    if not text:
        return []
    data = json.loads(text)
    return data if isinstance(data, list) else [data]


def load_run(folder, entity):
    bus = [row for row in charts.read_csv(folder, "servicebus-metrics") if row["entity"] == entity]
    bus.sort(key=lambda row: charts.parse_time(row["minute"]))
    sent = [row for row in bus if charts.number(row["incomingMessages"]) > 0]
    origin = charts.parse_time((sent or bus)[0]["minute"])

    def minutes(value):
        return (charts.parse_time(value) - origin).total_seconds() / 60.0

    run = {"origin": origin}
    run["bus"] = [(minutes(row["minute"]), charts.number(row["activeMessages"])) for row in bus]
    # The query omits seconds with no completions, so bin into 30-second buckets and fill the gaps with zero.
    buckets = defaultdict(float)
    for row in read_json(folder, "completions-per-second"):
        buckets[int((charts.parse_time(row["sec"]) - origin).total_seconds() // 30)] += charts.number(row["completed"])
    run["completed"] = [(key / 2.0, buckets[key] / 30.0) for key in range(min(buckets), max(buckets) + 1)] if buckets else []
    run["inFlight"] = [(minutes(row["sec"]), charts.number(row["appInFlight"])) for row in read_json(folder, "concurrency-per-second")]
    instances = charts.read_csv(folder, "instances-per-minute")
    run["instances"] = sorted((minutes(row["minute"]), charts.number(row["instances"])) for row in instances)
    plans = charts.read_csv(folder, "plan-metrics")
    run["cpu"] = sorted((minutes(row["minute"]), charts.number(row["cpuAvg"])) for row in plans)
    run["memory"] = sorted((minutes(row["minute"]), charts.number(row["memoryAvg"])) for row in plans)

    return run


def plot(axis, points, color, label, step=False):
    if not points:
        return
    points = sorted(points)
    xs, ys = [point[0] for point in points], [point[1] for point in points]
    if step:
        axis.step(xs, ys, where="post", color=color, label=label)
    else:
        axis.plot(xs, ys, color=color, label=label, linewidth=0.9)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    runs = [load_run(sys.argv[1], RUNS[0][1]), load_run(sys.argv[2], RUNS[1][1])]
    figure, axes = plt.subplots(5, 2, figsize=(15, 17), sharex=True, sharey="row")
    for column, (run, (title, entity, color)) in enumerate(zip(runs, RUNS)):
        axes[0][column].set_title(f"{title}\nstart {run['origin']:%Y-%m-%d %H:%M} UTC")
        plot(axes[0][column], run["completed"], color, "Process_order ended / s (30 s average)", step=True)

        plot(axes[1][column], run["bus"], color, f"active messages in {entity}", step=True)
        flows = "orders-concurrency" if column == 0 else "process-batch-item"
        plot(axes[2][column], run["inFlight"], color, f"{flows} runs in flight")
        plot(axes[3][column], run["instances"], color, "instances", step=True)
        plot(axes[4][column], run["cpu"], "#D83B01", "CPU % (avg)", step=True)
        plot(axes[4][column], run["memory"], "#5C2D91", "memory % (avg)", step=True)
        for row in range(5):
            axes[row][column].grid(alpha=0.3)
            axes[row][column].legend(loc="upper left", fontsize=8)
        axes[4][column].set_xlabel("minutes since the first message was sent")

    axes[0][0].set_ylabel("actions / s")
    axes[1][0].set_ylabel("messages")
    axes[2][0].set_ylabel("runs in flight")
    axes[3][0].set_ylabel("instances")
    axes[4][0].set_ylabel("percent")
    axes[4][0].set_ylim(0, 100)
    figure.suptitle("Trigger concurrency vs batch trigger: same WS1 plan, same load", fontsize=14)
    figure.tight_layout()
    figure.savefig(sys.argv[3], dpi=110)
    print(f"Saved {sys.argv[3]}")


if __name__ == "__main__":
    main()
