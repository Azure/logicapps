"""Draws the batch-window charts for one run folder.

Usage:
    python patterns/batch-window/tools/New-BatchCharts.py <runFolder>

Inputs (in the run folder):
    custom/batch-timeline.json   from tools/Run-Queries.ps1 (queries/batch-timeline.kql)
    servicebus-metrics.csv       from scripts/Export-Results.ps1
    plan-metrics.csv             from scripts/Export-PlanMetrics.ps1

Outputs (in the run folder):
    batch-rates.png     messages per minute: sent to the queue, added to the batch, processed
    batch-backlog.png   queue backlog and batch backlog (added but not yet processed)
    release-size.png    releases per minute and messages per release
    batch-scale.png     instances, plan CPU and memory
"""

import json
import os
import sys

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, "scripts"))
from importlib import import_module  # noqa: E402

charts = import_module("New-Charts")
plt = charts.plt
mdates = charts.mdates


def load_timeline(folder):
    with open(os.path.join(folder, "custom", "batch-timeline.json"), encoding="utf-8-sig") as handle:
        rows = json.load(handle)
    for row in rows:
        row["time"] = charts.parse_time(str(row["minute"]))
    return sorted(rows, key=lambda row: row["time"])


def value(row, name):
    number = row.get(name)
    return float(number) if number not in (None, "") else 0.0


def finish(figure, axes, output):
    for axis in axes:
        axis.grid(True, alpha=0.3)
        axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axes[-1].set_xlabel("Time (UTC)")
    figure.tight_layout()
    figure.savefig(output, dpi=110)
    plt.close(figure)
    print(f"  {os.path.basename(output)}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    folder = sys.argv[1]
    timeline = load_timeline(folder)
    times = [row["time"] for row in timeline]
    bus = sorted(charts.read_csv(folder, "servicebus-metrics"), key=lambda row: charts.parse_time(row["minute"]))
    bus_times = [charts.parse_time(row["minute"]) for row in bus]
    plans = sorted(charts.read_csv(folder, "plan-metrics"), key=lambda row: charts.parse_time(row["minute"]))
    plan_times = [charts.parse_time(row["minute"]) for row in plans]

    figure, axis = plt.subplots(figsize=(10, 4.5))
    axis.plot(bus_times, charts.series(bus, "incomingMessages"), color="#5C2D91", linestyle="--",
              label="Sent to queue")
    axis.plot(times, [value(row, "batched") for row in timeline], color="#D83B01", label="Added to batch")
    axis.plot(times, [value(row, "processed") for row in timeline], color="#0078D4", linewidth=2,
              label="Processed (process-order runs)")
    axis.axhline(17 * 60, color="#107C10", linestyle=":", label="Target 17/s = 1,020/min")
    axis.set_ylabel("Messages per minute")
    axis.set_ylim(bottom=0)
    axis.legend(loc="upper right", fontsize=8)
    axis.set_title("Incoming and processing rate")
    finish(figure, [axis], os.path.join(folder, "batch-rates.png"))

    figure, axis = plt.subplots(figsize=(10, 4.5))
    added = processed = 0.0
    backlog = []
    for row in timeline:
        added += value(row, "batched")
        processed += value(row, "processed")
        backlog.append(max(0.0, added - processed))
    axis.fill_between(times, backlog, color="#0078D4", alpha=0.25, step="mid", label="Batch backlog (added - processed)")
    axis.plot(bus_times, charts.series(bus, "activeMessages"), color="#5C2D91", label="Queue active messages")
    axis.set_ylabel("Messages")
    axis.set_ylim(bottom=0)
    axis.legend(loc="upper right", fontsize=8)
    axis.set_title("Backlog")
    finish(figure, [axis], os.path.join(folder, "batch-backlog.png"))

    figure, (count_axis, size_axis) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
    count_axis.bar(times, [value(row, "releases") for row in timeline], width=1 / 1440 * 0.8, color="#0078D4")
    count_axis.axhline(60, color="#107C10", linestyle=":", label="Target 60 releases/min (1 s recurrence)")
    count_axis.set_ylabel("Releases per minute")
    count_axis.legend(loc="upper right", fontsize=8)
    count_axis.set_title("Batch releases")
    sizes = [value(row, "released") / value(row, "releases") if value(row, "releases") else None for row in timeline]
    size_axis.plot(times, sizes, marker=".", color="#D83B01")
    size_axis.axhline(17, color="#107C10", linestyle=":", label="messageCountLimit 17")
    size_axis.set_ylabel("Messages per release")
    size_axis.set_ylim(0, 20)
    size_axis.legend(loc="lower right", fontsize=8)
    finish(figure, [count_axis, size_axis], os.path.join(folder, "release-size.png"))

    figure, (scale_axis, cpu_axis) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
    scale_axis.step(times, [value(row, "instances") for row in timeline], where="mid", color="#107C10", linewidth=2)
    scale_axis.set_ylabel("Instances")
    scale_axis.set_ylim(0, 4)
    scale_axis.set_title("Scale-out (max 3) and plan resources")
    cpu_axis.plot(plan_times, charts.series(plans, "cpuAvg"), color="#D83B01", label="CPU % (average)")
    cpu_axis.plot(plan_times, charts.series(plans, "cpuMax"), color="#D83B01", linestyle=":", label="CPU % (max)")
    cpu_axis.plot(plan_times, charts.series(plans, "memoryAvg"), color="#0078D4", label="Memory % (average)")
    cpu_axis.set_ylabel("Percent")
    cpu_axis.set_ylim(0, 100)
    cpu_axis.legend(loc="upper right", fontsize=8)
    finish(figure, [scale_axis, cpu_axis], os.path.join(folder, "batch-scale.png"))


if __name__ == "__main__":
    main()
