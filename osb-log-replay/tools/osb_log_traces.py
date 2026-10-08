#!/usr/bin/env python3
"""Step 3: turn exported OSB log events into traces and scenarios.

Input: events exported from Splunk (JSON lines from the REST export, or a CSV export with a _raw column) or a raw
WebLogic server log (events start with '####<'). Each event's OSB message is taken out of the WebLogic envelope,
matched against the log signatures from step 1, masked, and grouped by correlation id into a trace. Traces are
classified into scenarios: flow x outcome (success / error) x branch values (header fields by default).

Usage:
  osb_log_traces.py signatures.json events.jsonl|events.csv|server.log -o out/ [--format auto|splunk-json|csv|weblogic]
                    [--dims hdr_resource,hdr_eventType] [--mask-regex PATTERN ...] [--no-default-masks]
Writes out/traces.jsonl, out/scenarios.json, out/coverage.json. Stdlib only.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

WL_EVENT_START = re.compile(r"^####<", re.M)
WL_MESSAGE = re.compile(r"<(BEA-\d+)>\s*<(.*)>\s*$", re.S)
WL_TIME = re.compile(r"^####<([^>]+)>")
WL_EPOCH = re.compile(r"<(\d{13})>")
LOCATION_PREFIX = re.compile(r"^\s*\[[^\]]*\]\s*", re.S)        # [stage, pipeline, ..., REQUEST] written by OSB before the text
DEFAULT_MASKS = [r"(?<![\w-])\d{9,}(?![\w-])",                   # national / account / phone numbers (not digits inside UUIDs or codes)
                 r"[\w.+-]+@[\w-]+\.[\w.-]+"]                    # e-mail addresses


# ------------------------------------------------------------------ loading
def load_events(path: Path, fmt: str) -> list[dict]:
    text = path.read_text(encoding="utf-8", errors="replace")
    if fmt == "auto":
        if path.suffix == ".csv":
            fmt = "csv"
        elif text.lstrip().startswith("{"):
            fmt = "splunk-json"
        else:
            fmt = "weblogic"
    events = []
    if fmt == "splunk-json":
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            res = obj.get("result", obj)
            if "_raw" in res:
                events.append({"raw": res["_raw"], "time": res.get("_time")})
    elif fmt == "csv":
        for row in csv.DictReader(text.splitlines()):
            if row.get("_raw"):
                events.append({"raw": row["_raw"], "time": row.get("_time")})
    elif fmt == "weblogic":
        starts = [m.start() for m in WL_EVENT_START.finditer(text)] + [len(text)]
        for a, b in zip(starts, starts[1:]):
            raw = text[a:b].rstrip("\n")
            events.append({"raw": raw, "time": None})
    else:
        raise ValueError(fmt)
    for e in events:
        epoch = WL_EPOCH.search(e["raw"])
        if not e["time"]:
            m = WL_TIME.match(e["raw"])
            e["time"] = m.group(1) if m else None
        e["epoch_ms"] = int(epoch.group(1)) if epoch else None
    return events


def osb_message(raw: str) -> tuple[str, str | None]:
    """Return the OSB text without the WebLogic envelope and the location prefix, plus the BEA message id."""
    m = WL_MESSAGE.search(raw)
    if not m:
        return raw, None
    return LOCATION_PREFIX.sub("", m.group(2), count=1), m.group(1)


# ------------------------------------------------------------------ masking
class Masker:
    def __init__(self, patterns: list[str]):
        self.patterns = [re.compile(p) for p in patterns]
        self.count = 0

    def _sub(self, m: re.Match) -> str:
        self.count += 1
        s = m.group(0)
        h = hashlib.sha256(s.encode()).hexdigest()
        if s.isdigit():                                           # same length, digits only, same input -> same output
            return "".join(str(int(c, 16) % 10) for c in h)[: len(s)]
        return "masked_" + h[:10] + ("@example.invalid" if "@" in s else "")

    def __call__(self, value: str) -> str:
        for p in self.patterns:
            value = p.sub(self._sub, value)
        return value


# ------------------------------------------------------------------ matching
def compile_signatures(doc: dict) -> list[dict]:
    sigs = []
    for s in doc["signatures"]:
        if not s.get("regex"):
            continue
        s = dict(s)
        s["_re"] = re.compile(s["regex"], re.S)
        sigs.append(s)
    return sigs


def match(sigs: list[dict], message: str) -> tuple[dict, dict] | None:
    best = None
    for s in sigs:
        if s["anchor"] and s["anchor"].split()[0] not in message:
            continue
        m = s["_re"].fullmatch(message.strip()) or s["_re"].search(message)
        if m:
            literal_len = len(s["regex"]) - sum(len(g["name"]) for g in s["groups"])
            if best is None or literal_len > best[2]:            # the most specific signature wins
                best = (s, {k: (v or "").strip() for k, v in m.groupdict().items()}, literal_len)
    return (best[0], best[1]) if best else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("signatures", type=Path)
    ap.add_argument("events", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=Path("traces-out"))
    ap.add_argument("--format", default="auto", choices=["auto", "splunk-json", "csv", "weblogic"])
    ap.add_argument("--dims", default="", help="comma-separated fields that split scenarios (default: all hdr_* fields)")
    ap.add_argument("--mask-regex", action="append", default=[])
    ap.add_argument("--no-default-masks", action="store_true")
    args = ap.parse_args()

    sigs = compile_signatures(json.loads(args.signatures.read_text(encoding="utf-8")))
    masker = Masker(([] if args.no_default_masks else DEFAULT_MASKS) + args.mask_regex)
    events = load_events(args.events, args.format)
    traces, orphans, unmatched = defaultdict(list), 0, 0
    seen = Counter()
    for e in events:
        msg, bea = osb_message(e["raw"])
        hit = match(sigs, msg)
        if not hit:
            unmatched += 1
            continue
        s, fields = hit
        fields = {k: masker(v) for k, v in fields.items()}
        seen[s["id"]] += 1
        corr = next((fields[c] for c in s["roles"]["correlation"] if fields.get(c)), None)
        rec = {"time": e["time"], "epoch_ms": e["epoch_ms"], "signature": s["id"], "flow": s["flow"],
               "pipeline_type": s["pipeline_type"], "level": s["level"], "bea": bea, "fields": fields}
        if not corr:
            orphans += 1
            continue
        traces[(s["flow"], corr)].append(rec)

    args.out.mkdir(parents=True, exist_ok=True)
    dims_arg = [d for d in args.dims.split(",") if d]
    scen = defaultdict(lambda: {"count": 0, "examples": [], "with_payload": 0})
    with (args.out / "traces.jsonl").open("w", encoding="utf-8") as fh:
        for (flow, corr), evs in sorted(traces.items()):
            evs.sort(key=lambda r: (r["epoch_ms"] or 0))
            merged = {}
            for r in evs:
                for k, v in r["fields"].items():
                    merged.setdefault(k, v)
            outcome = "error" if any(r["pipeline_type"] == "error" for r in evs) else "success"
            dims = dims_arg or sorted(k for k in merged if k.startswith("hdr_"))
            branch = {d: merged.get(d, "?") for d in dims}
            fault_code = None
            if merged.get("fault"):
                m = re.search(r"<(?:\w+:)?errorCode>([^<]+)<", merged["fault"])
                fault_code = m.group(1) if m else "unparsed"
            key = "|".join([flow, outcome] + [f"{k}={v}" for k, v in branch.items()] + ([f"errorCode={fault_code}"] if fault_code else []))
            has_payload = bool(merged.get("body"))
            trace = {"flow": flow, "correlation": corr, "outcome": outcome, "branch": branch, "fault_code": fault_code,
                     "scenario": key, "has_payload": has_payload, "events": evs}
            fh.write(json.dumps(trace, ensure_ascii=False) + "\n")
            sc = scen[key]
            sc["count"] += 1
            sc["with_payload"] += int(has_payload)
            if len(sc["examples"]) < 5:
                sc["examples"].append(corr)

    total = sum(v["count"] for v in scen.values()) or 1
    scenarios = sorted(({"scenario": k, **v, "share": round(v["count"] / total * 100, 1)} for k, v in scen.items()),
                       key=lambda x: -x["count"])
    (args.out / "scenarios.json").write_text(json.dumps(scenarios, indent=2, ensure_ascii=False), encoding="utf-8")
    all_ids = [s["id"] for s in sigs]
    coverage = {"events_read": len(events), "events_matched": sum(seen.values()), "events_unmatched": unmatched,
                "events_without_correlation": orphans, "traces": len(traces), "masked_values": masker.count,
                "signatures_seen": dict(seen), "signatures_never_seen": [i for i in all_ids if i not in seen],
                "traces_without_payload": sum(1 for (f, c), evs in traces.items()
                                              if not any(r["fields"].get("body") for r in evs))}
    (args.out / "coverage.json").write_text(json.dumps(coverage, indent=2), encoding="utf-8")
    print(f"{coverage['events_read']} events, {coverage['events_matched']} matched, {coverage['traces']} traces, "
          f"{len(scenarios)} scenarios, {coverage['traces_without_payload']} traces without payload, "
          f"{len(coverage['signatures_never_seen'])} signatures never seen -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
