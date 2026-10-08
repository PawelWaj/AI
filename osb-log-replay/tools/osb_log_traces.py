#!/usr/bin/env python3
"""Step 3: turn exported OSB log events into traces and scenarios.

Input: events exported from Splunk (JSON lines from the REST export, or a CSV export with a _raw column) or a raw
server log in either format OSB writes: the classic WebLogic server log (events start with '####<') or the ODL
diagnostic log of OSB 12c ('[2026-10-08T11:59:16.339+03:00] [osb_server1] [NOTIFICATION] ... [ecid: ...]
[FlowId: ...]  [stage, pipeline, REQUEST] text'). Each event's OSB text is taken out of its envelope,
matched against the log signatures from step 1, masked, and grouped by correlation id into a trace. Traces are
classified into scenarios: flow x outcome (success / error) x branch values (header fields by default).

Usage:
  osb_log_traces.py signatures.json events.jsonl|events.csv|server.log -o out/
                    [--format auto|splunk-json|csv|weblogic|odl|lines] [--dims hdr_resource,hdr_eventType]
                    [--mask-regex PATTERN ...] [--mask-json-key KEY ...] [--no-default-masks] [--no-default-json-keys]
Personal data is masked in every extracted field: long numbers, e-mail addresses, and the values of JSON fields with
personal names, birth dates, identity and contact data (defaults below; add client-specific keys with --mask-json-key).
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
from datetime import datetime
from pathlib import Path

WL_EVENT_START = re.compile(r"^####<", re.M)
WL_MESSAGE = re.compile(r"<(BEA-\d+)>\s*<(.*)>\s*$", re.S)
WL_TIME = re.compile(r"^####<([^>]+)>")
WL_EPOCH = re.compile(r"<(\d{13})>")
LOCATION_PREFIX = re.compile(r"^\s*\[[^\]]*\]\s*", re.S)        # [stage, pipeline, ..., REQUEST] written by OSB before the text
ODL_EVENT_START = re.compile(r"^\[\d{4}-\d{2}-\d{2}T[^\]]*\]", re.M)
ODL_TIME = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T[^\]]+)\]")
ODL_LEVEL = re.compile(r"^\[[^\]]*\]\s*\[[^\]]*\]\s*\[([A-Z_]+)(?::\d+)?\]")
ODL_ECID = re.compile(r"\[ecid:\s*([^\],]+)")
ODL_FLOWID = re.compile(r"\[FlowId:\s*([^\]]+)\]")
ODL_LOCATION = re.compile(r"\[[^\[\]]*,\s*(?:REQUEST|RESPONSE|ERROR_HANDLER|ROUTING|ROUTE|NONE)\]\s?")
DEFAULT_JSON_KEYS = ["firstName", "secondName", "thirdName", "middleName", "lastName", "surName", "familyName", "fullName",
                     "nameEnglish", "nameArabic", "englishName", "arabicName", "birthDate", "dateOfBirth", "dob",
                     "email", "mobile", "mobileNo", "phone", "phoneNo", "address", "passportNo", "iqamaNo",
                     "nationalId", "nin", "newNin", "oldNin", "socialInsuranceNo", "iban", "accountNo"]
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
        elif WL_EVENT_START.search(text):
            fmt = "weblogic"
        elif ODL_EVENT_START.search(text):
            fmt = "odl"
        else:
            fmt = "lines"
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
    elif fmt in ("weblogic", "odl"):
        start = WL_EVENT_START if fmt == "weblogic" else ODL_EVENT_START
        starts = [m.start() for m in start.finditer(text)] + [len(text)]
        for a, b in zip(starts, starts[1:]):
            events.append({"raw": text[a:b].rstrip("\n"), "time": None})
    elif fmt == "lines":
        events = [{"raw": line, "time": None} for line in text.splitlines() if line.strip()]
    else:
        raise ValueError(fmt)
    for e in events:
        epoch = WL_EPOCH.search(e["raw"]) if e["raw"].startswith("####<") else None
        if not e["time"]:
            m = WL_TIME.match(e["raw"]) or ODL_TIME.match(e["raw"])
            e["time"] = m.group(1) if m else None
        e["epoch_ms"] = int(epoch.group(1)) if epoch else parse_epoch_ms(e["time"])
    return events


def parse_epoch_ms(value) -> int | None:
    """ISO-8601 timestamps (ODL header, Splunk _time) -> epoch milliseconds, for ordering lines within a trace."""
    if not value:
        return None
    try:
        return int(datetime.fromisoformat(str(value).strip().replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def osb_message(raw: str) -> tuple[str, dict]:
    """Return the OSB text without its envelope (WebLogic or ODL) and without the location prefix, plus metadata:
    format, BEA message id (WebLogic), level, ecid and FlowId (ODL). The ecid identifies one request inside OSB."""
    m = WL_MESSAGE.search(raw)
    if m and raw.lstrip().startswith("####<"):
        return LOCATION_PREFIX.sub("", m.group(2), count=1), {"format": "weblogic", "bea": m.group(1)}
    if ODL_TIME.match(raw):
        meta = {"format": "odl"}
        for key, rx in (("level", ODL_LEVEL), ("ecid", ODL_ECID), ("flow_id", ODL_FLOWID)):
            mm = rx.search(raw)
            if mm:
                meta[key] = mm.group(1).strip()
        loc = ODL_LOCATION.search(raw)
        return (raw[loc.end():] if loc else raw), meta
    return raw, {"format": "unknown"}


# ------------------------------------------------------------------ masking
class Masker:
    """Deterministic masking: the same input always gives the same output, so masked keys still join across lines.
    JSON field masking keeps the payload valid JSON: strings become masked_<hash>, numbers keep their length, dates
    keep their format (moved to 1990-01-01) so the masked payload still parses in the code under test."""

    def __init__(self, patterns: list[str], json_keys: list[str] | None = None):
        self.patterns = [re.compile(p) for p in patterns]
        self.count = 0
        keys = "|".join(re.escape(k) for k in (json_keys or []))
        self.json_str = re.compile(r'("(?:%s)"\s*:\s*)"((?:[^"\\]|\\.)*)"' % keys) if keys else None
        self.json_num = re.compile(r'("(?:%s)"\s*:\s*)(-?\d+(?:\.\d+)?)' % keys) if keys else None
        self.json_obj = re.compile(r'("(?:%s)"\s*:\s*)\{([^{}]*)\}' % keys) if keys else None

    def _token(self, s: str) -> str:
        self.count += 1
        if re.match(r"^\d{4}-\d{2}-\d{2}", s):
            return ("1990-01-01" if s[:2] in ("19", "20") else "1410-01-01") + s[10:]
        if s.isdigit():
            return "".join(str(int(c, 16) % 10) for c in hashlib.sha256(s.encode()).hexdigest())[: len(s)]
        return "masked_" + hashlib.sha256(s.encode()).hexdigest()[:10] if s else s

    def _json(self, value: str) -> str:
        if not self.json_str:
            return value
        value = self.json_obj.sub(lambda m: m.group(1) + "{" + re.sub(
            r'(:\s*)"((?:[^"\\]|\\.)*)"', lambda n: n.group(1) + '"' + self._token(n.group(2)) + '"', m.group(2)) + "}", value)
        value = self.json_str.sub(lambda m: m.group(1) + '"' + self._token(m.group(2)) + '"', value)
        return self.json_num.sub(lambda m: m.group(1) + (self._token(m.group(2)) if m.group(2).isdigit() else m.group(2)), value)

    def _sub(self, m: re.Match) -> str:
        self.count += 1
        s = m.group(0)
        h = hashlib.sha256(s.encode()).hexdigest()
        if s.isdigit():                                           # same length, digits only, same input -> same output
            return "".join(str(int(c, 16) % 10) for c in h)[: len(s)]
        return "masked_" + h[:10] + ("@example.invalid" if "@" in s else "")

    def __call__(self, value: str) -> str:
        value = self._json(value)
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
    ap.add_argument("--format", default="auto", choices=["auto", "splunk-json", "csv", "weblogic", "odl", "lines"])
    ap.add_argument("--dims", default="", help="comma-separated fields that split scenarios (default: all hdr_* fields)")
    ap.add_argument("--mask-regex", action="append", default=[])
    ap.add_argument("--no-default-masks", action="store_true")
    ap.add_argument("--mask-json-key", action="append", default=[], help="extra JSON field to mask, e.g. establishmentNameArb")
    ap.add_argument("--no-default-json-keys", action="store_true")
    args = ap.parse_args()

    sigs = compile_signatures(json.loads(args.signatures.read_text(encoding="utf-8")))
    masker = Masker(([] if args.no_default_masks else DEFAULT_MASKS) + args.mask_regex,
                    ([] if args.no_default_json_keys else DEFAULT_JSON_KEYS) + args.mask_json_key)
    events = load_events(args.events, args.format)
    traces, orphans, unmatched, by_ecid = defaultdict(list), 0, 0, 0
    seen, formats = Counter(), Counter()
    for e in events:
        msg, meta = osb_message(e["raw"])
        formats[meta["format"]] += 1
        hit = match(sigs, msg)
        if not hit:
            unmatched += 1
            continue
        s, fields = hit
        fields = {k: masker(v) for k, v in fields.items()}
        seen[s["id"]] += 1
        corr = next((fields[c] for c in s["roles"]["correlation"] if fields.get(c)), None)
        if not corr and meta.get("ecid"):                      # no id in the log text: the ODL ecid ties one OSB request
            corr, by_ecid = "ecid:" + meta["ecid"], by_ecid + 1
        rec = {"time": e["time"], "epoch_ms": e["epoch_ms"], "signature": s["id"], "flow": s["flow"],
               "pipeline_type": s["pipeline_type"], "level": s["level"], "log": meta, "fields": fields}
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
    coverage = {"events_read": len(events), "formats": dict(formats), "events_correlated_by_ecid": by_ecid,
                "events_matched": sum(seen.values()), "events_unmatched": unmatched,
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
