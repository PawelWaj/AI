#!/usr/bin/env bash
# Paste into the migration repository root and run: bash 1_install_agents.sh
# Installs agent layer: AGENTS.md, role prompts, pi prompts, runner, preflight. Existing files are overwritten.
set -euo pipefail
mkdir -p "$(dirname "AGENTS.md")"
cat > 'AGENTS.md' <<'KIT_EOF_AGENTS_MD'
# AGENTS.md: OSB → Camel migration repository (client programme)

Every AI agent working in this repository follows these rules. Role prompts in `agents/` add duties per phase.

## What this repository is

Camel on Spring Boot modules that replace Oracle Service Bus flows, one Maven module per OSB project folder, one
`RouteBuilder` per OSB proxy service. Source of truth for behaviour = the OSB export under `osb-src/` (read-only).

## Workflow (never skip a step)

1. **Check first:** search this repository for the proxy name, its queues/topics/URLs and XQuery file names. If a
   route already exists, compare and report; do not generate a second one.
2. **Analyse** with skill `osb-to-camel` Step 0–1 → `migration/<flow>/FLOW_CARD.md`.
3. **Stop for approval.** No code for a card without `Status: approved` and an approver name.
4. **Implement** with `osb-to-camel` Step 2.
5. **Test** with `osb-to-camel` Step 3 and skill `camel-migration-verification`.
6. **Verify:** `tools/verify_flow.sh <module> <flow>` must report all gates green.
7. **Record:** `migration/<flow>/MIGRATION_RECORD.md` with the four sections: Original OSB behaviour / Camel
   implementation / Behavioural differences / Items requiring human validation.

## Hard rules

- Inputs are files from `osb-src/`. Never build code from screenshots, chat text or memory of "how OSB usually works".
- Runtime: Camel on Spring Boot. **No Camel K, no Kubernetes operators, no Kamelet CRDs.** YAML DSL and the `kamelet`
  component inside Spring Boot are allowed only if the card says so.
- Messaging: Red Hat AMQ Broker, AMQP 1.0 on port 5672, `camel-amqp` (Qpid JMS) with a failover URI. Destinations
  exist only through the Git register; never rely on auto-create. A WebLogic durable topic subscription becomes a
  named subscription queue with a broker-side filter, consumed by FQQN `<address>::<subscription>`.
- JMS: local transacted sessions; duplicate-ID header on every send; consumers idempotent.
- Every endpoint, queue name, timeout and retry value is a `{{placeholder}}`; no host names, ports or credentials in
  code, tests or `application.yml`. Credentials come from Vault at runtime.
- Keep original XQuery/XSLT files and their behaviour (quirks included) unless the card approves a change. Never
  rewrite a working transform into Java "because it is cleaner".
- Logging: stdout, correlation id in every line, no full payloads above DEBUG, mask personal data (SIN, national ID).
- Component options: Camel MCP if connected, else `skills/osb-to-camel/references/versions.md` + Camel docs for that
  version. Do not guess options.
- **Test oracle:** expected outputs come from OSB (recordings, the original transform run on Saxon, the OSB test
  console). Never generate an expected file by running the new Camel code.
- Never delete, skip or weaken a test to get green. A skipped test needs a reason in the record.
- Never claim equivalence. Report gate results and test evidence; humans decide.

## Commands

| Purpose | Command |
|---|---|
| Inventory an export | `python3 skills/osb-to-camel/scripts/osb_inventory.py osb-src/<project> -o migration/osb-inventory` |
| Scaffold a card | `python3 skills/osb-to-camel/scripts/scaffold_flow.py migration/osb-inventory/flows/<flow>.json -o migration/<flow>/` |
| Build + tests | `mvn -q -f <module>/pom.xml verify` |
| All gates | `tools/verify_flow.sh <module> <flow>` |

## Definition of done (per flow)

Card approved · gates G1–G8 green in `verify-report.json` · record written · reviewer report with no open BLOCKER ·
human sign-off · shadow run in E2E passed (TESTING.md L6) before cut-over.
KIT_EOF_AGENTS_MD
mkdir -p "$(dirname "agents/orchestrator.md")"
cat > 'agents/orchestrator.md' <<'KIT_EOF_AGENTS_ORCHESTRATOR_MD'
# Orchestrator: phases, hand-offs, loops

You coordinate the migration of one OSB flow (or one batch) through four roles. You do not write cards, code or tests
yourself. You start each role with its prompt from `agents/`, pass only the hand-off files listed below, read the
gate output, and decide the next state. Repository rules: `AGENTS.md`.

## State machine (per flow)

| State | Role | Input files | Output files | Exit when | Next |
|---|---|---|---|---|---|
| S0 NEW | analyst | `osb-src/<project>/` | `migration/osb-inventory/`, `migration/<flow>/FLOW_CARD.md` | card written, open items listed | S1 |
| S1 CARD_REVIEW | **human** | card | card with `Status: approved` + approver | approved / changes requested | S2 / S0 |
| S2 IMPLEMENT | implementer | approved card, `osb-src/`, skill templates | `<module>/src/main/**`, `register/` snippet | `mvn -DskipTests package` passes | S3 |
| S3 TEST | tester | approved card, `osb-src/`, golden fixtures, **not** the implementer's chat | `<module>/src/test/**`, `golden/MANIFEST.csv` | tests written for every matrix row | S4 |
| S4 VERIFY | tools (no AI) | module | `migration/<flow>/verify-report.json` | all gates green | S5 |
| S4a FIX | implementer | verify report, failing test output | code changes only | re-run S4 | S4 |
| S5 REVIEW | reviewer | card, code, tests, verify report | `REVIEW.md`, `MIGRATION_RECORD.md` | no BLOCKER | S6 |
| S6 SIGN_OFF | **human** | record, review, report | signed record | signed | S7 |
| S7 SHADOW | platform + tester | E2E deployment | shadow comparison report (TESTING.md L6) | diff rate 0 over the agreed window | DONE |

## Loop limits and stop conditions

- S4 ↔ S4a: at most **3** fix loops. Then stop the flow, status `BLOCKED`, attach the last report.
- The implementer may change **production code only** in S4a. If a test looks wrong, it writes the argument into
  `migration/<flow>/TEST_DISPUTE.md`; the tester (fresh context) decides; a human breaks ties.
- Batch mode: stop the batch after 3 consecutive flows with an unknown OSB action, a missing resource or a shim gap.
  The mapping tables need an entry first.
- Any request to touch `osb-src/`, credentials, production endpoints or another flow's module: refuse and report.

## Status file

Keep `migration/STATUS.md`: one row per flow with state, tier, loop count, gates summary, blocking items, owner.
KIT_EOF_AGENTS_ORCHESTRATOR_MD
mkdir -p "$(dirname "agents/analyst.md")"
cat > 'agents/analyst.md' <<'KIT_EOF_AGENTS_ANALYST_MD'
# Role: analyst

**Goal:** a complete, sourced flow card for one OSB flow. No code.

**Use:** skill `osb-to-camel`, Steps 0 and 1. Read `references/osb-action-mapping.md`, `osb-transport-mapping.md`,
`osb-expression-mapping.md`, `triage-rules.md` as the card needs them.

**Do**
1. Run the inventory once per project; read `INVENTORY.md` fully.
2. Scaffold the card, then complete it from the real `.proxy`, `.pipeline`, `.bix`/`.biz`, `.xqy`, `.xsl`, `.xsd`,
   `.wsdl`, `.jca`, `.mfl` files. One row per pipeline action, in execution order, with the file and XPath it came from.
3. Fill: contract, context variables, backends with retries/timeouts, transforms with `fn-bea:` use, error handlers
   (what they send, whether they swallow the fault), transactions, selectors, durable subscriptions, logging of
   personal data, test matrix (one row per operation, branch, error path, transform, backend; IDs T1..Tn).
4. Name every behaviour that cannot map 1:1 and every quirk the migration must preserve (it goes to the parity tests).
5. Open items: one owner each. Blocking items are marked BLOCKING.

**Do not:** propose improvements to the contract, guess missing files, write Java.

**Hand-off:** `migration/<flow>/FLOW_CARD.md`, status `draft`, plus a 5-line summary for the human reviewer.
KIT_EOF_AGENTS_ANALYST_MD
mkdir -p "$(dirname "agents/implementer.md")"
cat > 'agents/implementer.md' <<'KIT_EOF_AGENTS_IMPLEMENTER_MD'
# Role: implementer

**Goal:** the Camel on Spring Boot code for one **approved** card. Nothing the card did not approve.

**Use:** skill `osb-to-camel`, Step 2, templates in `assets/templates/java/` (read them before writing), `AGENTS.md`.

**Do**
1. Refuse to start unless the card says `Status: approved` with an approver.
2. Generate: `RouteBuilder` (route id = proxy name), `OsbSupport`/`OsbXQuery` usage for OSB expressions, original
   transforms copied unchanged (+ `fn-bea` shim import only), processors only where the card says, `application.yml`
   keys with placeholders, the Artemis register snippet (addresses, subscription queues with filters, DLQ/expiry).
3. Map OSB retries to redelivery on that endpoint, OSB error handlers to the scope the card decided, OSB `Reply`
   semantics exactly (a swallowed fault stays swallowed unless the card approved a change).
4. `mvn -q -DskipTests package` must pass before hand-off.

**In fix loops (S4a):** change production code only. If you believe a test is wrong, write
`migration/<flow>/TEST_DISPUTE.md` (test, expected, actual, evidence from the OSB files) and stop. Never edit tests,
fixtures, `golden/` or `MANIFEST.csv`.

**Do not:** add components outside `references/versions.md` without a note, hard-code hosts/queues/credentials,
generate expected outputs, run against real environments.

**Hand-off:** the module path and a list of files changed.
KIT_EOF_AGENTS_IMPLEMENTER_MD
mkdir -p "$(dirname "agents/tester.md")"
cat > 'agents/tester.md' <<'KIT_EOF_AGENTS_TESTER_MD'
# Role: tester (independent oracle)

**Goal:** a test suite that would catch a wrong migration. You work from the **card and the OSB evidence**, not from
the implementer's reasoning. Start with a fresh context.

**Use:** skill `osb-to-camel` Step 3 + `references/test-strategy.md`, skill `camel-migration-verification`.

**Do**
1. One test per row of the card's test matrix. Put the row ID in the test name or `@DisplayName` ("T3 …"); gate G6
   checks it.
2. Expected outputs only from OSB: recorded traffic, the **original** XQuery/XSLT run on Saxon with the `fn-bea` shim,
   or the OSB test console. Register each file in `src/test/resources/golden/MANIFEST.csv`
   (`file,source,flow,captured_by,date`); `source` ∈ `osb-recording | original-transform | osb-test-console |
   card-rule`. Gate G7 rejects anything else.
3. Mock every external system: `mock:` via AdviceWith for route logic, WireMock for HTTP/SOAP, Testcontainers Artemis
   (AMQ Broker image, AMQP 5672) for JMS behaviour: filters, transactions, redelivery, DLQ, error queue headers.
4. Cover the quirks the card lists (they are features until a human says otherwise).
5. Assert behaviour, not implementation: message bodies (XMLUnit, canonical), headers, destinations, counts,
   acknowledgement (message gone vs redelivered).

**Do not:** read the implementer's explanation of why something should pass, compute expectations with the new code,
use `@Disabled` without a reason in the record, relax an assertion to make a test green.

**Hand-off:** the test sources, `MANIFEST.csv`, and the list of matrix rows that could not be tested with the reason.
KIT_EOF_AGENTS_TESTER_MD
mkdir -p "$(dirname "agents/reviewer.md")"
cat > 'agents/reviewer.md' <<'KIT_EOF_AGENTS_REVIEWER_MD'
# Role: reviewer (evidence only, read-only)

**Goal:** an honest review and the migration record. You do not change code or tests.

**Inputs:** approved card, module code, tests, `verify-report.json`, `golden/MANIFEST.csv`, the OSB files.

**Check**
1. Every pipeline action on the card maps to a Camel step (action id → class/line). Missing = BLOCKER.
2. Contract unchanged: inbound transport, URI path, WSDL/namespaces, selector, subscription semantics.
3. Error behaviour: same destinations, headers, swallowed vs propagated, retry counts and intervals.
4. Transactions and acknowledgement match the card's decision; deviations are listed as deliberate.
5. Tests: every matrix row present (G6), oracle provenance clean (G7), mutation check killed every mutant (G8), no
   skipped test without a reason.
6. Rules in `AGENTS.md`: placeholders, no secrets, no Camel K/operators, logging of personal data.

**Severity:** BLOCKER (wrong behaviour or missing evidence) · MAJOR (rule broken, behaviour plausibly fine) ·
MINOR (style, naming).

**Write**
- `migration/<flow>/REVIEW.md`: findings with severity and file:line.
- `migration/<flow>/MIGRATION_RECORD.md` from the skill template, with the four sections: **Original OSB behaviour /
  Camel implementation / Behavioural differences / Items requiring human validation**. Use the words "evidence shows"
  with a gate or test name; never "equivalent".
KIT_EOF_AGENTS_REVIEWER_MD
mkdir -p "$(dirname "pi/prompts/osb-analyse.md")"
cat > 'pi/prompts/osb-analyse.md' <<'KIT_EOF_PI_PROMPTS_OSB_ANALYSE_MD'
---
description: OSB flow -> inventory + flow card (analyst role, no code)
argument-hint: "<osb-project-dir> <flow>"
---
Act as the analyst defined in agents/analyst.md and follow AGENTS.md.
Use skill osb-to-camel Steps 0 and 1 on the OSB export $1 for flow $2.
Write migration/$2/FLOW_CARD.md with Status draft, then stop and list the BLOCKING open items.
KIT_EOF_PI_PROMPTS_OSB_ANALYSE_MD
mkdir -p "$(dirname "pi/prompts/osb-implement.md")"
cat > 'pi/prompts/osb-implement.md' <<'KIT_EOF_PI_PROMPTS_OSB_IMPLEMENT_MD'
---
description: Approved flow card -> Camel on Spring Boot code (implementer role)
argument-hint: "<flow> <module-dir>"
---
Act as the implementer defined in agents/implementer.md and follow AGENTS.md.
Refuse unless migration/$1/FLOW_CARD.md says Status approved with an approver.
Implement it with skill osb-to-camel Step 2 into Maven module $2. Never touch $2/src/test.
Finish when `mvn -q -DskipTests -f $2/pom.xml package` passes.
KIT_EOF_PI_PROMPTS_OSB_IMPLEMENT_MD
mkdir -p "$(dirname "pi/prompts/osb-test.md")"
cat > 'pi/prompts/osb-test.md' <<'KIT_EOF_PI_PROMPTS_OSB_TEST_MD'
---
description: Flow card + OSB evidence -> test suite (tester role; start a NEW session first)
argument-hint: "<flow> <module-dir> <osb-project-dir>"
---
Act as the tester defined in agents/tester.md and follow AGENTS.md. You have not seen the implementation reasoning.
Write the tests for flow $1 from migration/$1/FLOW_CARD.md and the OSB evidence in $3, with skill osb-to-camel Step 3
and skill camel-migration-verification. One test per matrix row (T-ID in the name). Expected files only from OSB,
listed in $2/src/test/resources/golden/MANIFEST.csv. Do not edit $2/src/main. Run `mvn -q -f $2/pom.xml verify`.
KIT_EOF_PI_PROMPTS_OSB_TEST_MD
mkdir -p "$(dirname "pi/prompts/osb-verify.md")"
cat > 'pi/prompts/osb-verify.md' <<'KIT_EOF_PI_PROMPTS_OSB_VERIFY_MD'
---
description: Run gates G1-G8 for a flow and explain the result
argument-hint: "<module-dir> <flow>"
---
Run `tools/verify_flow.sh $1 $2` and show migration/$2/verify-report.json as a table.
For each red gate, name the owner role per skill camel-migration-verification Step 2. Do not fix anything.
KIT_EOF_PI_PROMPTS_OSB_VERIFY_MD
mkdir -p "$(dirname "pi/prompts/osb-review.md")"
cat > 'pi/prompts/osb-review.md' <<'KIT_EOF_PI_PROMPTS_OSB_REVIEW_MD'
---
description: Evidence-only review + migration record (reviewer role; start a NEW session first)
argument-hint: "<flow> <module-dir> <osb-project-dir>"
---
Act as the reviewer defined in agents/reviewer.md. Do not edit code or tests.
Review flow $1 (card migration/$1/FLOW_CARD.md, module $2, gates migration/$1/verify-report.json, OSB sources $3)
and write migration/$1/REVIEW.md and migration/$1/MIGRATION_RECORD.md with the four sections.
KIT_EOF_PI_PROMPTS_OSB_REVIEW_MD
mkdir -p "$(dirname "pi/run_flow.sh")"
cat > 'pi/run_flow.sh' <<'KIT_EOF_PI_RUN_FLOW_SH'
#!/usr/bin/env bash
# Agentic run of one OSB flow on the pi coding agent (https://pi.dev).
# Pi has no sub-agents, so each role is a separate `pi -p --no-session` process: a fresh context per role is exactly
# the independence the tester and reviewer need. Deterministic checks sit between the roles.
#
# Usage: pi/run_flow.sh <osb-project-dir> <flow> <module-dir> [--from analyse|implement|test|verify|review]
# Env:   OSB_PI_MODEL (model pattern for `pi --model`; not PI_MODEL, which pi itself sets), PI_THINKING (default high),
#        MAX_FIX_LOOPS (default 3), KIT (default: the directory above this script)
set -euo pipefail

PROJECT=${1:?usage: run_flow.sh <osb-project-dir> <flow> <module-dir> [--from phase]}
FLOW=${2:?flow name}
MODULE=${3:?module dir}
FROM=analyse
[ "${4:-}" = "--from" ] && FROM=${5:?phase}
KIT=${KIT:-$(cd "$(dirname "$0")/.." && pwd)}
OUT="migration/$FLOW"
LOG="$OUT/agent-logs"
MAX_FIX_LOOPS=${MAX_FIX_LOOPS:-3}
mkdir -p "$LOG"

PI_BASE=(pi --print --no-session --thinking "${PI_THINKING:-high}"
         --skill "$KIT/skills/osb-to-camel" --skill "$KIT/skills/camel-migration-verification")
[ -n "${OSB_PI_MODEL:-}" ] && PI_BASE+=(--model "$OSB_PI_MODEL")

# role <name> <tools> <prompt>: one fresh pi process with the role prompt appended to the system prompt
role() {
  local name=$1 tools=$2 prompt=$3 stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  echo ">> $name" >&2
  "${PI_BASE[@]}" --tools "$tools" --append-system-prompt "$KIT/agents/$name.md" "$prompt" \
    > "$LOG/$stamp-$name.out" 2> "$LOG/$stamp-$name.err"
  echo "$LOG/$stamp-$name.out"
}

# fingerprint of a directory tree (detects edits outside a role's lane; works without git)
# sha1sum on Git Bash/Linux, shasum on macOS
SHA=$(command -v sha1sum || command -v shasum)
fp() { [ -d "$1" ] && find "$1" -type f -print0 | sort -z | xargs -0 "$SHA" 2>/dev/null | "$SHA" | cut -c1-16 || echo none; }

approved() { grep -Eq '^\| \*\*Status\*\* \| *approved' "$OUT/FLOW_CARD.md" 2>/dev/null; }

phase_reached() { case "$FROM" in analyse) return 0;; implement) [ "$1" != analyse ];; test) [[ "$1" =~ ^(test|verify|review)$ ]];;
                  verify) [[ "$1" =~ ^(verify|review)$ ]];; review) [ "$1" = review ];; esac; }

# ---------------------------------------------------------------- S0 analyse
if phase_reached analyse; then
  role analyst "read,bash,edit,write" \
    "Use skill osb-to-camel Steps 0 and 1. OSB export: $PROJECT. Flow: $FLOW. Run the inventory into migration/osb-inventory, scaffold and complete $OUT/FLOW_CARD.md from the real OSB files. Status draft. End with a 5-line summary and the BLOCKING open items." > /dev/null
  [ -f "$OUT/FLOW_CARD.md" ] || { echo "analyst wrote no card"; exit 1; }
fi

# ---------------------------------------------------------------- S1 human gate A
if ! approved; then
  echo "STOP: $OUT/FLOW_CARD.md is not approved. A human sets '| **Status** | approved' plus the approver, then:"
  echo "      pi/run_flow.sh $PROJECT $FLOW $MODULE --from implement"
  exit 0
fi

TESTS_FP() { fp "$MODULE/src/test"; }
MAIN_FP()  { fp "$MODULE/src/main"; }

# ---------------------------------------------------------------- S2 implement
if phase_reached implement; then
  before=$(TESTS_FP)
  role implementer "read,bash,edit,write" \
    "Implement the approved card $OUT/FLOW_CARD.md with skill osb-to-camel Step 2 into Maven module $MODULE. OSB sources: $PROJECT. Run 'mvn -q -DskipTests -f $MODULE/pom.xml package' until it passes. Do not create or edit anything under $MODULE/src/test." > /dev/null
  [ "$(TESTS_FP)" = "$before" ] || { echo "VIOLATION: implementer changed $MODULE/src/test"; exit 1; }
fi

# ---------------------------------------------------------------- S3 test (fresh context, no implementer output passed)
if phase_reached test; then
  before=$(MAIN_FP)
  role tester "read,bash,edit,write" \
    "Write the test suite for flow $FLOW from the approved card $OUT/FLOW_CARD.md and the OSB evidence in $PROJECT, following skill osb-to-camel Step 3 and skill camel-migration-verification. Tests go to $MODULE/src/test; register every expected file in $MODULE/src/test/resources/golden/MANIFEST.csv. Do not edit $MODULE/src/main. Run 'mvn -q -f $MODULE/pom.xml verify' and report the result honestly." > /dev/null
  [ "$(MAIN_FP)" = "$before" ] || { echo "VIOLATION: tester changed $MODULE/src/main"; exit 1; }
fi

# ---------------------------------------------------------------- S4 verify + fix loop
if phase_reached verify; then
  loop=0
  until "$KIT/tools/verify_flow.sh" "$MODULE" "$FLOW"; do
    loop=$((loop + 1))
    if [ "$loop" -gt "$MAX_FIX_LOOPS" ]; then
      echo "BLOCKED after $MAX_FIX_LOOPS fix loops; see $OUT/verify-report.json"; exit 1
    fi
    before=$(TESTS_FP)
    role implementer "read,bash,edit,write" \
      "Fix loop $loop for flow $FLOW. Read $OUT/verify-report.json and the logs next to it. Change production code under $MODULE/src/main only. If a test is wrong, write $OUT/TEST_DISPUTE.md with evidence from the OSB files and stop." > /dev/null
    [ "$(TESTS_FP)" = "$before" ] || { echo "VIOLATION: implementer changed tests in fix loop $loop"; exit 1; }
    [ -f "$OUT/TEST_DISPUTE.md" ] && { echo "STOP: test dispute raised, a fresh tester or a human decides ($OUT/TEST_DISPUTE.md)"; exit 1; }
  done
fi

# ---------------------------------------------------------------- S5 review (read-only tools; the script writes the files)
if phase_reached review; then
  out=$(role reviewer "read,grep,find,ls" \
    "Review flow $FLOW: card $OUT/FLOW_CARD.md, module $MODULE, gates $OUT/verify-report.json, OSB sources $PROJECT. Print REVIEW.md content, then a line containing only =====RECORD=====, then MIGRATION_RECORD.md content.")
  awk '/^=====RECORD=====$/{exit} {print}' "$out" > "$OUT/REVIEW.md"
  awk 'f{print} /^=====RECORD=====$/{f=1}' "$out" > "$OUT/MIGRATION_RECORD.md"
  [ -s "$OUT/MIGRATION_RECORD.md" ] || echo "WARNING: reviewer output had no record section; see $out"
  if grep -q "BLOCKER" "$OUT/REVIEW.md"; then echo "Review has BLOCKER findings: $OUT/REVIEW.md"; exit 1; fi
fi

echo "DONE for $FLOW: gates green, review without BLOCKER. Next: human sign-off (gate B), then the E2E shadow run (TESTING.md L6)."
KIT_EOF_PI_RUN_FLOW_SH
mkdir -p "$(dirname "pi/preflight.sh")"
cat > 'pi/preflight.sh' <<'KIT_EOF_PI_PREFLIGHT_SH'
#!/usr/bin/env bash
# Preflight for the client VDI: checks everything the kit needs before the first run.
# Runs in Git Bash (Windows), WSL or Linux. Read-only: installs nothing, changes nothing.
# Usage: pi/preflight.sh [model-endpoint-url]
set -u
ok=0; warn=0; fail=0
pass() { printf '  [ OK ] %s\n' "$1"; ok=$((ok+1)); }
wrn()  { printf '  [WARN] %s\n' "$1"; warn=$((warn+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }   # $1 >= $2

echo "OS: $(uname -s 2>/dev/null) $(uname -r 2>/dev/null)"

echo "Agent"
if command -v node >/dev/null; then
  v=$(node -v | tr -d v); ver_ge "$v" 22.19.0 && pass "node $v" || bad "node $v < 22.19 (pi requirement)"
else bad "node not found (pi needs Node.js 22.19+)"; fi
if command -v pi >/dev/null; then pass "pi $(pi --version 2>/dev/null | head -1)"; else bad "pi not found"; fi
[ -n "${OSB_PI_MODEL:-}" ] && pass "OSB_PI_MODEL=$OSB_PI_MODEL" || wrn "OSB_PI_MODEL unset: pi uses its default model"
for f in "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/models.json" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/auth.json"; do
  [ -f "$f" ] && pass "found $f" || wrn "no $f (needed for a custom endpoint or stored login)"
done
[ "${PI_OFFLINE:-}" ] && pass "PI_OFFLINE set (no catalog/network calls)" || wrn "PI_OFFLINE unset: pi may call pi.dev (catalog, version check)"
[ "${PI_TELEMETRY:-}" = "0" ] && pass "PI_TELEMETRY=0" || wrn "PI_TELEMETRY not 0"
if [ -n "${1:-}" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null || echo 000)
  [ "$code" != "000" ] && pass "model endpoint reachable ($1 → HTTP $code)" || bad "model endpoint not reachable: $1"
fi

echo "Shell tools"
command -v bash >/dev/null && pass "bash $(bash --version | head -1 | awk '{print $4}')" || bad "bash missing (Git for Windows provides it)"
command -v sha1sum >/dev/null || command -v shasum >/dev/null && pass "sha1sum/shasum" || bad "no sha1sum/shasum"
PY=$(command -v python3 || command -v python || command -v py)
if [ -n "$PY" ]; then v=$("$PY" -c 'import sys;print("%d.%d"%sys.version_info[:2])'); ver_ge "$v" 3.10 && pass "python $v ($PY)" || bad "python $v < 3.10"
else bad "python not found"; fi
command -v git >/dev/null && pass "git" || wrn "git missing (lane checks still work, CI guard needs git)"

echo "Build and test"
if command -v java >/dev/null; then
  v=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/'); [ "$v" -ge 21 ] 2>/dev/null && pass "java $v" || bad "java $v < 21"
else bad "java not found (JDK 21)"; fi
if command -v mvn >/dev/null; then pass "maven $(mvn -v 2>/dev/null | head -1 | awk '{print $3}')"
  [ -f "$HOME/.m2/settings.xml" ] && pass "~/.m2/settings.xml present (mirror/proxy)" || wrn "no ~/.m2/settings.xml: Maven will try Maven Central directly"
else bad "maven not found"; fi
if docker info >/dev/null 2>&1; then pass "docker"; elif podman info >/dev/null 2>&1; then pass "podman"
else wrn "no Docker/Podman: gate G5 (Testcontainers Artemis) will be NOT RUN here; run level-2 tests where Docker is available"; fi

echo "Kit layout (run from the migration repository root)"
for p in AGENTS.md agents/analyst.md tools/verify_flow.sh pi/run_flow.sh; do [ -e "$p" ] && pass "$p" || bad "$p missing"; done
sk=0; for d in .pi/skills "$HOME/.pi/agent/skills" .agents/skills; do [ -f "$d/osb-to-camel/SKILL.md" ] && sk=1; done
[ $sk = 1 ] && pass "skill osb-to-camel discoverable" || bad "skill osb-to-camel not in .pi/skills, ~/.pi/agent/skills or .agents/skills"
# pi skips a SKILL.md whose front matter is not valid YAML, without an error: check the usual traps
for f in .pi/skills/*/SKILL.md "$HOME/.pi/agent/skills"/*/SKILL.md .agents/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  issue=$(awk 'NR==1 && $0!="---"{print "no front matter"; exit} NR>1 && $0=="---"{exit}
               NR>1 && /^[A-Za-z_-]+: /{v=$0; sub(/^[A-Za-z_-]+: /,"",v);
                 if (v ~ /^["\x27]/) next;
                 if (index(v,": ")) {print "unquoted \": \" in " $1; exit}
                 if (index(v," #")) {print "unquoted \" #\" in " $1; exit}
                 if (length(v)>1024 && $1=="description:") {print "description over 1024 characters"; exit}}' "$f")
  [ -z "$issue" ] && pass "front matter valid: $f" || bad "pi will skip $f: $issue"
done
[ -d osb-src ] && [ -n "$(ls -A osb-src 2>/dev/null)" ] && pass "osb-src/ has content" || wrn "osb-src/ empty: put the OSB export there"

echo; echo "Result: $ok ok, $warn warnings, $fail failures"
[ $fail -eq 0 ]
KIT_EOF_PI_PREFLIGHT_SH
mkdir -p .pi/prompts && cp pi/prompts/*.md .pi/prompts/
chmod +x pi/*.sh 2>/dev/null || true
echo "installed: 13 files (agent layer: AGENTS.md, role prompts, pi prompts, runner, preflight)"
