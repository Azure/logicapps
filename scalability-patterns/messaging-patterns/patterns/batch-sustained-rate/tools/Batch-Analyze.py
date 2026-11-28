"""Export batch-sustained Cosmos docs and compute rates, releases, latency and duplicates."""
import argparse, csv, json, os, sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), ".tools", "pylib"))


def parse(ts):
    ts = ts.replace("Z", "+00:00")
    if "+" not in ts[10:]:
        ts += "+00:00"
    if "." in ts:
        head, rest = ts.split(".", 1)
        idx = rest.index("+")
        frac, tz = rest[:idx], rest[idx:]
        ts = f"{head}.{frac[:6]}{tz}"
    return datetime.fromisoformat(ts)


def export(args):
    from azure.cosmos import CosmosClient
    from azure.identity import AzureCliCredential
    client = CosmosClient(args.endpoint, credential=AzureCliCredential())
    container = client.get_database_client("msgpat").get_container_client("items")
    cursor, stop = parse(args.since), parse(args.until)
    rows = 0
    q = ("SELECT c.messageId, c.releaseId, c.receiver, c.sentAtUtc, c.processedAtUtc FROM c "
         "WHERE c.pattern = @p AND c.sentAtUtc >= @s AND c.sentAtUtc < @e")
    with open(args.csv, "w", newline="") as handle:
        writer = csv.writer(handle)
        while cursor < stop:
            nxt = cursor + timedelta(seconds=args.slice)
            prm = [{"name": "@p", "value": args.pattern},
                   {"name": "@s", "value": cursor.strftime("%Y-%m-%dT%H:%M:%S")},
                   {"name": "@e", "value": nxt.strftime("%Y-%m-%dT%H:%M:%S")}]
            for attempt in range(8):
                try:
                    batch = [[i.get("messageId"), i.get("releaseId"), i.get("receiver"), i.get("sentAtUtc"), i.get("processedAtUtc")]
                             for i in container.query_items(q, parameters=prm, enable_cross_partition_query=True, max_item_count=5000)]
                    break
                except Exception as ex:
                    print(f"retry {cursor} {type(ex).__name__}", flush=True)
            else:
                raise RuntimeError(f"slice {cursor} failed")
            writer.writerows(batch)
            rows += len(batch)
            cursor = nxt
    print(f"exported {rows} rows to {args.csv}")


def pct(values, p):
    if not values:
        return None
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))]


def analyze(args):
    data = [r for r in csv.reader(open(args.csv)) if r and r[3] and r[4]]
    rows = [(m, rel, rcv, parse(s), parse(p)) for m, rel, rcv, s, p in data]
    dup = Counter(r[0] for r in rows)
    duplicates = sum(c - 1 for c in dup.values() if c > 1)
    unique = len(dup)
    releases = defaultdict(list)
    for r in rows:
        releases[r[1]].append(r)
    sizes = sorted(len(v) for v in releases.values())
    # release start = earliest processedAt per release (approximate release time)
    per_receiver = defaultdict(list)
    for rel, v in releases.items():
        per_receiver[v[0][2]].append(min(x[4] for x in v))
    intervals = []
    for rcv, times in per_receiver.items():
        times.sort()
        intervals += [(b - a).total_seconds() for a, b in zip(times, times[1:])]
    intervals.sort()
    # per-second processed and sent counts
    proc = Counter(int(r[4].timestamp()) for r in rows)
    sent = Counter(int(r[3].timestamp()) for r in rows)
    lat = sorted((r[4] - r[3]).total_seconds() for r in rows)
    result = {
        "docs": len(rows), "uniqueMessages": unique, "duplicates": duplicates,
        "releases": len(releases), "receivers": len(per_receiver),
        "releaseSizeP50": pct(sizes, 50), "releaseSizeMax": sizes[-1] if sizes else None,
        "releaseSizeMean": round(sum(sizes) / len(sizes), 1) if sizes else None,
        "releaseIntervalP50": pct(intervals, 50), "releaseIntervalP95": pct(intervals, 95),
        "latencyP50": pct(lat, 50), "latencyP95": pct(lat, 95), "latencyMax": lat[-1] if lat else None,
        "firstProcessed": min(r[4] for r in rows).isoformat() if rows else None,
        "lastProcessed": max(r[4] for r in rows).isoformat() if rows else None,
    }
    if args.phases:
        ph = json.load(open(args.phases))["phases"]
        win = [p for p in ph if p["name"] == args.window] if args.window else ph[-1:]
        start, end = parse(win[0]["startUtc"]), parse(win[0]["endUtc"])
        secs = (end - start).total_seconds()
        n = sum(c for t, c in proc.items() if start.timestamp() <= t < end.timestamp())
        s = sum(c for t, c in sent.items() if start.timestamp() <= t < end.timestamp())
        result["window"] = win[0]["name"]
        result["windowProcessedPerSec"] = round(n / secs, 1)
        result["windowSentPerSecInCosmos"] = round(s / secs, 1)
        rel_in = [v for v in releases.values() if start <= min(x[4] for x in v) < end]
        result["windowReleases"] = len(rel_in)
        rs = sorted(len(v) for v in rel_in)
        result["windowReleaseSizeP50"] = pct(rs, 50)
        result["windowReleaseSizeMean"] = round(sum(rs) / len(rs), 1) if rs else None
        wl = sorted((r[4] - r[3]).total_seconds() for r in rows if start <= r[3] < end)
        result["windowSentProcessed"] = len({r[0] for r in rows if start <= r[3] < end})
        result["windowLatencyP50"] = pct(wl, 50)
        result["windowLatencyP95"] = pct(wl, 95)
        result["releaseUniqueSizeMax"] = max(len({x[0] for x in v}) for v in releases.values())
    if args.persec:
        lo, hi = min(min(proc), min(sent)), max(max(proc), max(sent))
        with open(args.persec, "w", newline="") as h:
            w = csv.writer(h)
            w.writerow(["epoch", "utc", "sent", "processed"])
            for t in range(lo, hi + 1):
                w.writerow([t, datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), sent.get(t, 0), proc.get(t, 0)])
    if args.releasecsv:
        with open(args.releasecsv, "w", newline="") as h:
            w = csv.writer(h)
            w.writerow(["releaseId", "receiver", "firstProcessedUtc", "size"])
            for rel, v in sorted(releases.items(), key=lambda kv: min(x[4] for x in kv[1])):
                w.writerow([rel, v[0][2], min(x[4] for x in v).strftime("%Y-%m-%dT%H:%M:%S.%fZ"), len(v)])
    print(json.dumps(result, indent=2))
    if args.out:
        json.dump(result, open(args.out, "w"), indent=2)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")
    e = sub.add_parser("export")
    e.add_argument("--endpoint", required=True); e.add_argument("--pattern", required=True)
    e.add_argument("--since", required=True); e.add_argument("--until", required=True)
    e.add_argument("--slice", type=int, default=60); e.add_argument("--csv", required=True)
    a = sub.add_parser("analyze")
    a.add_argument("--csv", required=True); a.add_argument("--phases"); a.add_argument("--window")
    a.add_argument("--persec"); a.add_argument("--releasecsv"); a.add_argument("--out")
    args = ap.parse_args()
    export(args) if args.cmd == "export" else analyze(args)
