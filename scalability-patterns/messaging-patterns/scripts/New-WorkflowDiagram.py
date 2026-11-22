"""Draws a block diagram of a Logic Apps workflow from its workflow.json.

Usage:
    python scripts/New-WorkflowDiagram.py <workflow.json> <outputPng> [title]

The layout follows the designer: the trigger on top, then actions in run order.
Actions that run after the same predecessors sit side by side. For each and Until
loops are frames around their actions; conditions show True and False columns.
This is a generated diagram, not a designer screenshot.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module  # noqa: E402

plt = import_module("New-Charts").plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch  # noqa: E402

CARD_WIDTH = 3.4
CARD_HEIGHT = 0.78
GAP_X = 0.35
GAP_Y = 0.45
PAD = 0.25
HEADER = 0.45

COLORS = {
    "trigger": "#0078D4",
    "servicebus": "#0F6CBD",
    "cosmos": "#107C10",
    "blob": "#008575",
    "Workflow": "#5C2D91",
    "Http": "#C239B3",
    "Liquid": "#CA5010",
    "InvokeFunction": "#986F0B",
    "Response": "#0078D4",
    "Wait": "#8A8886",
    "default": "#605E5C",
}

FRAME_TYPES = {"Foreach": "For each", "Until": "Until", "Scope": "Scope"}


def humanize(name):
    return name.replace("_", " ")


def provider_family(action):
    config = action.get("inputs", {}).get("serviceProviderConfiguration", {})
    service = (config.get("serviceProviderId", "") + config.get("connectionName", "")).lower()
    if "servicebus" in service:
        return "servicebus", "Service Bus"
    if "cosmos" in service:
        return "cosmos", "Azure Cosmos DB"
    if "blob" in service:
        return "blob", "Azure Blob Storage"
    return "default", config.get("connectionName", "Built-in connector")


def describe(action):
    kind = action.get("type", "")
    inputs = action.get("inputs", {}) if isinstance(action.get("inputs"), dict) else {}
    if kind == "ServiceProvider":
        family, label = provider_family(action)
        operation = humanize_operation(inputs.get("serviceProviderConfiguration", {}).get("operationId", ""))
        return family, f"{label}: {operation}"
    if kind == "Workflow":
        target = inputs.get("host", {}).get("workflow", {}).get("id", "child workflow")
        return "Workflow", f"Call workflow: {target}"
    if kind == "Http":
        return "Http", f"HTTP {inputs.get('method', '')}".strip()
    if kind == "Wait":
        interval = inputs.get("interval", {})
        return "Wait", f"Delay {interval.get('count', '')} {interval.get('unit', '').lower()}".strip()
    labels = {
        "Liquid": "Transform JSON with Liquid",
        "InvokeFunction": "Call local C# function",
        "Response": "Response",
        "Compose": "Compose",
        "Select": "Data operations: Select",
        "InitializeVariable": "Initialize variable",
        "SetVariable": "Set variable",
        "IncrementVariable": "Increment variable",
        "AppendToArrayVariable": "Append to array variable",
    }
    return (kind if kind in COLORS else "default"), labels.get(kind, kind)


def humanize_operation(operation):
    words = []
    current = ""
    for character in operation:
        if character.isupper() and current:
            words.append(current)
            current = character.lower()
        else:
            current += character
    words.append(current)
    return " ".join(words).capitalize()


def ordered_rows(actions):
    """Groups actions into rows by longest runAfter path, like the designer."""
    depth = {}

    def level(name):
        if name not in depth:
            after = [parent for parent in (actions[name].get("runAfter") or {}) if parent in actions]
            depth[name] = 0 if not after else 1 + max(level(parent) for parent in after)
        return depth[name]

    for name in actions:
        level(name)
    rows = []
    for name in actions:
        while len(rows) <= depth[name]:
            rows.append([])
        rows[depth[name]].append(name)
    return rows


class Node:
    def __init__(self, name, action):
        self.name = name
        self.action = action
        kind = action.get("type")
        self.columns = []
        if kind in FRAME_TYPES:
            self.columns = [("", action.get("actions", {}))]
        elif kind == "If":
            self.columns = [("True", action.get("actions", {})),
                            ("False", (action.get("else") or {}).get("actions", {}))]
        elif kind == "Switch":
            self.columns = [(case, value.get("actions", {})) for case, value in action.get("cases", {}).items()]
            self.columns.append(("Default", (action.get("default") or {}).get("actions", {})))
        self.children = [Block(actions) for _, actions in self.columns]
        if self.columns:
            inner_width = sum(child.width for child in self.children) + GAP_X * (len(self.children) - 1)
            inner_height = max(child.height for child in self.children)
            label_height = 0.3 if kind in ("If", "Switch") else 0
            self.width = max(CARD_WIDTH, inner_width + 2 * PAD)
            self.height = HEADER + label_height + inner_height + PAD
        else:
            self.width = CARD_WIDTH
            self.height = CARD_HEIGHT

    def draw(self, axis, x_left, y_top):
        kind = self.action.get("type")
        if not self.columns:
            family, subtitle = describe(self.action)
            card(axis, x_left, y_top, self.width, self.height, humanize(self.name), subtitle, COLORS[family])
            return
        frame_label = FRAME_TYPES.get(kind, "Condition" if kind == "If" else kind)
        axis.add_patch(FancyBboxPatch((x_left, y_top), self.width, self.height,
                                      boxstyle="round,pad=0,rounding_size=0.08", linewidth=1.2,
                                      edgecolor="#8A8886", facecolor="#F3F2F1", linestyle="--"))
        axis.text(x_left + 0.15, y_top + HEADER / 2, f"{frame_label}: {humanize(self.name)}",
                  va="center", ha="left", fontsize=9, fontweight="bold", color="#323130")
        inner_width = sum(child.width for child in self.children) + GAP_X * (len(self.children) - 1)
        x = x_left + (self.width - inner_width) / 2
        y = y_top + HEADER
        for (label, _), child in zip(self.columns, self.children):
            child_y = y
            if label:
                axis.text(x + child.width / 2, y + 0.12, label, ha="center", va="center", fontsize=8,
                          color="#107C10" if label == "True" else "#A4262C", fontweight="bold")
                child_y = y + 0.3
            if child.rows:
                child.draw(axis, x, child_y)
            else:
                axis.text(x + child.width / 2, child_y + 0.3, "(no actions)", ha="center", va="center",
                          fontsize=8, color="#8A8886", style="italic")
            x += child.width + GAP_X


class Block:
    def __init__(self, actions):
        self.rows = [[Node(name, actions[name]) for name in row] for row in ordered_rows(actions)]
        widths = [sum(node.width for node in row) + GAP_X * (len(row) - 1) for row in self.rows]
        self.width = max([CARD_WIDTH] + widths)
        self.height = sum(max(node.height for node in row) for row in self.rows) + GAP_Y * max(0, len(self.rows) - 1)
        if not self.rows:
            self.height = 0.6

    def draw(self, axis, x_left, y_top, entry=None):
        """Draws rows and connects each action to the actions it runs after."""
        y = y_top
        bottoms = {}
        for row in self.rows:
            row_width = sum(node.width for node in row) + GAP_X * (len(row) - 1)
            x = x_left + (self.width - row_width) / 2
            for node in row:
                top = (x + node.width / 2, y)
                run_after = node.action.get("runAfter") or {}
                parents = [parent for parent in run_after if parent in bottoms]
                for parent in parents:
                    statuses = [status for status in run_after[parent] if status != "Succeeded"]
                    arrow(axis, bottoms[parent], top, label=", ".join(statuses).lower())
                if not parents and entry:
                    arrow(axis, entry, top)
                node.draw(axis, x, y)
                bottoms[node.name] = (x + node.width / 2, y + node.height)
                x += node.width + GAP_X
            y += max(node.height for node in row) + GAP_Y


def card(axis, x_left, y_top, width, height, title, subtitle, color):
    axis.add_patch(FancyBboxPatch((x_left, y_top), width, height, boxstyle="round,pad=0,rounding_size=0.08",
                                  linewidth=1, edgecolor="#C8C6C4", facecolor="white"))
    axis.add_patch(FancyBboxPatch((x_left, y_top), 0.12, height, boxstyle="square,pad=0",
                                  linewidth=0, facecolor=color))
    axis.text(x_left + 0.25, y_top + height * 0.36, title, va="center", ha="left", fontsize=9,
              fontweight="bold", color="#201F1E")
    axis.text(x_left + 0.25, y_top + height * 0.72, subtitle, va="center", ha="left", fontsize=7.5,
              color="#605E5C")


def arrow(axis, start, end, label=""):
    color = "#A4262C" if label else "#8A8886"
    axis.add_patch(FancyArrowPatch(start, end, arrowstyle="-|>", mutation_scale=10, color=color,
                                   linewidth=1, linestyle="--" if label else "-",
                                   connectionstyle="arc3,rad=0", shrinkA=0, shrinkB=1))
    if label:
        axis.text((start[0] + end[0]) / 2, (start[1] + end[1]) / 2, "if " + label, ha="center", va="center",
                  fontsize=7, color=color, bbox={"facecolor": "white", "edgecolor": "none", "pad": 1})


def trigger_details(trigger):
    kind = trigger.get("type")
    inputs = trigger.get("inputs", {})
    runtime = trigger.get("runtimeConfiguration", {}).get("concurrency", {})
    lines = []
    if kind == "Recurrence":
        recurrence = trigger.get("recurrence", {})
        lines.append(f"Recurrence: every {recurrence.get('interval')} {recurrence.get('frequency', '').lower()}")
    elif kind == "Request":
        lines.append("When an HTTP request is received")
    else:
        parameters = inputs.get("parameters", {})
        operation = humanize_operation(inputs.get("serviceProviderConfiguration", {}).get("operationId", ""))
        queue = parameters.get("queueName", parameters.get("topicName", ""))
        lines.append(f"Service Bus: {operation}" + (f" ({queue})" if queue else ""))
        if "isSessionsEnabled" in parameters or "Session" in operation or "session" in operation:
            lines[-1] += ", sessions"
        if kind == "ServiceProvider" and "recurrence" not in trigger:
            lines.append("Split on: " + ("on" if "splitOn" in trigger else "off (batch of messages)"))
        if parameters.get("maxMessageBatchSize"):
            lines.append(f"Batch size: {parameters['maxMessageBatchSize']}")
    if runtime.get("runs"):
        lines.append(f"Concurrency: {runtime['runs']} runs")
    return lines


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    with open(sys.argv[1], encoding="utf-8-sig") as handle:
        document = json.load(handle)
    output = sys.argv[2]
    workflow_name = os.path.basename(os.path.dirname(os.path.abspath(sys.argv[1])))
    title = sys.argv[3] if len(sys.argv) > 3 else workflow_name
    definition = document["definition"]
    trigger_name, trigger = next(iter(definition.get("triggers", {}).items()))
    details = trigger_details(trigger)
    body = Block(definition.get("actions", {}))

    trigger_height = 0.45 + 0.25 * len(details)
    width = max(body.width, CARD_WIDTH + 0.6)
    total_height = 0.7 + trigger_height + GAP_Y + body.height + 0.3
    figure, axis = plt.subplots(figsize=(max(5.5, (width + 0.6) * 1.15), max(2.5, total_height * 1.05)))
    axis.set_xlim(-0.3, width + 0.3)
    axis.set_ylim(total_height, 0)
    axis.axis("off")

    axis.text(width / 2, 0.3, f"{title}  ({document.get('kind', 'Stateful')})", ha="center", va="center",
              fontsize=11, fontweight="bold", color="#201F1E")
    trigger_left = (width - CARD_WIDTH - 0.6) / 2
    trigger_top = 0.6
    axis.add_patch(FancyBboxPatch((trigger_left, trigger_top), CARD_WIDTH + 0.6, trigger_height,
                                  boxstyle="round,pad=0,rounding_size=0.08", linewidth=1,
                                  edgecolor=COLORS["trigger"], facecolor="#EFF6FC"))
    trigger_title = humanize(trigger_name)
    if len(trigger_title) > 36:
        trigger_title = trigger_title[:34].rstrip() + "…"
    axis.text(trigger_left + 0.2, trigger_top + 0.25, "Trigger: " + trigger_title, va="center",
              ha="left", fontsize=9, fontweight="bold", color="#201F1E")
    for index, line in enumerate(details):
        axis.text(trigger_left + 0.2, trigger_top + 0.52 + 0.25 * index, line, va="center", ha="left",
                  fontsize=7.5, color="#323130")

    entry = (width / 2, trigger_top + trigger_height)
    body.draw(axis, (width - body.width) / 2, entry[1] + GAP_Y, entry=entry)
    os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
    figure.savefig(output, dpi=110, bbox_inches="tight")
    plt.close(figure)
    print("wrote " + output)


if __name__ == "__main__":
    main()
