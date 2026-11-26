"""Draws the fixed-rate charts and summary for one batch-fixed-rate run.

Usage:
    python New-FixedRateCharts.py <runFolder> [targetRate]

Reads custom/timeline-per-second.json and custom/releases.json (Run-Queries.ps1),
servicebus-metrics.csv and instances-per-minute.csv (Export-Results.ps1) and
plan-metrics.csv (Export-PlanMetrics.ps1). Writes rate.png, backlog.png,
release-size.png, resources.png and fixed-rate-summary.json to the run folder.
"""

import csv
import json
import os
import statistics
import sys
from datetime import datetime, timezone

KIT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

BLUE, ORANGE, GREEN, PURPLE, GREY = "#0078D4", "#D83B01", "#107C10", "#5C2D91", "#605E5C"


def parse_time(text):
    text = text.replace("Z", "+00:00")
    if "." in text:
        head, tail = text.split(".", 1)
        digits = "".join(ch for ch in tail if ch.isdigit())
        zone = tail[len(digits):]
        text = f"{head}.{digits[:6].ljust(6, '0')}{zone}"
    value = datetime.fromisoformat(text)
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def read_json(folder, name):
    path = os.path.join(folder, "custom", name + ".json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig") as handle:
        data = json.load(handle)
    return data if isinstance(data, list) else [data]


def read_csv(folder, name):
    path = os.path.join(folder, name + ".csv")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def rolling(values, width):
    output = []
    total = 0.0
    for index, value in enumerate(values):
        total += value
        if index >= width:
            total -= values[index - width]
        output.append(total / min(index + 1, width))
    return output


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def format_axis(axis):
    axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axis.grid(alpha=0.3)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    folder = sys.argv[1]
    target = float(sys.argv[2]) if len(sys.argv) > 2 else 50.0
    seconds = sorted(read_json(folder, "timeline-per-second"), key=lambda row: row["s"])
    releases = sorted(read_json(folder, "releases"), key=lambda row: row["releaseAt"])
    bus = read_csv(folder, "servicebus-metrics")
    instances = read_csv(folder, "instances-per-minute")
    plans = read_csv(folder, "plan-metrics")

    times = [parse_time(row["s"]) for row in seconds]
    sent = [float(row["sent"]) for row in seconds]
    pushed = [float(row["pushed"]) for row in seconds]
    started = [float(row["started"]) for row in seconds]
    backlog = [float(row["backlog"]) for row in seconds]

    figure, axis = plt.subplots(figsize=(11, 4.8))
    axis.plot(times, started, color=BLUE, alpha=0.18, linewidth=0.6, label="processed per second")
    axis.plot(times, rolling(sent, 10), color=GREY, linestyle="--", label="sent by producer (10 s avg)")
    axis.plot(times, rolling(pushed, 10), color=ORANGE, label="pushed to batch (10 s avg)")
    axis.plot(times, rolling(started, 10), color=BLUE, linewidth=2, label="processed (10 s avg)")
    axis.axhline(target, color=GREEN, linestyle=":", linewidth=2, label=f"target {target:g} msg/s")
    axis.set_ylabel("messages per second")
    axis.set_title("Incoming vs processing rate")
    format_axis(axis)
    axis.legend(loc="upper right", fontsize=8)
    figure.tight_layout()
    figure.savefig(os.path.join(folder, "rate.png"), dpi=120)
    plt.close(figure)

    figure, axis = plt.subplots(figsize=(11, 4))
    axis.plot(times, backlog, color=PURPLE, linewidth=1.5, label="held in batch (pushed - processed)")
    bus_rows = sorted([row for row in bus if number(row.get("activeMessages")) is not None],
                      key=lambda row: row["minute"])
    if bus_rows:
        axis.plot([parse_time(row["minute"]) for row in bus_rows],
                  [number(row["activeMessages"]) for row in bus_rows],
                  color=ORANGE, marker="o", markersize=3, label="Service Bus active messages (per minute)")
    axis.set_ylabel("messages")
    axis.set_title("Backlog")
    format_axis(axis)
    axis.legend(loc="upper right", fontsize=8)
    figure.tight_layout()
    figure.savefig(os.path.join(folder, "backlog.png"), dpi=120)
    plt.close(figure)

    release_times = [parse_time(row["releaseAt"]) for row in releases]
    sizes = [float(row["size"]) for row in releases]
    gaps = [float(row["gapSeconds"]) for row in releases if number(row.get("gapSeconds")) is not None]
    figure, (left, right) = plt.subplots(1, 2, figsize=(11, 4), gridspec_kw={"width_ratios": [2.2, 1]})
    left.scatter(release_times, sizes, s=4, color=BLUE)
    left.axhline(target, color=GREEN, linestyle=":", linewidth=2, label="messageCountLimit 50")
    left.set_ylabel("messages per release")
    left.set_title("Release size")
    format_axis(left)
    left.legend(loc="lower right", fontsize=8)
    right.hist(gaps, bins=[x / 2 for x in range(0, 41)], color=ORANGE)
    right.set_xlabel("seconds between releases")
    right.set_title("Release gap")
    right.grid(alpha=0.3)
    figure.tight_layout()
    figure.savefig(os.path.join(folder, "release-size.png"), dpi=120)
    plt.close(figure)

    figure, (scale_axis, cpu_axis) = plt.subplots(2, 1, figsize=(11, 5.5), sharex=True,
                                                  gridspec_kw={"height_ratios": [1, 1.4]})
    instance_rows = sorted(instances, key=lambda row: row["minute"])
    instance_key = next((key for key in ("instances", "instanceCount", "count_") if instance_rows and key in instance_rows[0]), None)
    if instance_key:
        scale_axis.step([parse_time(row["minute"]) for row in instance_rows],
                        [number(row[instance_key]) for row in instance_rows], where="post", color=BLUE)
    scale_axis.set_ylabel("instances")
    scale_axis.set_ylim(0, 4)
    scale_axis.set_title("Instances, CPU and memory (WS1, 1-3 instances)")
    format_axis(scale_axis)
    plan_rows = sorted(plans, key=lambda row: row["minute"])
    plan_times = [parse_time(row["minute"]) for row in plan_rows]
    for column, color, label in (("cpuAvg", ORANGE, "CPU % (avg)"), ("cpuMax", ORANGE, "CPU % (max)"),
                                 ("memoryAvg", GREEN, "memory % (avg)"), ("memoryMax", GREEN, "memory % (max)")):
        values = [number(row.get(column)) for row in plan_rows]
        if any(value is not None for value in values):
            cpu_axis.plot(plan_times, values, color=color, linestyle="-" if column.endswith("Avg") else ":", label=label)
    cpu_axis.set_ylabel("percent")
    cpu_axis.set_ylim(0, 100)
    format_axis(cpu_axis)
    cpu_axis.legend(loc="upper right", fontsize=8)
    cpu_axis.set_xlabel("time (UTC)")
    figure.tight_layout()
    figure.savefig(os.path.join(folder, "resources.png"), dpi=120)
    plt.close(figure)

    minutes = {}
    for when, value, incoming in zip(times, started, pushed):
        key = when.replace(second=0, microsecond=0)
        bucket = minutes.setdefault(key, [0.0, 0.0])
        bucket[0] += value
        bucket[1] += incoming
    per_minute = [(key, value[0] / 60.0, value[1] / 60.0) for key, value in sorted(minutes.items())]
    saturated = [rate for _, rate, _ in per_minute if rate > 0]
    first = next((index for index, value in enumerate(started) if value > 0), 0)
    last = max((index for index, value in enumerate(started) if value > 0), default=0)
    active = started[first:last + 1]
    summary = {
        "targetRate": target,
        "processedMessages": sum(started),
        "pushedMessages": sum(pushed),
        "processingSeconds": len(active),
        "averageRateWhileProcessing": (sum(active) / len(active)) if active else None,
        "maxPerSecond": max(started) if started else None,
        "secondsAbove50": sum(1 for value in started if value > target),
        "max10sAverage": max(rolling(started, 10)) if started else None,
        "perMinuteRate": [{"minute": key.isoformat(), "processedPerSecond": round(rate, 2),
                           "pushedPerSecond": round(incoming, 2)} for key, rate, incoming in per_minute],
        "perMinuteRateCv": (statistics.pstdev(saturated) / statistics.mean(saturated)) if len(saturated) > 1 else None,
        "peakBatchBacklog": max(backlog) if backlog else None,
        "releases": len(sizes),
        "releaseSizeP50": percentile(sizes, 0.5),
        "releaseSizeMax": max(sizes) if sizes else None,
        "releasesAt50": sum(1 for size in sizes if size == target),
        "releaseGapP50": percentile(gaps, 0.5),
        "releaseGapP95": percentile(gaps, 0.95),
        "releaseGapMax": max(gaps) if gaps else None,
    }
    with open(os.path.join(folder, "fixed-rate-summary.json"), "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2)
    print(json.dumps({key: value for key, value in summary.items() if key != "perMinuteRate"}, indent=2))


if __name__ == "__main__":
    main()
