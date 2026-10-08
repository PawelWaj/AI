#!/usr/bin/env python3
"""L6 shadow comparison: pair OSB and Camel output messages by a correlation key and diff them.

Each message is a file <name>.xml with an optional <name>.headers.json ({"header": "value"}).
The key is taken from the headers first, else from the first XML element whose local name equals --key.
Elements whose local name is in --ignore are removed before the canonical (C14N 2.0) comparison; headers listed in
--ignore are dropped too. Exit 0 = no differences and no unmatched messages, 1 = differences, 2 = usage error.
"""
from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def strip(elem: ET.Element, ignore: set[str]) -> None:
    for child in list(elem):
        if local(child.tag) in ignore:
            elem.remove(child)
        else:
            strip(child, ignore)


def load(dir_: Path, key: str, ignore: set[str]) -> tuple[dict[str, tuple[str, dict]], list[str]]:
    msgs, errors = {}, []
    for xml_file in sorted(dir_.glob("*.xml")):
        hdr_file = xml_file.with_suffix(".headers.json")
        headers = json.loads(hdr_file.read_text(encoding="utf-8")) if hdr_file.is_file() else {}
        try:
            root = ET.fromstring(xml_file.read_bytes())
        except ET.ParseError as exc:
            errors.append(f"{xml_file.name}: {exc}")
            continue
        k = headers.get(key) or next((e.text for e in root.iter() if local(e.tag) == key and e.text), None)
        if not k:
            errors.append(f"{xml_file.name}: no key '{key}'")
            continue
        strip(root, ignore)
        canon = ET.canonicalize(ET.tostring(root, encoding="unicode"), strip_text=True)
        msgs[k] = (canon, {h: v for h, v in headers.items() if h not in ignore})
    return msgs, errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--osb", type=Path, required=True)
    ap.add_argument("--camel", type=Path, required=True)
    ap.add_argument("--key", default="correlationId")
    ap.add_argument("--ignore", default="", help="comma-separated element/header local names")
    ap.add_argument("-o", "--out", type=Path)
    args = ap.parse_args()
    if not args.osb.is_dir() or not args.camel.is_dir():
        print("both --osb and --camel must be directories", file=sys.stderr)
        return 2
    ignore = {s.strip() for s in args.ignore.split(",") if s.strip()}
    osb, osb_err = load(args.osb, args.key, ignore)
    cam, cam_err = load(args.camel, args.key, ignore)
    equal, body_diff, header_diff = [], [], []
    for k in sorted(set(osb) & set(cam)):
        (ob, oh), (cb, ch) = osb[k], cam[k]
        if ob != cb:
            body_diff.append(k)
        elif oh != ch:
            header_diff.append({"key": k, "osb": oh, "camel": ch})
        else:
            equal.append(k)
    report = {"matched_equal": len(equal), "body_diff": body_diff, "header_diff": header_diff,
              "osb_only": sorted(set(osb) - set(cam)), "camel_only": sorted(set(cam) - set(osb)),
              "unreadable": osb_err + cam_err, "ignored": sorted(ignore)}
    clean = not (body_diff or header_diff or report["osb_only"] or report["camel_only"] or report["unreadable"])
    report["status"] = "PASS" if clean else "FAIL"
    text = json.dumps(report, indent=2)
    if args.out:
        args.out.write_text(text, encoding="utf-8")
    print(text)
    return 0 if clean else 1


if __name__ == "__main__":
    sys.exit(main())
