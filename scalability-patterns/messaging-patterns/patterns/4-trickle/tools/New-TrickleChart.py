"""Draws per-message e2e latency against send time for both workflows, with the send gap shown."""
import json
import os
import sys
from datetime import datetime

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


out_dir = sys.argv[1]
with open(os.path.join(out_dir, "per-message-latency.json"), encoding="utf-8") as handle:
    rows = json.load(handle)
fig, (top, bottom) = plt.subplots(2, 1, figsize=(12, 7), sharex=True, gridspec_kw={"height_ratios": [3, 1]})
for workflow, marker in (("trickle-stateful", "o"), ("trickle-stateless", "s")):
    points = sorted((parse(r["sentAt"]), r["e2eMs"] / 1000.0, r.get("gapSincePrevSendSec")) for r in rows if r["workflowName"] == workflow)
    if not points:
        continue
    top.plot([p[0] for p in points], [p[1] for p in points], marker=marker, linestyle="-", linewidth=0.6, markersize=3, label=workflow)
    idle = [p for p in points if p[2] is None or p[2] > 120]
    top.scatter([p[0] for p in idle], [p[1] for p in idle], s=80, facecolors="none", edgecolors="red")
    if workflow == "trickle-stateful":
        bottom.bar([p[0] for p in points], [p[2] or 0 for p in points], width=0.0004, color="grey")
top.set_ylabel("e2e latency (s)")
top.set_yscale("log")
top.set_title("4-trickle: per-message latency (red circles: first message after a >120 s gap)")
top.legend()
top.grid(True, which="both", alpha=0.3)
bottom.set_ylabel("gap before send (s)")
bottom.set_xlabel("send time (UTC)")
bottom.grid(True, alpha=0.3)
fig.tight_layout()
path = os.path.join(out_dir, "trickle-latency.png")
fig.savefig(path, dpi=110)
print(path)
