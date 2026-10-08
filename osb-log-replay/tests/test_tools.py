"""Unit tests for the osb-log-replay tools. Run: python3 -m unittest discover -s tests -v (stdlib only)."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import osb_log_signatures as sigmod  # noqa: E402
import osb_log_traces as trmod  # noqa: E402
import replay_runner as rr  # noqa: E402
import spl_from_signatures as spl  # noqa: E402

SAMPLES = ROOT / "samples"
CONFIG = ROOT / "replay-config.json"


def run(*args):
    return subprocess.run([sys.executable, *map(str, args)], capture_output=True, text=True, check=True)


class SignatureTests(unittest.TestCase):
    def test_split_respects_quotes_and_parentheses(self):
        parts = sigmod.split_top_level('"a, b", fn:data($x/y[@n="1,2"]), \'it\'\'s\'')
        self.assertEqual(parts, ['"a, b"', 'fn:data($x/y[@n="1,2"])', "'it''s'"])

    def test_literal_unescape(self):
        self.assertEqual(sigmod.literal_value("'it''s'"), "it's")

    def test_group_names(self):
        used = {}
        self.assertEqual(sigmod.group_name('fn:data($inbound/a/*:user-header[@name="resource"]/@value)', used), "hdr_resource")
        self.assertEqual(sigmod.group_name("$body//*:resourceId/text()", used), "body_resourceId")
        self.assertEqual(sigmod.group_name("$body", used), "body")
        self.assertEqual(sigmod.group_name("fn-bea:serialize($fault)", used), "fault")
        self.assertEqual(sigmod.group_name("$uuId", used), "uuId")
        self.assertEqual(sigmod.group_name("$uuId", used), "uuId_2")

    def test_signature_matches_its_own_output(self):
        sig = sigmod.build_signature('fn:concat("Request Received with TraceID - ",$uuId," ::",$body)')
        import re
        m = re.compile(sig["regex"], re.S).search("Request Received with TraceID - abc-1 ::{\n \"a\": 1\n}")
        self.assertEqual(m.group("uuId"), "abc-1")
        self.assertIn('"a": 1', m.group("body"))
        self.assertEqual(sig["roles"]["correlation"], ["uuId"])
        self.assertEqual(sig["roles"]["payload"], ["body"])

    def test_warnings(self):
        sig = sigmod.build_signature('fn:concat("x",$a,$b)')
        self.assertTrue(any("ambiguous" in w for w in sig["warnings"]))
        self.assertTrue(any("no correlation" in w for w in sig["warnings"]))

    def test_sample_export(self):
        with tempfile.TemporaryDirectory() as d:
            run(ROOT / "tools/osb_log_signatures.py", SAMPLES, "-o", Path(d) / "s.json")
            sigs = json.loads((Path(d) / "s.json").read_text())["signatures"]
        self.assertEqual(len(sigs), 3)
        self.assertEqual({s["pipeline_type"] for s in sigs}, {"request", "error"})
        self.assertEqual(sum(1 for s in sigs if s["level"] == "debug"), 1)


class TraceTests(unittest.TestCase):
    def test_weblogic_envelope(self):
        raw = "####<Oct 6> <Info> <OSB Pipeline> <h> <s> <t> <u> <> <x> <1791270902101> <[x] > <BEA-000000> < [st, p, null, REQUEST] hello world>"
        msg, meta = trmod.osb_message(raw)
        self.assertEqual((msg, meta["bea"], meta["format"]), ("hello world", "BEA-000000", "weblogic"))

    def test_odl_envelope(self):
        raw = ("[2026-10-08T11:59:16.339+03:00] [osb_server1] [NOTIFICATION] [] [oracle.osb.logging.pipeline] "
               "[tid: [ACTIVE].ExecuteThread: '97' for queue: 'x'] [userId: <anonymous>] [ecid: abc-1,0] [FlowId: F1]  "
               "[node, request-1, stage-1, REQUEST] Request Received ::{\"a\":1}")
        msg, meta = trmod.osb_message(raw)
        self.assertEqual(msg, 'Request Received ::{"a":1}')
        self.assertEqual((meta["format"], meta["level"], meta["ecid"], meta["flow_id"]), ("odl", "NOTIFICATION", "abc-1", "F1"))

    def test_json_field_masking_keeps_json_valid(self):
        m = trmod.Masker(trmod.DEFAULT_MASKS, trmod.DEFAULT_JSON_KEYS + ["branchNameArb"])
        src = ('{"name":{"firstName":"Jane","surName":"Example","nameEnglish":"JANE EXAMPLE"},"nin":1000000001,'
               '"birthDate":{"gregorian":"1999-05-17T00:00:00.000Z","hijiri":"1420-01-30"},"branchNameArb":"x y",'
               '"amount":0.00,"keep":"visible"}')
        out = m(src)
        doc = json.loads(out)
        self.assertNotIn("Jane", out)
        self.assertNotIn("JANE EXAMPLE", out)
        self.assertNotIn("1000000001", out)
        self.assertNotIn("x y", out)
        self.assertEqual(doc["birthDate"]["gregorian"], "1990-01-01T00:00:00.000Z")
        self.assertEqual(len(str(doc["nin"])), 10)
        self.assertEqual(doc["keep"], "visible")
        self.assertIn('"amount":0.00', out)                      # untouched fields keep their exact text
        self.assertEqual(m(src), out)                             # deterministic

    def test_odl_sample_end_to_end(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            run(ROOT / "tools/osb_log_signatures.py", SAMPLES, "-o", d / "s.json")
            run(ROOT / "tools/osb_log_traces.py", d / "s.json", SAMPLES / "osb-odl-sample.log", "-o", d / "t")
            cov = json.loads((d / "t/coverage.json").read_text())
            traces = [json.loads(line) for line in (d / "t/traces.jsonl").read_text().splitlines()]
        self.assertEqual(cov["formats"], {"odl": 3})
        self.assertEqual(cov["events_matched"], 3)
        self.assertEqual(cov["traces"], 2)
        body = [t for t in traces if t["outcome"] == "success"][0]["events"][0]["fields"]["body"]
        self.assertNotIn("Jane", body)
        self.assertNotIn("jane@example.org", body)
        self.assertEqual(json.loads(body)["data"]["customer"]["birthDate"]["gregorian"][:10], "1990-01-01")
        err = [t for t in traces if t["outcome"] == "error"][0]
        self.assertEqual(err["fault_code"], "BEA-382000")

    def test_masking_is_deterministic_and_spares_uuids(self):
        m = trmod.Masker(trmod.DEFAULT_MASKS)
        a = m("id 1234567890 in /c/1234567890/x uuid 7f3c2a10-1111-4a2b-9c01-000000000001 mail a.b@c.com")
        self.assertNotIn("1234567890", a)
        self.assertIn("7f3c2a10-1111-4a2b-9c01-000000000001", a)
        self.assertNotIn("a.b@c.com", a)
        self.assertEqual(m("1234567890"), m("1234567890"))
        self.assertEqual(len(m("1234567890")), 10)

    def test_sample_pipeline_to_scenarios(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            run(ROOT / "tools/osb_log_signatures.py", SAMPLES, "-o", d / "s.json")
            run(ROOT / "tools/osb_log_traces.py", d / "s.json", SAMPLES / "osb-weblogic-sample.log", "-o", d / "t")
            cov = json.loads((d / "t/coverage.json").read_text())
            scen = json.loads((d / "t/scenarios.json").read_text())
            traces = [json.loads(line) for line in (d / "t/traces.jsonl").read_text().splitlines()]
        self.assertEqual(cov["events_read"], 8)
        self.assertEqual(cov["events_unmatched"], 1)          # the WebLogic RUNNING line is not an OSB log action
        self.assertEqual(cov["traces"], 4)
        self.assertEqual(cov["traces_without_payload"], 1)    # debug line missing for trace 4
        self.assertTrue(any("errorCode=BEA-382000" in s["scenario"] for s in scen))
        multi = [t for t in traces if t["correlation"].endswith("0002")][0]
        self.assertIn('"referenceNo": "REF-0002"', multi["events"][0]["fields"]["body"])
        self.assertTrue(all("Cancel Order" in t["branch"].get("hdr_resource", "") for t in [multi]))


class FixtureTests(unittest.TestCase):
    def test_fixtures_and_manifest(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            run(ROOT / "tools/osb_log_signatures.py", SAMPLES, "-o", d / "s.json")
            run(ROOT / "tools/osb_log_traces.py", d / "s.json", SAMPLES / "osb-weblogic-sample.log", "-o", d / "t")
            out = run(ROOT / "tools/fixtures_from_traces.py", d / "t/traces.jsonl", CONFIG, "-o", d / "fx").stdout
            inputs = list((d / "fx/parity").rglob("input.payload"))
            manifest = (d / "fx/golden/MANIFEST.csv").read_text().splitlines()
            err = [p.parent for p in inputs if json.loads((p.parent / "expected.json").read_text())["outcome"] == "error"]
            headers = json.loads((err[0] / "headers.json").read_text())
            expected = json.loads((err[0] / "expected.json").read_text())
        self.assertEqual(len(inputs), 3)                      # 4 traces, one without payload is skipped
        self.assertIn("SKIPPED", out)
        self.assertEqual(len(manifest), 1 + 3 * 3)
        self.assertTrue(all(",osb-recording," in row for row in manifest[1:]))
        self.assertEqual(headers["resource"], "Create Order")
        self.assertIn("traceId", headers)
        self.assertEqual(expected["destination"], "orderEventErrorQueue")
        self.assertIn("errorCode", expected["expected_headers"])


class FakeBroker:
    """Plays the flow under test: routes each sent message by a rule function."""

    def __init__(self, rule):
        self.rule, self.inbox = rule, []

    def subscribe(self, destination, dtype):
        pass

    def send(self, destination, dtype, body, headers):
        out = self.rule(body, headers)
        if out:
            self.inbox.append(out)

    def receive(self, timeout):
        return self.inbox.pop(0) if self.inbox else None


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        run(ROOT / "tools/osb_log_signatures.py", SAMPLES, "-o", d / "s.json")
        run(ROOT / "tools/osb_log_traces.py", d / "s.json", SAMPLES / "osb-weblogic-sample.log", "-o", d / "t")
        run(ROOT / "tools/fixtures_from_traces.py", d / "t/traces.jsonl", CONFIG, "-o", d / "fx")
        self.cfg = json.loads(CONFIG.read_text())
        self.flow = "order-event-prj/order-event"
        self.fc = dict(self.cfg["flows"][self.flow], timeout_s=0.2)
        self.fixtures = rr.find_fixtures(d / "fx", self.flow)

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def correct_flow(body, headers):
        if headers.get("eventType") != "updated" or headers.get("resource") not in ("Create Order", "Cancel Order"):
            return None                                       # dropped by the subscription filter
        try:
            json.loads(body)
            return ("/queue/InboundOrderEventQueue", {"traceId": headers["traceId"]}, body)
        except ValueError:
            return ("orderEventErrorQueue", {k: "x" for k in ("errorCode", "errorMessage", "resource", "eventType")}
                    | {"traceId": headers["traceId"]}, body)

    def test_correct_flow_passes_all(self):
        res = rr.run_flow(FakeBroker(self.correct_flow), self.flow, self.fc, self.fixtures, negative=True)
        self.assertEqual(len(res), 3 + 2)
        self.assertTrue(all(r["status"] == "PASS" for r in res), res)

    def test_wrong_outcome_and_missing_headers_fail(self):
        def broken(body, headers):                            # sends everything to the error queue without error headers
            return ("orderEventErrorQueue", {"traceId": headers["traceId"]}, body)
        res = rr.run_flow(FakeBroker(broken), self.flow, self.fc, self.fixtures, negative=True)
        probs = " ".join(p for r in res for p in r["problems"])
        self.assertIn("outcome error, expected success", probs)
        self.assertIn("missing headers", probs)
        self.assertIn("was delivered", probs)                 # negative cases leak through

    def test_golden_body_comparison(self):
        ok = [f for f in self.fixtures if json.loads((f / "expected.json").read_text())["outcome"] == "success"][0]
        (ok / "expected-output.xml").write_text("<a><b>1</b></a>")
        def flow(body, headers):
            return ("InboundOrderEventQueue", {"traceId": headers["traceId"]}, "<a>\n  <b>2</b>\n</a>")
        res = rr.run_flow(FakeBroker(flow), self.flow, self.fc, [ok], negative=False)
        self.assertIn("body differs", " ".join(res[0]["problems"]))

    def test_junit(self):
        xml = rr.junit([{"flow": "f", "case": "c", "status": "FAIL", "problems": ["x <y>"], "seconds": 1}])
        self.assertIn('failures="1"', xml)
        self.assertIn("x &lt;y&gt;", xml)


class SplTests(unittest.TestCase):
    def test_pcre_conversion(self):
        self.assertEqual(spl.pcre('a(?P<x>.*?)"b'), 'a(?<x>.*?)\\"b')


if __name__ == "__main__":
    unittest.main()
