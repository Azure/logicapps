"""Exports one batch-deadline run from Application Insights and Azure Monitor, then draws the charts.

Usage (Azure CLI signed in, matplotlib installed):
    python Export-Run.py <runFolder> <appInsightsAppId> <planResourceId> <endUtc>

The run folder must hold t0.txt (the moment ingress was enabled) and backlog.csv (utc,elapsedSeconds,active),
which the run steps in the README write. Writes CSVs, summary.json and PNG charts into the run folder.
"""
import csv
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

# The Azure CLI Python ignores PYTHONPATH, so add the kit's library folder explicitly.
_PYLIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".tools", "pylib")
if os.path.isdir(_PYLIB):
    sys.path.insert(0, os.path.normpath(_PYLIB))

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

BACKLOG = 100000
DEADLINE_MINUTES = 10
CHILD = "process-batch-item"


def parse_time(text):
    text = text.strip().replace("Z", "+00:00")
    if "." in text:
        head, tail = text.split(".", 1)
        frac, _, zone = tail.partition("+")
        text = f"{head}.{frac[:6]}+{zone or '00:00'}"
    return datetime.fromisoformat(text).astimezone(timezone.utc)


def az(args):
    output = subprocess.run("az " + args, shell=True, capture_output=True, text=True, check=True).stdout
    return json.loads(output)


def query(app_id, kql):
    kql = " ".join(line.strip() for line in kql.strip().splitlines())
    path = os.path.join(RUN, "_query.kql")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(kql)
    try:
        result = az(f'monitor app-insights query --app {app_id} --analytics-query "@{path}" -o json')
    finally:
        os.remove(path)
    table = result["tables"][0]
    names = [column["name"] for column in table["columns"]]
    return [dict(zip(names, row)) for row in table["rows"]]


def write_csv(name, rows):
    if not rows:
        return
    with open(os.path.join(RUN, name), "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


RUN, APP, PLAN, END = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(os.path.join(RUN, "t0.txt"), encoding="utf-8") as handle:
    T0 = parse_time(handle.read())
END_TIME = parse_time(END)
# NOTE: start on a whole minute so the range rows line up with bin(timestamp, 10s).
START = (T0 - timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:00Z")
STOP = END_TIME.strftime("%Y-%m-%dT%H:%M:%SZ")
WINDOW = f"where timestamp between (datetime({START}) .. datetime({STOP}))"
ACTS = (
    f"requests | {WINDOW} | extend r = parse_json(tostring(customDimensions.resource)) "
    "| extend wf = tostring(r.workflowName), act = tostring(r.actionName), "
    "cat = tostring(customDimensions.Category), finishedAt = timestamp + totimespan(duration * 10000)"
)

timeline = query(APP, f"""
let a = {ACTS};
let inst = union requests, traces | {WINDOW} | where cloud_RoleInstance != ''
  | summarize instances = dcount(cloud_RoleInstance) by bin10 = bin(timestamp, 10s);
let pulled = a | where cat == 'Workflow.Operations.Triggers' and wf startswith 'orders-ingress'
  | summarize pulled = count() by bin10 = bin(timestamp, 10s);
let pushed = a | where act == 'Send_to_batch'
  | summarize pushed = count(), pushed1 = countif(wf == 'orders-ingress'), pushed2 = countif(wf == 'orders-ingress-2')
  by bin10 = bin(finishedAt, 10s);
let released = a | where act == 'Process_batch'
  | summarize releases = count(), releases1 = countif(wf == 'orders-receiver'), releases2 = countif(wf == 'orders-receiver-2')
  by bin10 = bin(timestamp, 10s);
let items = a | where cat == 'Workflow.Operations.Triggers' and wf == '{CHILD}'
  | summarize itemsReleased = count() by bin10 = bin(timestamp, 10s);
let processed = a | where act == 'Process_order' and wf == '{CHILD}'
  | summarize processed = count(), failed = countif(success == false) by bin10 = bin(finishedAt, 10s);
range bin10 from datetime({START}) to datetime({STOP}) step 10s
| join kind=leftouter inst on bin10 | join kind=leftouter pulled on bin10 | join kind=leftouter pushed on bin10
| join kind=leftouter released on bin10 | join kind=leftouter items on bin10 | join kind=leftouter processed on bin10
| project bin10, instances = coalesce(instances, 0), pulled = coalesce(pulled, 0), pushed = coalesce(pushed, 0),
  pushed1 = coalesce(pushed1, 0), pushed2 = coalesce(pushed2, 0), releases = coalesce(releases, 0),
  releases1 = coalesce(releases1, 0), releases2 = coalesce(releases2, 0), itemsReleased = coalesce(itemsReleased, 0),
  processed = coalesce(processed, 0), failed = coalesce(failed, 0)
| order by bin10 asc
""")
write_csv("timeline-per-10s.csv", timeline)

latency = query(APP, f"""
{ACTS}
| where act == 'Process_order' and wf == '{CHILD}'
| extend tp = parse_json(tostring(customDimensions.trackedProperties))
| extend sentAt = todatetime(tp.sentAtUtc), enqueuedAt = todatetime(tp.enqueuedTimeUtc)
| extend e2eMs = datetime_diff('millisecond', finishedAt, sentAt),
  sinceStartMs = datetime_diff('millisecond', finishedAt, datetime({T0.strftime('%Y-%m-%dT%H:%M:%S.%fZ')}))
| summarize processed = count(), failed = countif(success == false), firstFinished = min(finishedAt), lastFinished = max(finishedAt),
  firstSent = min(sentAt), lastSent = max(sentAt),
  e2eP50 = percentile(e2eMs, 50), e2eP95 = percentile(e2eMs, 95), e2eP99 = percentile(e2eMs, 99),
  sinceStartP50 = percentile(sinceStartMs, 50), sinceStartP95 = percentile(sinceStartMs, 95),
  childP50 = percentile(duration, 50), childP95 = percentile(duration, 95), childP99 = percentile(duration, 99)
""")
write_csv("end-to-end-latency.csv", latency)

totals = query(APP, f"""
{ACTS}
| summarize rows = count(), failed = countif(success == false), firstAt = min(timestamp), lastAt = max(timestamp),
  p50Ms = percentile(duration, 50), p95Ms = percentile(duration, 95) by wf, act, cat
| order by wf asc, act asc
""")
write_csv("workflow-totals.csv", totals)

instances = query(APP, f"""
union requests, traces | {WINDOW} | where cloud_RoleInstance != ''
| summarize instances = dcount(cloud_RoleInstance), busy = dcountif(cloud_RoleInstance, itemType == 'request')
  by minute = bin(timestamp, 1m)
| order by minute asc
""")
write_csv("instances-per-minute.csv", instances)

metrics = az(
    f'monitor metrics list --resource "{PLAN}" --metric CpuPercentage MemoryPercentage --interval PT1M '
    f"--aggregation Average Maximum --start-time {START} --end-time {STOP} -o json"
)
plan = {}
for metric in metrics["value"]:
    name = metric["name"]["value"]
    for series in metric["timeseries"]:
        for point in series["data"]:
            row = plan.setdefault(point["timeStamp"], {"minute": point["timeStamp"]})
            row[name + "Average"] = point.get("average")
            row[name + "Maximum"] = point.get("maximum")
plan_rows = [plan[key] for key in sorted(plan)]
write_csv("plan-metrics.csv", plan_rows)

with open(os.path.join(RUN, "backlog.csv"), encoding="utf-8") as handle:
    backlog = [(float(row["elapsedSeconds"]), int(row["active"])) for row in csv.DictReader(handle)]

# Summary.
first_drop = next(seconds for seconds, count in backlog if count < BACKLOG)
queue_empty = next(seconds for seconds, count in backlog if count == 0)
stats = latency[0] if latency else {}
processed = int(stats.get("processed") or 0)
pulled_total = sum(int(row["pulled"]) for row in timeline)
pushed_total = sum(int(row["pushed"]) for row in timeline)
peak_rate = max((int(row["processed"]) / 10.0 for row in timeline), default=0)
cpu_peak = max((row.get("CpuPercentageMaximum") or 0 for row in plan_rows), default=0)
cpu_avg_peak = max((row.get("CpuPercentageAverage") or 0 for row in plan_rows), default=0)
mem_peak = max((row.get("MemoryPercentageMaximum") or 0 for row in plan_rows), default=0)
first_finished = stats.get("firstFinished")
last_finished = stats.get("lastFinished")
processing_seconds = (
    (parse_time(last_finished) - parse_time(first_finished)).total_seconds() if first_finished and last_finished else 0
)
summary = {
    "pattern": "batch-deadline",
    "runId": os.path.basename(os.path.normpath(RUN)),
    "workflowName": CHILD,
    "windowStartUtc": START,
    "windowEndUtc": STOP,
    "t0Utc": T0.isoformat().replace("+00:00", "Z"),
    "deadlineMinutes": DEADLINE_MINUTES,
    "deadlineUtc": (T0 + timedelta(minutes=DEADLINE_MINUTES)).isoformat().replace("+00:00", "Z"),
    "requiredMessagesPerSecond": round(BACKLOG / (DEADLINE_MINUTES * 60.0), 1),
    "messagesSent": BACKLOG,
    "queueFirstDropSeconds": first_drop,
    "queueEmptySeconds": queue_empty,
    "queueDrainRatePerSecond": round(BACKLOG / (queue_empty - first_drop), 1),
    "ingressTriggerRuns": pulled_total,
    "sendToBatchCompleted": pushed_total,
    "releases": sum(int(row["releases"]) for row in timeline),
    "itemsReleased": sum(int(row["itemsReleased"]) for row in timeline),
    "runsCompleted": processed,
    "runsFailed": int(stats.get("failed") or 0),
    "processingComplete": processed >= BACKLOG,
    "avgMessagesPerSecond": round(processed / processing_seconds, 2) if processing_seconds else 0,
    "peakRunsPerSecond": peak_rate,
    "endToEndLatencyMs": {"p50": stats.get("e2eP50"), "p95": stats.get("e2eP95"), "p99": stats.get("e2eP99")},
    "sinceStartMs": {"p50": stats.get("sinceStartP50"), "p95": stats.get("sinceStartP95")},
    "childActionMs": {"p50": stats.get("childP50"), "p95": stats.get("childP95"), "p99": stats.get("childP99")},
    "maxInstances": max((int(row["instances"]) for row in instances), default=0),
    "maxBusyInstances": max((int(row["busy"]) for row in instances), default=0),
    "cpuPercentPeakPerInstance": cpu_peak,
    "cpuPercentPeakPlanAverage": cpu_avg_peak,
    "memoryPercentPeak": mem_peak,
    "firstSentUtc": stats.get("firstSent"),
    "lastFinishedUtc": last_finished,
    "failedActions": sum(int(row["failed"]) for row in totals),
}
with open(os.path.join(RUN, "summary.json"), "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)

# Charts. The x axis is minutes since T0.
def minutes(text):
    return (parse_time(text) - T0).total_seconds() / 60.0


xs = [minutes(row["bin10"]) for row in timeline]
deadline_line = DEADLINE_MINUTES
drop_deadline = first_drop / 60.0 + DEADLINE_MINUTES

fig, ax = plt.subplots(figsize=(10, 5))
ax.plot([seconds / 60.0 for seconds, _ in backlog], [count for _, count in backlog], label="queue backlog (orders)")
remaining = BACKLOG
outstanding = []
for row in timeline:
    remaining -= int(row["processed"])
    outstanding.append(remaining)
ax.plot(xs, outstanding, label="not yet processed (100,000 - process-order runs)")
ax.plot([0, deadline_line], [BACKLOG, 0], "k:", label="required pace from T0 (167 msg/s)")
ax.axvline(deadline_line, color="red", linestyle="--", label="deadline T0 + 10 min")
ax.axvline(drop_deadline, color="orange", linestyle="--", label="first drop + 10 min")
ax.set_xlabel("minutes since ingress enabled (T0)")
ax.set_ylabel("messages")
ax.set_title("Backlog against the 10-minute deadline")
ax.legend()
ax.grid(alpha=0.3)
fig.savefig(os.path.join(RUN, "backlog-vs-deadline.png"), dpi=110, bbox_inches="tight")
plt.close(fig)

fig, ax = plt.subplots(figsize=(10, 5))
ax.plot(xs, [int(row["pulled"]) / 10.0 for row in timeline], label="ingress runs started (queue reads)")
ax.plot(xs, [int(row["pushed"]) / 10.0 for row in timeline], label="Send_to_batch finished (into batch)")
ax.plot(xs, [int(row["processed"]) / 10.0 for row in timeline], label="process-order finished")
ax.axhline(BACKLOG / (DEADLINE_MINUTES * 60.0), color="red", linestyle="--", label="required 167 msg/s")
ax.set_xlabel("minutes since T0")
ax.set_ylabel("messages per second (10 s bins)")
ax.set_title("Incoming against processing rate")
ax.legend()
ax.grid(alpha=0.3)
fig.savefig(os.path.join(RUN, "incoming-vs-processing.png"), dpi=110, bbox_inches="tight")
plt.close(fig)

fig, ax = plt.subplots(figsize=(10, 5))
ax.bar(xs, [int(row["itemsReleased"]) for row in timeline], width=0.15, label="items released per 10 s (both receivers)")
ax2 = ax.twinx()
ax2.plot(xs, [int(row["releases1"]) for row in timeline], "g.", label="orders-receiver releases")
ax2.plot(xs, [int(row["releases2"]) for row in timeline], "m.", label="orders-receiver-2 releases")
ax.axhline(2 * 100 * 10, color="red", linestyle="--", label="ceiling: 2 x 100 per second")
ax.set_xlabel("minutes since T0")
ax.set_ylabel("items per 10 s")
ax2.set_ylabel("releases per 10 s")
ax.set_title("Release size (messageCountLimit 100 per receiver per second)")
ax.legend(loc="upper left")
ax2.legend(loc="upper right")
ax.grid(alpha=0.3)
fig.savefig(os.path.join(RUN, "release-size.png"), dpi=110, bbox_inches="tight")
plt.close(fig)

fig, ax = plt.subplots(figsize=(10, 4))
ax.step([minutes(row["minute"]) for row in instances], [int(row["instances"]) for row in instances], where="post",
        label="instances sending telemetry")
ax.step([minutes(row["minute"]) for row in instances], [int(row["busy"]) for row in instances], where="post",
        label="instances running workflows")
ax.set_xlabel("minutes since T0")
ax.set_ylabel("instances")
ax.set_title("Instances per minute (WS1, minimum 2, burst 20, scale monitoring on)")
ax.legend()
ax.grid(alpha=0.3)
fig.savefig(os.path.join(RUN, "instances.png"), dpi=110, bbox_inches="tight")
plt.close(fig)

fig, ax = plt.subplots(figsize=(10, 4))
px = [minutes(row["minute"]) for row in plan_rows]
for key, label in [
    ("CpuPercentageAverage", "CPU % (plan average)"),
    ("CpuPercentageMaximum", "CPU % (busiest instance)"),
    ("MemoryPercentageAverage", "memory % (plan average)"),
    ("MemoryPercentageMaximum", "memory % (busiest instance)"),
]:
    ax.plot(px, [row.get(key) for row in plan_rows], label=label)
ax.set_xlabel("minutes since T0")
ax.set_ylabel("percent")
ax.set_ylim(0, 100)
ax.set_title("Plan CPU and memory per minute")
ax.legend()
ax.grid(alpha=0.3)
fig.savefig(os.path.join(RUN, "cpu-memory.png"), dpi=110, bbox_inches="tight")
plt.close(fig)

print(json.dumps(summary, indent=2))
