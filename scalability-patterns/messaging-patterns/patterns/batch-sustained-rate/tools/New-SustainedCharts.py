"""Draws the sustained-rate charts for one batch configuration.

Usage:
    python tools/New-SustainedCharts.py --export <export.csv> --sendlog <send.log> --poll <poll.csv>
        --instances <instances-per-minute.csv> --out <folder> --prefix <sustained-a> --title <text>
        [--steady-start <utc> --steady-end <utc>]

Inputs:
    export.csv     Cosmos export: messageId, releaseId, receiver, sentAtUtc, processedAtUtc (no header).
    send.log       Send-Rate.py log lines: <utc> phase=<name> sent=<n> rate10s=<r>/s.
    poll.csv       utc, active, dlq (Service Bus queue depth).
    instances.csv  minute, instances (App Insights distinct cloud_RoleInstance per minute).

Charts (<prefix>-rates, -backlog, -instances, -release-size .png):
    rates          incoming (sent) and processed (unique orders) per second, 10-second average.
    backlog        orders sent but not yet processed, and Service Bus active messages.
    instances      Logic App instances per minute.
    release-size   items per release, and releases per 10 seconds.
"""

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

KIT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(KIT_ROOT, "scripts"))
sys.path.insert(0, os.path.join(KIT_ROOT, ".tools", "pylib"))
from importlib import import_module  # noqa: E402

charts = import_module("New-Charts")
plt = charts.plt

BIN = 10


def to_time(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc)


def read_rows(path):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def read_send_log(path):
    points = []
    pattern = re.compile(r"^(\S+) phase=\S+ sent=([\d,]+)")
    with open(path, encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            match = pattern.match(line.strip())
            if match:
                points.append((charts.parse_time(match.group(1)).timestamp(), int(match.group(2).replace(",", ""))))
    return points


def sent_at(points, epoch):
    if not points or epoch < points[0][0]:
        return 0
    for (t0, s0), (t1, s1) in zip(points, points[1:]):
        if t0 <= epoch < t1:
            return s0 + (s1 - s0) * (epoch - t0) / (t1 - t0)
    return points[-1][1]


def shade(axis, args):
    if args.steady_start and args.steady_end:
        axis.axvspan(charts.parse_time(args.steady_start), charts.parse_time(args.steady_end),
                     color="#999999", alpha=0.12, label="steady window")


def main():
    parser = argparse.ArgumentParser()
    for name in ("export", "sendlog", "poll", "instances", "out", "prefix", "title"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--steady-start")
    parser.add_argument("--steady-end")
    args = parser.parse_args()

    first = {}
    releases = defaultdict(list)
    with open(args.export, newline="") as handle:
        for row in csv.reader(handle):
            if len(row) < 5 or not row[4]:
                continue
            processed = charts.parse_time(row[4]).timestamp()
            if row[0] not in first or processed < first[row[0]]:
                first[row[0]] = processed
            releases[row[1]].append(processed)

    sends = read_send_log(args.sendlog)
    start = int(sends[0][0]) // BIN * BIN - BIN
    end = int(max(max(first.values()), sends[-1][0])) // BIN * BIN + BIN
    processed_bins = Counter(int(t) // BIN * BIN for t in first.values())
    bins = list(range(start, end, BIN))
    times = [to_time(t) for t in bins]

    incoming = [max(0.0, sent_at(sends, t + BIN) - sent_at(sends, t)) / BIN for t in bins]
    processed = [processed_bins.get(t, 0) / BIN for t in bins]
    figure, axis = plt.subplots(figsize=(10, 4.5))
    shade(axis, args)
    axis.plot(times, incoming, label="incoming (sent) msg/s", color="#0078D4", linestyle="--")
    axis.plot(times, processed, label="processed (unique orders) msg/s", color="#107C10", linewidth=1.5)
    charts.save(figure, axis, args.out, args.prefix + "-rates", "Incoming and processing rate (10-second average)",
                "messages / second", args.title)

    backlog, total = [], 0
    for t in bins:
        total += processed_bins.get(t, 0)
        backlog.append(max(0.0, sent_at(sends, t + BIN) - total))
    poll = sorted(read_rows(args.poll), key=lambda row: row["utc"])
    figure, axis = plt.subplots(figsize=(10, 4.5))
    shade(axis, args)
    axis.plot(times, backlog, label="sent, not yet processed (batch store + queue)", color="#D83B01", linewidth=2)
    axis.plot([charts.parse_time(row["utc"]) for row in poll], charts.series(poll, "active"),
              label="Service Bus active messages (queue orders)", color="#0078D4", marker=".", markersize=3)
    charts.save(figure, axis, args.out, args.prefix + "-backlog", "Backlog", "messages", args.title)

    rows = sorted(read_rows(args.instances), key=lambda row: row["minute"])
    figure, axis = plt.subplots(figsize=(10, 4.5))
    shade(axis, args)
    axis.plot([charts.parse_time(row["minute"]) for row in rows], charts.series(rows, "instances"),
              marker=".", label="instances (App Insights role instances per minute)", color="#5C2D91")
    axis.set_ylim(0, 105)
    charts.save(figure, axis, args.out, args.prefix + "-instances", "Logic App instances", "instances", args.title)

    release_points = sorted((min(values), len(values)) for values in releases.values())
    figure, axis = plt.subplots(figsize=(10, 4.5))
    shade(axis, args)
    axis.scatter([to_time(t) for t, _ in release_points], [size for _, size in release_points],
                 s=4, alpha=0.35, color="#0078D4", label="items per release")
    per_bin = Counter(int(t) // BIN * BIN for t, _ in release_points)
    right = axis.twinx()
    right.plot(times, [per_bin.get(t, 0) for t in bins], color="#D83B01", linewidth=1, alpha=0.8,
               label="releases per 10 s")
    right.set_ylabel("releases / 10 s")
    right.legend(loc="upper right")
    charts.save(figure, axis, args.out, args.prefix + "-release-size", "Release size", "items per release", args.title)


if __name__ == "__main__":
    main()
