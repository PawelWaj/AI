#!/usr/bin/env python3
"""Step 4: pick representative traces per scenario and write test fixtures.

For each scenario, up to N traces with a payload are written as one fixture each:
  <out>/parity/<flow>/<scenario-slug>/<correlation>/input.payload   the logged request body (masked)
  <out>/parity/<flow>/<scenario-slug>/<correlation>/headers.json    JMS/HTTP headers reconstructed from the log fields
  <out>/parity/<flow>/<scenario-slug>/<correlation>/expected.json   outcome, destination, fault code, business keys
and every file is registered in <out>/golden/MANIFEST.csv with source 'osb-recording', which is what gate G7 of the
agent kit accepts. The expected OUTPUT body is not in the logs: produce it with the original XQuery (golden test,
source 'original-transform'), never with the new Camel code.

Usage: fixtures_from_traces.py traces.jsonl replay-config.json -o fixtures/ [--per-scenario 3]
"""
from __future__ import annotations

import argparse
import csv
import datetime
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


def slug(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-").lower()[:80]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("traces", type=Path)
    ap.add_argument("config", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=Path("fixtures"))
    ap.add_argument("--per-scenario", type=int, default=3)
    ap.add_argument("--captured-by", default="osb-log-replay")
    args = ap.parse_args()

    cfg = json.loads(args.config.read_text(encoding="utf-8"))
    flows_cfg = cfg["flows"]
    by_scen = defaultdict(list)
    for line in args.traces.read_text(encoding="utf-8").splitlines():
        if line.strip():
            t = json.loads(line)
            by_scen[t["scenario"]].append(t)

    manifest_path = args.out / "golden" / "MANIFEST.csv"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    new_file = not manifest_path.exists()
    written, skipped = 0, []
    today = datetime.date.today().isoformat()
    with manifest_path.open("a", newline="", encoding="utf-8") as mf:
        w = csv.writer(mf)
        if new_file:
            w.writerow(["file", "source", "flow", "captured_by", "date"])
        for scen, traces in sorted(by_scen.items()):
            flow = traces[0]["flow"]
            fc = flows_cfg.get(flow)
            if not fc:
                skipped.append(f"{scen}: flow not in config")
                continue
            usable = [t for t in traces if t["has_payload"]]
            if not usable:
                skipped.append(f"{scen}: no trace with a payload (debug logging off?)")
                continue
            for t in usable[: args.per_scenario]:
                merged = {}
                for e in t["events"]:
                    for k, v in e["fields"].items():
                        merged.setdefault(k, v)
                d = args.out / "parity" / slug(flow) / slug(scen.split("|", 1)[1]) / slug(t["correlation"])
                d.mkdir(parents=True, exist_ok=True)
                headers = {k[4:]: v for k, v in merged.items() if k.startswith("hdr_")}
                headers[fc.get("correlation_header", "traceId")] = t["correlation"]
                out_cfg = fc["outputs"][t["outcome"]]
                expected = {"outcome": t["outcome"], "destination": out_cfg["destination"],
                            "destination_type": out_cfg.get("type", "anycast"), "correlation": t["correlation"],
                            "fault_code": t["fault_code"],
                            "business_keys": {k: v for k, v in merged.items() if k.startswith("body_")},
                            "expected_headers": out_cfg.get("expect_headers", []),
                            "body_oracle": "original XQuery on input.payload (golden test), not the logs"}
                files = {"input.payload": merged["body"], "headers.json": json.dumps(headers, indent=2, ensure_ascii=False),
                         "expected.json": json.dumps(expected, indent=2, ensure_ascii=False)}
                for name, content in files.items():
                    (d / name).write_text(content, encoding="utf-8")
                    w.writerow([(d / name).relative_to(args.out).as_posix(), "osb-recording", flow, args.captured_by, today])
                written += 1
    print(f"{written} fixtures written to {args.out}/parity; manifest {manifest_path}")
    for s in skipped:
        print("SKIPPED", s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
