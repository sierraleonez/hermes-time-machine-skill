# Ansible IaC Skill — for Hermes Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A [Hermes Agent](https://hermes-agent.nousresearch.com) skill that teaches any Hermes instance to manage servers through Ansible playbooks — version-controlled, idempotent, no ad-hoc edits.

## What it does

When loaded, this skill instructs the agent to:

1. **Capture** current server state (packages, services, ports, configs)
2. **Encode** it into idempotent Ansible playbooks layered by concern
3. **Apply** through a dry-run → verify → apply → commit cycle
4. **Lock down** SSH behind Tailscale with safety gates and rollback scripts

The result: a git repo (`~/vps-infra/`) that is the single source of truth for your server. Every playbook run converges the machine toward the declared state.

## Installation

```bash
# Option 1 — from the Hermes skill registry (if available)
hermes skill install hermes-time-machine-skill

# Option 2 — clone and symlink
cd ~/.hermes/skills/devops/
git clone https://github.com/sierraleonez/hermes-time-machine-skill.git ansible-config-mgmt

# Option 3 — add to your config.yaml skills list
# skills:
#   - ansible-config-mgmt
```

After installing, Hermes auto-loads the skill when you mention Ansible, IaC, playbooks, server hardening, or infrastructure management.

## Contents

| Path | What |
|------|------|
| `SKILL.md` | Main skill — setup walkthrough + workflow + idempotency patterns + pitfalls |
| `README.md` | This file |
| `LICENSE` | MIT license |
| `references/github-git-auth.md` | Pushing repos from a server — PAT vs GitHub App |
| `references/vps-infra-repo-structure.md` | Reference repo layout |
| `scripts/capture-hashes.sh` | Baseline snapshot (packages, services, ports, Docker, configs) |
| `scripts/drift-check.sh` | Compare source vs target, exit 0 = in sync |
| `scripts/run-phase.sh` | Gated phased deployment (Tailscale → verify → lockdown → harden) |
| `scripts/rollback-ssh-lockdown.sh` | Restore public SSH via VNC (no SSH needed) |

## Quick start for a new server

```bash
# Install Ansible
apt install ansible

# Create repo skeleton
mkdir -p ~/vps-infra/{inventory,playbooks,vars,scripts,files}
cd ~/vps-infra && git init && git branch -m main
echo -e "*.vault\n*.env\n*.pem\n.deploy_key*\n" > .gitignore

# Write your first playbook (see SKILL.md for examples)
# ...
```

The **Setup / New Project Walkthrough** section in `SKILL.md` takes you step by step from bare server to running playbooks.

## Why this approach

- **Single source of truth** — the git repo, not the running box
- **Repeatable** — any server converges to the same state
- **Auditable** — every change has a commit
- **Self-hosted** — no CI/CD, no control plane, no dependencies beyond Ansible itself