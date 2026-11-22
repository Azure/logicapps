"""Draws one timeline chart for a benchmark run: load, scale-out and plan resources.

Usage:
    python scripts/New-TimelineChart.py <runFolder> <outputPng> [title]

Panels share the time axis (UTC):
    1. Service Bus messages per minute for each entity: incoming (sent) and completed
       (processed), with active messages (backlog) on the right axis.
    2. Logic App instances that reported telemetry each minute.
    3. App Service plan CPU and memory percentage (average across instances).

Inputs are servicebus-metrics.csv and instances-per-minute.csv from Export-Results.ps1,
and plan-metrics.csv from Export-PlanMetrics.ps1. A missing file leaves its panel empty.
"""

import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module  # noqa: E402

charts = import_module("New-Charts")
plt = charts.plt
mdates = charts.mdates

ENTITY_COLORS = ["#0078D4", "#D83B01", "#107C10", "#5C2D91"]


def group_by(rows, column):
    groups = defaultdict(list)
    for row in rows:
        groups[row[column]].append(row)
    for key in groups:
        groups[key].sort(key=lambda row: charts.parse_time(row["minute"]))
    return groups


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    folder, output = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else os.path.basename(os.path.dirname(os.path.abspath(folder)))
    bus = charts.read_csv(folder, "servicebus-metrics")
    instances = sorted(charts.read_csv(folder, "instances-per-minute"), key=lambda row: charts.parse_time(row["minute"]))
    plans = charts.read_csv(folder, "plan-metrics")

    figure, (load_axis, scale_axis, resource_axis) = plt.subplots(
        3, 1, figsize=(10, 8.5), sharex=True, gridspec_kw={"height_ratios": [2.2, 1, 1.3]})

    backlog_axis = load_axis.twinx()
    for index, (entity, rows) in enumerate(sorted(group_by(bus, "entity").items())):
        color = ENTITY_COLORS[index % len(ENTITY_COLORS)]
        times = [charts.parse_time(row["minute"]) for row in rows]
        load_axis.plot(times, charts.series(rows, "incomingMessages"), color=color, linestyle="--",
                       label=f"{entity}: incoming")
        load_axis.plot(times, charts.series(rows, "completeMessages"), color=color, linewidth=2,
                       label=f"{entity}: completed")
        backlog_axis.fill_between(times, charts.series(rows, "activeMessages"), color=color, alpha=0.12,
                                  step="mid", label=f"{entity}: backlog")
    load_axis.set_ylabel("Messages per minute")
    backlog_axis.set_ylabel("Active messages (shaded)")
    backlog_axis.set_ylim(bottom=0)
    load_axis.set_ylim(bottom=0)
    handles, labels = load_axis.get_legend_handles_labels()
    more_handles, more_labels = backlog_axis.get_legend_handles_labels()
    load_axis.legend(handles + more_handles, labels + more_labels, loc="upper right", fontsize=8, ncol=2)
    load_axis.set_title("Load: messages sent, messages processed and backlog")

    if instances:
        scale_axis.step([charts.parse_time(row["minute"]) for row in instances],
                        charts.series(instances, "instances"), where="mid", color="#107C10", linewidth=2)
    scale_axis.set_ylabel("Instances")
    scale_axis.set_ylim(0, max([1.0] + charts.series(instances, "instances")) + 1)
    scale_axis.yaxis.get_major_locator().set_params(integer=True)
    scale_axis.set_title("Scale-out: Logic App instances")

    for index, (plan, rows) in enumerate(sorted(group_by(plans, "plan").items())):
        times = [charts.parse_time(row["minute"]) for row in rows]
        suffix = ""
        if len(set(row["plan"] for row in plans)) > 1:
            suffix = " (high-priority plan)" if plan.endswith("-hi") else " (low-priority plan)"
        style = "-" if index == 0 else ":"
        resource_axis.plot(times, charts.series(rows, "cpuAvg"), color="#D83B01", linestyle=style,
                           label=f"CPU{suffix}")
        resource_axis.plot(times, charts.series(rows, "memoryAvg"), color="#5C2D91", linestyle=style,
                           label=f"Memory{suffix}")
    resource_axis.set_ylabel("Percent")
    resource_axis.set_ylim(0, 100)
    resource_axis.legend(loc="upper right", fontsize=8, ncol=2)
    resource_axis.set_title("Plan resources: CPU and memory (average)")
    resource_axis.set_xlabel("Time (UTC)")
    resource_axis.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))

    for axis in (load_axis, scale_axis, resource_axis):
        axis.grid(True, alpha=0.3)
    figure.suptitle(title, fontsize=12, fontweight="bold")
    figure.tight_layout()
    os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
    figure.savefig(output, dpi=110)
    plt.close(figure)
    print("wrote " + output)


if __name__ == "__main__":
    main()
