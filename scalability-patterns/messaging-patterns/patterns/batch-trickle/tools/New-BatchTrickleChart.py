"""Draws the batch-trickle charts and writes summary.json from the exported run folder."""
import csv
import json
import os
import statistics
import sys
from collections import Counter
from datetime import datetime, timedelta

# The Azure CLI Python has a ._pth file, so it ignores PYTHONPATH; add the kit's package folder directly.
for entry in os.environ.get("PYTHONPATH", "").split(os.pathsep):
    if entry and entry not in sys.path:
        sys.path.insert(0, entry)

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def parse(value):
    text = str(value).replace("Z", "+00:00")
    if "." in text:
        head, tail = text.split(".", 1)
        fraction, _, zone = tail.partition("+")
        text = f"{head}.{fraction[:6]}" + (f"+{zone}" if zone else "")
    return datetime.fromisoformat(text)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def percentile(values, share):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(share * (len(ordered) - 1))))]


run_dir = sys.argv[1]
custom = os.path.join(run_dir, "custom")
rates = {parse(r["second"]): r for r in load(os.path.join(custom, "per-second-rates.json"))}
messages = load(os.path.join(custom, "per-message-latency.json"))
minutes = load(os.path.join(custom, "instances-and-messages-per-minute.json"))
with open(os.path.join(run_dir, "plan-metrics.csv"), encoding="utf-8") as handle:
    plan = list(csv.DictReader(handle))
with open(os.path.join(run_dir, "servicebus-metrics.csv"), encoding="utf-8") as handle:
    servicebus = list(csv.DictReader(handle))

# Fill every second from the first to the last event so idle seconds count as zero.
first_second, last_second = min(rates), max(rates)
seconds, incoming, processed, releases, backlog = [], [], [], [], []
pending = 0
moment = first_second
while moment <= last_second:
    row = rates.get(moment, {})
    seconds.append(moment)
    incoming.append(row.get("incoming", 0) or 0)
    processed.append(row.get("processed", 0) or 0)
    releases.append(row.get("releases", 0) or 0)
    pending += incoming[-1] - processed[-1]
    backlog.append(max(pending, 0))
    moment += timedelta(seconds=1)

# Steady window: from the first processed message to the last second with a backlog (or the end of data).
start_index = next(i for i, value in enumerate(processed) if value > 0)
end_index = max(i for i, value in enumerate(processed) if value > 0)
window = processed[start_index:end_index + 1]
mean = statistics.mean(window)
stdev = statistics.pstdev(window)
latency = [m["e2eMs"] / 1000.0 for m in messages if m.get("e2eMs") is not None]
release_sizes = []
for index in range(start_index, end_index + 1, 10):
    released = sum(releases[index:index + 10])
    if released:
        release_sizes.append(sum(processed[index:index + 10]) / released)


def phase(values):
    """Mean, max, standard deviation and seconds above 5 for one phase of the run."""
    if not values:
        return None
    phase_mean = statistics.mean(values)
    phase_stdev = statistics.pstdev(values)
    return {
        "seconds": len(values),
        "processed": sum(values),
        "meanPerSecond": round(phase_mean, 3),
        "maxPerSecond": max(values),
        "stdevPerSecond": round(phase_stdev, 3),
        "coefficientOfVariation": round(phase_stdev / phase_mean, 3) if phase_mean else None,
        "secondsAbove5": sum(1 for value in values if value > 5),
        "histogram": dict(sorted(Counter(values).items())),
    }


# The load phase ends at the last second with incoming messages; the drain phase follows.
last_incoming_index = max(i for i, value in enumerate(incoming) if value > 0)
summary = {
    "loadEndUtc": seconds[last_incoming_index].isoformat(),
    "loadPhase": phase(processed[start_index:last_incoming_index + 1]),
    "drainPhase": phase(processed[last_incoming_index + 1:end_index + 1]),
    "firstProcessedUtc": seconds[start_index].isoformat(),
    "lastProcessedUtc": seconds[end_index].isoformat(),
    "incomingTotal": sum(incoming),
    "incomingPeakPerSecond": max(incoming),
    "processedTotal": sum(processed),
    "processedMeanPerSecond": round(mean, 3),
    "processedMaxPerSecond": max(window),
    "processedMinPerSecond": min(window),
    "processedStdevPerSecond": round(stdev, 3),
    "processedCoefficientOfVariation": round(stdev / mean, 3) if mean else None,
    "processedPerSecondHistogram": dict(sorted(Counter(window).items())),
    "secondsAbove5": sum(1 for value in window if value > 5),
    "releasesTotal": sum(releases),
    "meanReleaseSize": round(sum(processed) / sum(releases), 3) if sum(releases) else None,
    "backlogPeak": max(backlog),
    "backlogAtEnd": backlog[-1],
    "latencySeconds": {
        "p50": round(percentile(latency, 0.50), 1),
        "p95": round(percentile(latency, 0.95), 1),
        "p99": round(percentile(latency, 0.99), 1),
        "max": round(max(latency), 1),
    } if latency else None,
    "duplicateExecutions": sum(1 for m in messages if (m.get("executions") or 1) > 1),
    "maxInstances": max((m["instances"] for m in minutes), default=None),
    "cpuAvgPercent": round(statistics.mean(float(p["cpuAvg"]) for p in plan if p["cpuAvg"]), 1),
    "cpuMaxPercent": round(max(float(p["cpuMax"]) for p in plan if p["cpuMax"]), 1),
    "memoryAvgPercent": round(statistics.mean(float(p["memoryAvg"]) for p in plan if p["memoryAvg"]), 1),
    "memoryMaxPercent": round(max(float(p["memoryMax"]) for p in plan if p["memoryMax"]), 1),
    "serviceBusDeadLetteredMax": max((float(r.get("DeadletteredMessages") or 0) for r in servicebus), default=0),
}
with open(os.path.join(run_dir, "summary.json"), "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)
print(json.dumps(summary, indent=2))

fig, axes = plt.subplots(5, 1, figsize=(13, 16), sharex=True)
ax = axes[0]
ax.plot(seconds, incoming, linewidth=0.6, color="tab:blue", label="incoming (sent to batch) / s")
ax.plot(seconds, processed, linewidth=0.8, color="tab:green", label="processed (Process_order) / s")
ax.axhline(5, color="red", linestyle="--", linewidth=0.8, label="downstream limit 5 / s")
ax.set_ylabel("messages / s")
ax.set_title("batch-trickle: incoming vs processing rate (1 s bins)")
ax.legend(loc="upper right")
ax.grid(True, alpha=0.3)

ax = axes[1]
ax.plot(seconds, backlog, color="tab:orange", label="backlog in batch (incoming - processed)")
sb_minutes = [parse(r["minute"]) for r in servicebus]
ax.plot(sb_minutes, [float(r.get("ActiveMessages") or 0) for r in servicebus], color="tab:purple", marker=".", label="Service Bus active messages (max / min)")
ax.set_ylabel("messages")
ax.set_title("Backlog")
ax.legend(loc="upper right")
ax.grid(True, alpha=0.3)

ax = axes[2]
size_times = [seconds[i] for i in range(start_index, end_index + 1, 10) if sum(releases[i:i + 10])]
ax.plot(size_times, release_sizes, color="tab:brown", label="mean release size (messages per release, 10 s bins)")
ax.plot(seconds, releases, linewidth=0.5, color="grey", alpha=0.6, label="releases / s")
ax.set_ylabel("messages / releases")
ax.set_title("Release size")
ax.legend(loc="upper right")
ax.grid(True, alpha=0.3)

ax = axes[3]
ax.step([parse(m["minute"]) for m in minutes], [m["instances"] for m in minutes], where="post", color="black")
ax.set_ylabel("instances")
ax.set_ylim(0, max(m["instances"] for m in minutes) + 1)
ax.set_title("Workflow host instances (distinct cloud_RoleInstance per minute)")
ax.grid(True, alpha=0.3)

ax = axes[4]
plan_minutes = [parse(p["minute"]) for p in plan]
ax.plot(plan_minutes, [float(p["cpuAvg"] or 0) for p in plan], label="CPU avg %")
ax.plot(plan_minutes, [float(p["cpuMax"] or 0) for p in plan], linestyle="--", label="CPU max %")
ax.plot(plan_minutes, [float(p["memoryAvg"] or 0) for p in plan], label="memory avg %")
ax.set_ylabel("%")
ax.set_ylim(0, 100)
ax.set_title("WS1 plan CPU and memory (1 min)")
ax.set_xlabel("time (UTC)")
ax.legend(loc="upper right")
ax.grid(True, alpha=0.3)
fig.tight_layout()
path = os.path.join(run_dir, "batch-trickle-timeline.png")
fig.savefig(path, dpi=100)
print(path)

fig, (left, right) = plt.subplots(1, 2, figsize=(12, 4))
histogram = Counter(window)
left.bar(list(histogram), list(histogram.values()), color="tab:green")
left.set_xlabel("messages processed in a second")
left.set_ylabel("seconds")
left.set_title("Processing rate distribution (steady window)")
left.grid(True, alpha=0.3)
right.scatter([parse(m["sentAt"]) for m in messages], latency, s=2)
right.set_xlabel("send time (UTC)")
right.set_ylabel("e2e latency (s)")
right.set_title("Per-message latency (grows with the backlog)")
right.grid(True, alpha=0.3)
fig.autofmt_xdate()
fig.tight_layout()
path = os.path.join(run_dir, "batch-trickle-distribution.png")
fig.savefig(path, dpi=100)
print(path)
