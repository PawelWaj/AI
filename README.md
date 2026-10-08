# AI

AI-assisted engineering assets: agent skills, role prompts and the deterministic tooling around them.

## Contents

| Path | What it is |
|---|---|
| [`skills/osb-camel-agent-kit/`](skills/osb-camel-agent-kit/) | Kit for migrating Oracle Service Bus (OSB 11g/12c) flows to Apache Camel on Spring Boot with an AI coding agent: two Agent Skills, role prompts, an agentic runner for the [pi](https://pi.dev) coding agent, and quality gates that run without AI |
| [`skills/osb-camel-agent-kit.zip`](skills/osb-camel-agent-kit.zip) | The same kit as one archive |
| [`skills/README.md`](skills/README.md) | Overview of the skills folder and a quick install |

## OSB to Camel agent kit at a glance

```
OSB export ─► ANALYST ─► flow card ─► HUMAN APPROVAL ─► IMPLEMENTER ─► TESTER ─► GATES G1-G8 ─► REVIEWER ─► record
                                                            ▲                         │ red (max 3x)
                                                            └──────── fix loop ───────┘
```

- **Skills** (open Agent Skills format, `SKILL.md`):
  - `osb-to-camel`: inventory and triage of an OSB export, a design card per flow, generation of the Camel route, transforms, configuration and a mocked test suite.
  - `camel-migration-verification`: how to verify generated code, the gates and the shadow run.
- **Agents:** analyst, implementer, tester and reviewer role prompts. Each role runs in a fresh context; the tester never sees the implementer's reasoning.
- **Gates:** `tools/verify_flow.sh` covers build, Camel endpoint validation, repository rules, unit and integration tests, test-matrix coverage, oracle provenance and transform mutation. Acceptance comes from script output, not from what the model says.
- **Runs on:**
  - pi, interactively (`/osb-analyse` … `/osb-review`) or unattended (`pi/run_flow.sh`);
  - any agent that reads `AGENTS.md` and Agent Skills.

Start with [`skills/osb-camel-agent-kit/README.md`](skills/osb-camel-agent-kit/README.md), then `TRIAL_GUIDE.md`.

## Quick install into a migration project

```bash
git clone https://github.com/PawelWaj/AI.git
cd <your-migration-repo>
cp -r ../AI/skills/osb-camel-agent-kit/{AGENTS.md,agents,tools,pi} .
mkdir -p .pi/skills .pi/prompts
cp -r ../AI/skills/osb-camel-agent-kit/skills/* .pi/skills/
cp ../AI/skills/osb-camel-agent-kit/pi/prompts/*.md .pi/prompts/
pi/preflight.sh
```

Before generating code for a real programme, fill `.pi/skills/osb-to-camel/references/programme-rules.md` with that
programme's decisions: runtime, logging, secrets, messaging, cut-over.

## Status

- **Inventory and triage scripts:** tested on the bundled synthetic OSB fixtures.
- **Code and test generation:** evaluated on a synthetic flow only. Validate on your own flows, starting with a small pilot, before relying on it.
