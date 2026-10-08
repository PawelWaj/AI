# Paste-install on the VDI (no file transfer needed)

Run each script from the migration repository root in Git Bash or WSL, in this order. Each one ends with an
`installed: N files` line; if that line is missing, the paste was truncated: paste that script again.

| Script | Installs | Size |
|---|---|---|
| `1_install_agents.sh` | AGENTS.md, agents/*.md (role prompts), pi/prompts + .pi/prompts (/osb-* commands), pi/run_flow.sh, pi/preflight.sh | 26 KB |
| `2_install_gates.sh` | tools/verify_flow.sh, check_matrix.py, check_oracle.py, mutate_transforms.py, compare_shadow.py, pom plugins, Jenkins stages | 22 KB |
| `3_install_skill_osb_core.sh` | .pi/skills/osb-to-camel: SKILL.md, scripts, references | 141 KB |
| `4_install_skill_osb_templates.sh` | .pi/skills/osb-to-camel/assets/templates | 80 KB |
| `5_install_skill_verification.sh` | .pi/skills/camel-migration-verification | 11 KB |

How to paste a script: in the VDI terminal type `cat > 1_install_agents.sh`, press Enter, paste, press Ctrl-D,
then `bash 1_install_agents.sh`. Afterwards: `pi/preflight.sh`, then start `pi` and check the startup header lists
AGENTS.md, both skills and the /osb-* prompts.
