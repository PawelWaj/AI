#!/usr/bin/env bash
# Paste into the migration repository root and run: bash 2_install_gates.sh
# Installs gate tools. Existing files are overwritten.
set -euo pipefail
mkdir -p "$(dirname "tools/verify_flow.sh")"
cat > 'tools/verify_flow.sh' <<'KIT_EOF_TOOLS_VERIFY_FLOW_SH'
#!/usr/bin/env bash
# Gates G1-G8 for one migrated OSB flow. Writes migration/<flow>/verify-report.json.
# Usage: tools/verify_flow.sh <module-dir> <flow> [card-path]
# Env:   SKIP_G8=1 to skip the (slow) mutation gate during local loops; CI never sets it.
set -uo pipefail

MODULE=${1:?usage: verify_flow.sh <module-dir> <flow> [card-path]}
FLOW=${2:?usage: verify_flow.sh <module-dir> <flow> [card-path]}
CARD=${3:-migration/$FLOW/FLOW_CARD.md}
TOOLS=$(cd "$(dirname "$0")" && pwd)
# "$PY" on Linux/macOS, python or py on Windows Git Bash
PY=${PYTHON:-$(command -v "$PY" || command -v python || command -v py)}
OUT_DIR="migration/$FLOW"
REPORT="$OUT_DIR/verify-report.json"
RESULTS=$(mktemp)
mkdir -p "$OUT_DIR"
trap 'rm -f "$RESULTS"' EXIT

record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"; echo "  $1 $2  $3"; }
mvnq() { mvn -q -B -f "$MODULE/pom.xml" "$@"; }

echo "Verifying flow '$FLOW' in $MODULE"

# G1 build
if mvnq -DskipTests package > "$OUT_DIR/g1-build.log" 2>&1; then record G1 PASS "build"; else record G1 FAIL "see g1-build.log"; fi

# G2 Camel endpoint validation (camel-report-maven-plugin must be in the pom, see tools/pom-build-plugins.xml)
if mvnq camel-report:validate > "$OUT_DIR/g2-validate.log" 2>&1; then record G2 PASS "endpoint URIs valid"
else record G2 FAIL "see g2-validate.log"; fi

# G3 repository rules
PATTERN='jms://|t3://|\.example\.ins|amqps?://[A-Za-z0-9]|(password|passwd|secret)[[:space:]]*[:=][[:space:]]*[^$[:space:]{]|camel-k|kind:[[:space:]]*(Integration|Kamelet)\b'
HITS=$(grep -RInE "$PATTERN" "$MODULE/src" --include='*.java' --include='*.yaml' --include='*.yml' --include='*.properties' --include='*.xml' 2>/dev/null | grep -v '/src/test/resources/golden/' | grep -v '/src/test/resources/parity/' || true)
if [ -z "$HITS" ]; then record G3 PASS "no hosts, secrets or Camel K"
else printf '%s\n' "$HITS" > "$OUT_DIR/g3-hits.txt"; record G3 FAIL "$(printf '%s\n' "$HITS" | wc -l | tr -d ' ') hits, see g3-hits.txt"; fi

# G4 + G5 one mvn verify run (surefire = unit/route/golden/contract, failsafe = *IT with Testcontainers)
CONTAINER_RT=""
if docker info > /dev/null 2>&1; then CONTAINER_RT=docker; elif podman info > /dev/null 2>&1; then CONTAINER_RT=podman; fi
mvnq verify > "$OUT_DIR/g45-verify.log" 2>&1
read -r UT_TESTS UT_FAIL UT_SKIP < <("$PY" - "$MODULE/target/surefire-reports" <<'PY'
import sys, glob, xml.etree.ElementTree as ET
t=f=s=0
for p in glob.glob(sys.argv[1] + "/TEST-*.xml"):
    r=ET.parse(p).getroot(); t+=int(r.get("tests",0)); f+=int(r.get("failures",0))+int(r.get("errors",0)); s+=int(r.get("skipped",0))
print(t, f, s)
PY
)
SKIP_OK=0; grep -q '^## Skipped tests' "$OUT_DIR/MIGRATION_RECORD.md" 2>/dev/null && SKIP_OK=1
if [ "${UT_TESTS:-0}" -eq 0 ]; then record G4 FAIL "no surefire tests ran"
elif [ "$UT_FAIL" -gt 0 ]; then record G4 FAIL "$UT_FAIL failing of $UT_TESTS"
elif [ "$UT_SKIP" -gt 0 ] && [ "$SKIP_OK" -eq 0 ]; then record G4 FAIL "$UT_SKIP skipped without '## Skipped tests' in the record"
else record G4 PASS "$UT_TESTS tests, $UT_SKIP skipped"; fi

if [ -z "$CONTAINER_RT" ]; then record G5 NOT_RUN "no Docker/Podman: integration tests not run (not green)"
else
  read -r IT_TESTS IT_FAIL < <("$PY" - "$MODULE/target/failsafe-reports" <<'PY'
import sys, glob, xml.etree.ElementTree as ET
t=f=0
for p in glob.glob(sys.argv[1] + "/TEST-*.xml"):
    r=ET.parse(p).getroot(); t+=int(r.get("tests",0)); f+=int(r.get("failures",0))+int(r.get("errors",0))
print(t, f)
PY
)
  if [ "${IT_TESTS:-0}" -eq 0 ]; then record G5 FAIL "no *IT tests ran ($CONTAINER_RT)"
  elif [ "$IT_FAIL" -gt 0 ]; then record G5 FAIL "$IT_FAIL failing of $IT_TESTS"
  else record G5 PASS "$IT_TESTS integration tests ($CONTAINER_RT)"; fi
fi

# G6 matrix coverage
G6=$("$PY" "$TOOLS/check_matrix.py" "$CARD" "$MODULE/src/test/java" 2>&1); RC=$?
echo "$G6" > "$OUT_DIR/g6-matrix.json"
[ $RC -eq 0 ] && record G6 PASS "every matrix row has a test" || record G6 FAIL "see g6-matrix.json"

# G7 oracle provenance
G7=$("$PY" "$TOOLS/check_oracle.py" "$MODULE/src/test/resources" 2>&1); RC=$?
echo "$G7" > "$OUT_DIR/g7-oracle.json"
[ $RC -eq 0 ] && record G7 PASS "all fixtures from OSB" || record G7 FAIL "see g7-oracle.json"

# G8 transform mutation
if [ "${SKIP_G8:-0}" = "1" ]; then record G8 NOT_RUN "skipped by SKIP_G8 (local loop only)"
else
  G8=$("$PY" "$TOOLS/mutate_transforms.py" "$MODULE" 2>&1); RC=$?
  echo "$G8" > "$OUT_DIR/g8-mutation.json"
  [ $RC -eq 0 ] && record G8 PASS "all transform mutants killed" || record G8 FAIL "see g8-mutation.json"
fi

"$PY" - "$RESULTS" "$REPORT" "$FLOW" "$MODULE" <<'PY'
import sys, json, datetime
rows=[l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
gates=[{"gate":g,"status":s,"detail":d} for g,s,d in rows]
green=all(x["status"]=="PASS" for x in gates)
json.dump({"flow":sys.argv[3],"module":sys.argv[4],"date":datetime.datetime.now().isoformat(timespec="seconds"),
           "all_green":green,"gates":gates}, open(sys.argv[2],"w"), indent=2)
print(("ALL GATES GREEN" if green else "NOT GREEN") + f" -> {sys.argv[2]}")
sys.exit(0 if green else 1)
PY
KIT_EOF_TOOLS_VERIFY_FLOW_SH
mkdir -p "$(dirname "tools/check_matrix.py")"
cat > 'tools/check_matrix.py' <<'KIT_EOF_TOOLS_CHECK_MATRIX_PY'
#!/usr/bin/env python3
"""G6: every test-matrix row (T1..Tn) of the flow card has at least one test that names it.

A test "names" a row when the ID appears as a whole token in the test sources, e.g. @DisplayName("T3 filter ...")
or a method t3_filterRejectsCreated(). T1 does not match T10.
Exit 0 = all rows covered, 1 = rows missing, 2 = usage / input error.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROW_ID = re.compile(r"^\|\s*(T\d+)\s*\|", re.MULTILINE)


def matrix_ids(card: Path) -> list[str]:
    text = card.read_text(encoding="utf-8")
    match = re.search(r"^##\s*8\..*?$(.*?)(^##\s|\Z)", text, re.MULTILINE | re.DOTALL)
    section = match.group(1) if match else text
    return sorted(set(ROW_ID.findall(section)), key=lambda s: int(s[1:]))


def covered(test_text: str, row: str) -> bool:
    num = row[1:]
    return re.search(rf"(?<![A-Za-z0-9])[Tt]{num}(?![0-9])", test_text) is not None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("card", type=Path)
    ap.add_argument("test_dir", type=Path, help="e.g. <module>/src/test/java")
    args = ap.parse_args()
    if not args.card.is_file() or not args.test_dir.is_dir():
        print(json.dumps({"gate": "G6", "status": "ERROR", "detail": "card or test dir not found"}))
        return 2
    ids = matrix_ids(args.card)
    if not ids:
        print(json.dumps({"gate": "G6", "status": "FAIL", "detail": "no T-rows found in card section 8"}))
        return 1
    sources = "\n".join(p.read_text(encoding="utf-8", errors="replace")
                        for p in args.test_dir.rglob("*") if p.suffix in {".java", ".kt", ".groovy", ".yaml", ".yml"})
    missing = [r for r in ids if not covered(sources, r)]
    status = "PASS" if not missing else "FAIL"
    print(json.dumps({"gate": "G6", "status": status, "rows": len(ids), "missing": missing}))
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
KIT_EOF_TOOLS_CHECK_MATRIX_PY
mkdir -p "$(dirname "tools/check_oracle.py")"
cat > 'tools/check_oracle.py' <<'KIT_EOF_TOOLS_CHECK_ORACLE_PY'
#!/usr/bin/env python3
"""G7: every expected-output fixture comes from OSB, not from the generated Camel code.

Checks every file under <resources>/golden and <resources>/parity against <resources>/golden/MANIFEST.csv
(columns: file,source,flow,captured_by,date; file relative to <resources>).
Exit 0 = clean, 1 = violations, 2 = usage / input error.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

ALLOWED = {"osb-recording", "original-transform", "osb-test-console", "card-rule"}
FIXTURE_DIRS = ("golden", "parity")
IGNORED = {"MANIFEST.csv", "ignore-fields.txt", "README.md", ".gitkeep"}


def load_manifest(path: Path) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as fh:
        return {row["file"].strip(): row for row in csv.DictReader(fh)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("resources", type=Path, help="e.g. <module>/src/test/resources")
    args = ap.parse_args()
    manifest_path = args.resources / "golden" / "MANIFEST.csv"
    fixtures = [p for d in FIXTURE_DIRS if (args.resources / d).is_dir()
                for p in (args.resources / d).rglob("*") if p.is_file() and p.name not in IGNORED]
    if not fixtures:
        print(json.dumps({"gate": "G7", "status": "FAIL", "detail": "no golden/parity fixtures found"}))
        return 1
    if not manifest_path.is_file():
        print(json.dumps({"gate": "G7", "status": "FAIL", "detail": "golden/MANIFEST.csv missing"}))
        return 1
    try:
        manifest = load_manifest(manifest_path)
    except (KeyError, csv.Error) as exc:
        print(json.dumps({"gate": "G7", "status": "ERROR", "detail": f"bad manifest: {exc}"}))
        return 2
    unlisted, bad_source = [], []
    for p in fixtures:
        rel = p.relative_to(args.resources).as_posix()
        row = manifest.get(rel)
        if row is None:
            unlisted.append(rel)
        elif row.get("source", "").strip() not in ALLOWED:
            bad_source.append(f"{rel} ({row.get('source', '').strip() or 'empty'})")
    ok = not unlisted and not bad_source
    print(json.dumps({"gate": "G7", "status": "PASS" if ok else "FAIL", "fixtures": len(fixtures),
                      "unlisted": unlisted, "bad_source": bad_source, "allowed_sources": sorted(ALLOWED)}))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
KIT_EOF_TOOLS_CHECK_ORACLE_PY
mkdir -p "$(dirname "tools/mutate_transforms.py")"
cat > 'tools/mutate_transforms.py' <<'KIT_EOF_TOOLS_MUTATE_TRANSFORMS_PY'
#!/usr/bin/env python3
"""G8: break each transform on purpose; the golden tests must fail for every mutant.

Mutants (one at a time, original restored after each run, even on error or Ctrl-C):
  XQuery: the content of an element constructor  >{ expr }<  becomes  >{"__MUTANT__"}<
  XSLT:   the select of an <xsl:value-of select="..."/> becomes  select="'__MUTANT__'"
Up to --per-file mutants per transform. A mutant "survives" when the test command exits 0.
Exit 0 = all mutants killed, 1 = survivors or no mutants, 2 = usage error.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

XQ_SITE = re.compile(r">\{([^{}]+)\}<")
XSL_SITE = re.compile(r"(<xsl:value-of\s+select=)\"([^\"]+)\"")


def mutants(text: str, suffix: str, limit: int) -> list[str]:
    out = []
    if suffix in {".xqy", ".xq", ".xquery"}:
        for m in list(XQ_SITE.finditer(text))[:limit]:
            out.append(text[:m.start()] + '>{"__MUTANT__"}<' + text[m.end():])
    elif suffix in {".xsl", ".xslt"}:
        for m in list(XSL_SITE.finditer(text))[:limit]:
            out.append(text[:m.start()] + m.group(1) + "\"'__MUTANT__'\"" + text[m.end():])
    return out


def run_tests(cmd: list[str], cwd: Path, timeout: int) -> bool:
    """True when the tests pass (mutant survived)."""
    try:
        res = subprocess.run(cmd, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
    except subprocess.TimeoutExpired:
        return False
    return res.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("module", type=Path)
    ap.add_argument("--per-file", type=int, default=3)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--test-cmd", default="mvn -q -Dtest=*GoldenTest*,*RouteTest* -Dsurefire.failIfNoSpecifiedTests=false test")
    args = ap.parse_args()
    main_res = args.module / "src" / "main" / "resources"
    if not main_res.is_dir():
        print(json.dumps({"gate": "G8", "status": "ERROR", "detail": f"{main_res} not found"}))
        return 2
    cmd = args.test_cmd.split()
    cmd[0] = shutil.which(cmd[0]) or cmd[0]  # resolves mvn.cmd on Windows
    results = []
    for f in sorted(p for p in main_res.rglob("*") if p.suffix in {".xqy", ".xq", ".xquery", ".xsl", ".xslt"}):
        original = f.read_text(encoding="utf-8")
        backup = f.with_suffix(f.suffix + ".g8bak")
        shutil.copy2(f, backup)
        try:
            for i, mutant in enumerate(mutants(original, f.suffix, args.per_file), 1):
                f.write_text(mutant, encoding="utf-8")
                survived = run_tests(cmd, args.module, args.timeout)
                results.append({"file": f.relative_to(args.module).as_posix(), "mutant": i,
                                "result": "SURVIVED" if survived else "KILLED"})
        finally:
            shutil.move(backup, f)
    survivors = [r for r in results if r["result"] == "SURVIVED"]
    status = "PASS" if results and not survivors else "FAIL"
    detail = "no mutable transform sites found" if not results else ""
    print(json.dumps({"gate": "G8", "status": status, "mutants": len(results), "survivors": survivors,
                      "detail": detail}))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
KIT_EOF_TOOLS_MUTATE_TRANSFORMS_PY
mkdir -p "$(dirname "tools/compare_shadow.py")"
cat > 'tools/compare_shadow.py' <<'KIT_EOF_TOOLS_COMPARE_SHADOW_PY'
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
KIT_EOF_TOOLS_COMPARE_SHADOW_PY
mkdir -p "$(dirname "tools/pom-build-plugins.xml")"
cat > 'tools/pom-build-plugins.xml' <<'KIT_EOF_TOOLS_POM_BUILD_PLUGINS_XML'
<!-- Build plugins the gates rely on. Merge into <build><plugins> of each flow module (or the parent pom).
     Versions are properties: pin them in the parent pom to the programme's approved versions. -->
<plugins>
  <!-- G4: unit, route, golden, contract tests (*Test) -->
  <plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <version>${surefire.version}</version>
    <configuration>
      <excludes><exclude>**/*IT.java</exclude></excludes>
    </configuration>
  </plugin>

  <!-- G5: integration tests (*IT) with Testcontainers AMQ Broker -->
  <plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-failsafe-plugin</artifactId>
    <version>${surefire.version}</version>
    <executions>
      <execution><goals><goal>integration-test</goal><goal>verify</goal></goals></execution>
    </executions>
  </plugin>

  <!-- G2: validates every Camel endpoint URI and option against the Camel catalog of this version -->
  <plugin>
    <groupId>org.apache.camel</groupId>
    <artifactId>camel-report-maven-plugin</artifactId>
    <version>${camel.version}</version>
    <configuration>
      <failOnError>true</failOnError>
      <includeTest>false</includeTest>
      <ignoreUnknownComponent>false</ignoreUnknownComponent>
    </configuration>
  </plugin>

  <!-- Optional G8b: mutation testing of Java processors -->
  <plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>${pitest.version}</version>
    <dependencies>
      <dependency>
        <groupId>org.pitest</groupId>
        <artifactId>pitest-junit5-plugin</artifactId>
        <version>${pitest.junit5.version}</version>
      </dependency>
    </dependencies>
    <configuration>
      <targetClasses><param>${integration.base.package}.*</param>  <!-- base package: OPEN, set in the parent pom --></targetClasses>
      <mutationThreshold>70</mutationThreshold>
    </configuration>
  </plugin>
</plugins>
KIT_EOF_TOOLS_POM_BUILD_PLUGINS_XML
mkdir -p "$(dirname "ci/Jenkinsfile.groovy")"
cat > 'ci/Jenkinsfile.groovy' <<'KIT_EOF_CI_JENKINSFILE_GROOVY'
// Stages to add to the migration repository's Jenkins pipeline. One run per changed flow module.
// Parameters: FLOW (flow name), MODULE (module dir), TARGET (target branch, default main),
//             IMPLEMENTER_ID (git author e-mail used by the implementer agent).
pipeline {
  agent { label 'maven-docker' }          // Java 21, Maven 3.9, Python 3, Docker or Podman for Testcontainers
  parameters {
    string(name: 'FLOW', description: 'OSB flow name, e.g. order-event')
    string(name: 'MODULE', description: 'Maven module directory of the flow')
    string(name: 'TARGET', defaultValue: 'main')
    string(name: 'IMPLEMENTER_ID', defaultValue: 'implementer-agent@ci.local')
  }
  stages {
    stage('guard') {
      // Independence rule: the implementer identity may not touch tests, fixtures or the manifest.
      steps {
        sh '''
          set -eu
          git fetch -q origin "$TARGET"
          BAD=""
          for c in $(git rev-list "origin/$TARGET..HEAD"); do
            if [ "$(git show -s --format=%ae "$c")" = "$IMPLEMENTER_ID" ]; then
              F=$(git show --name-only --format= "$c" | grep -E '/src/test/|/golden/|/parity/|MANIFEST\\.csv' || true)
              [ -n "$F" ] && BAD="$BAD $c"
            fi
          done
          if [ -n "$BAD" ]; then echo "Implementer commits touch test paths:$BAD"; exit 1; fi
        '''
      }
    }
    stage('approved card') {
      steps {
        sh 'grep -Eq "^\\| \\*\\*Status\\*\\* \\| approved" "migration/$FLOW/FLOW_CARD.md" || { echo "card not approved"; exit 1; }'
      }
    }
    stage('gates G1-G8') {
      steps { sh 'tools/verify_flow.sh "$MODULE" "$FLOW"' }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: "migration/${params.FLOW}/**, ${params.MODULE}/target/*-reports/**", allowEmptyArchive: true
      junit testResults: "${params.MODULE}/target/*-reports/TEST-*.xml", allowEmptyResults: true
    }
  }
}
KIT_EOF_CI_JENKINSFILE_GROOVY
chmod +x tools/*.sh tools/*.py 2>/dev/null || true
echo "installed: 7 files (gate tools)"
