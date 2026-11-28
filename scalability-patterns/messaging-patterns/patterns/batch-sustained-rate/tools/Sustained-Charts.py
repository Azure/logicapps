"""Draws the four sustained-rate charts for one config from Batch-Analyze.py outputs.

Usage: python Sustained-Charts.py <runDir> <prefix> <label> <outDir> <namePrefix>
"""
import csv
import json
import os
import sys
from datetime import datetime, timedelta

KIT = os.environ.get("KIT_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(KIT, ".tools", "pylib"))
sys.path.insert(0, os.path.join(KIT, "scripts"))
from importlib import import_module  # noqa: E402

charts = import_module("New-Charts")
plt, mdates, parse_time = charts.plt, charts.mdates, charts.parse_time

run_dir, prefix, label, out_dir, name = sys.argv[1:6]
os.makedirs(out_dir, exist_ok=True)


def rows(file):
    with open(os.path.join(run_dir, f"{prefix}-{file}"), newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


phases = json.load(open(os.path.join(run_dir, f"{prefix}-phases.json")))
steady = next(phase for phase in phases["phases"] if phase["name"] == "steady")
steady_start, steady_end = parse_time(steady["startUtc"]), parse_time(steady["endUtc"])

persec = [(parse_time(row["utc"]), int(row["sent"]), int(row["processed"])) for row in rows("persec.csv")]
persec.sort()

# NOTE: Cosmos sentAt covers processed messages only, so actual incoming comes from the sender log.
send_points = []
with open(os.path.join(run_dir, f"{prefix}-send.log"), encoding="utf-8") as handle:
    for line in handle:
        if " sent=" in line:
            parts = line.split()
            send_points.append((parse_time(parts[0]), int(parts[2].split("=")[1].replace(",", ""))))
send_start = send_points[0][0] - timedelta(seconds=10)
send_points.insert(0, (send_start, 0))


def sent_until(when):
    total = 0
    for point_time, point_total in send_points:
        if point_time <= when:
            total = point_total
    return total


def finish(axis, title, ylabel, file):
    axis.axvspan(steady_start, steady_end, color="#999999", alpha=0.12, label="steady window")
    axis.set_title(title)
    axis.set_ylabel(ylabel)
    axis.set_xlabel("Time (UTC)")
    axis.grid(alpha=0.3)
    axis.legend(loc="best")
    axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    axis.figure.suptitle(label, fontsize=9)
    axis.figure.autofmt_xdate()
    axis.figure.tight_layout()
    axis.figure.savefig(os.path.join(out_dir, f"{name}-{file}.png"), dpi=100)
    plt.close(axis.figure)


bucket = 10
times, processed_rate = [], []
for index in range(0, len(persec), bucket):
    chunk = persec[index:index + bucket]
    times.append(chunk[0][0])
    processed_rate.append(sum(item[2] for item in chunk) / len(chunk))
send_times = [point[0] for point in send_points]
send_rate = [0] + [
    (send_points[index][1] - send_points[index - 1][1]) / max(1, (send_points[index][0] - send_points[index - 1][0]).total_seconds())
    for index in range(1, len(send_points))]
send_times.append(send_points[-1][0] + timedelta(seconds=1))
send_rate.append(0)
figure, axis = plt.subplots(figsize=(12, 5))
axis.step(send_times, send_rate, "--", where="pre", color="#0078D4", label="incoming (sent) msg/s")
axis.plot(times, processed_rate, color="#107C10", label="processed (unique orders) msg/s")
finish(axis, "Incoming and processing rate (10-second average)", "messages / second", "rates")

backlog_times, backlog, processed_total = [], [], 0
for index, (when, sent, processed) in enumerate(persec):
    processed_total += processed
    if index % bucket == 0:
        backlog_times.append(when)
        backlog.append(max(0, sent_until(when) - processed_total))
poll = [(parse_time(row["utc"]), int(row["active"])) for row in rows("poll.csv")]
figure, axis = plt.subplots(figsize=(12, 5))
axis.plot(backlog_times, backlog, color="#D83B01", linewidth=2, label="sent, not yet processed (batch store + queue)")
axis.plot([item[0] for item in poll], [item[1] for item in poll], ".-", color="#0078D4", label="Service Bus active messages (queue orders)")
finish(axis, "Backlog", "messages", "backlog")

instances = [(parse_time(row["minute"]), int(row["instances"])) for row in rows("instances.csv")]
figure, axis = plt.subplots(figsize=(12, 5))
axis.step([item[0] for item in instances], [item[1] for item in instances], where="post", color="#5C2D91", label="instances (max %d)" % max(item[1] for item in instances))
finish(axis, "Logic App instances per minute", "instances", "instances")

releases = [(parse_time(row["firstProcessedUtc"]), int(row["size"])) for row in rows("releases.csv")]
figure, axis = plt.subplots(figsize=(12, 5))
axis.scatter([item[0] for item in releases], [item[1] for item in releases], s=6, color="#0078D4", label="release (messages per batch)")
finish(axis, "Release size (by first processed time)", "messages per release", "release-size")
print("charts written to", out_dir)
