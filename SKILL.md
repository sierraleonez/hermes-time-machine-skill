---
name: ansible-config-mgmt
description: Capture server state in Ansible, change only via playbooks.
version: 1.1.0
platforms: [linux]
---

# Ansible Configuration Management

Use when the user wants to capture a server's exact state into Ansible for replication, or declares that all future changes must go through Ansible playbooks.

Complementary to `infrastructure-deployment` (day-to-day service deployment). This governs the IaC workflow: capture -> encode -> verify -> change-through-playbooks.

## Setup / New Project Walkthrough

Follow these steps to adopt this approach on a fresh server. Each section links to the relevant deep-dive below.

### 0. Prerequisites

- A Linux server (Ubuntu 22.04+ recommended) with SSH or console access
- `ansible` installed (`apt install ansible` or `pip install ansible`)
- A GitHub account and a classic PAT with `repo` scope (for pushing the repo)
- Optional: Tailscale account + auth key (for SSH lockdown)

### 1. Create the repo

```bash
mkdir -p ~/vps-infra/{inventory,playbooks,vars,scripts,files}
cd ~/vps-infra
git init && git branch -m main
echo -e "*.vault\n*.env\n*.pem\n.deploy_key*\n" > .gitignore
git add .gitignore && git commit -m "skeleton"
```

### 2. Write your first playbook

Start small — `playbooks/00-base.yml` with just SSH hardening:

```yaml
---
- name: Base system hardening
  hosts: vps
  become: true
  tasks:
    - name: Disable root SSH login
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PermitRootLogin'
        line: 'PermitRootLogin no'
      notify: restart sshd

  handlers:
    - name: restart sshd
      ansible.builtin.service:
        name: ssh
        state: restarted
```

### 3. Add inventory and config

`inventory/production.ini`:
```ini
[vps]
src ansible_host=127.0.0.1 ansible_connection=local ansible_become=true
ansible_python_interpreter=/usr/bin/python3
```

`ansible.cfg`:
```ini
[defaults]
inventory = inventory/production.ini
host_key_checking = False
gathering = smart
```

### 4. Test it

```bash
ansible-playbook playbooks/00-base.yml --check --diff
# If ok:
ansible-playbook playbooks/00-base.yml --become
```

### 5. Create site.yml (the master playbook)

`site.yml` imports all playbooks in order:
```yaml
---
- import_playbook: playbooks/00-base.yml
# - import_playbook: playbooks/01-docker.yml
# - import_playbook: playbooks/02-caddy.yml
```

Comment out playbooks you haven't written yet — they're no-ops until uncommented.

### 6. Baseline snapshot

Run this once before any more changes, save the output for drift-checking:

```bash
dpkg-query --list | sort | md5sum    # packages
systemctl list-unit-files | sort | md5sum  # services
ss -tlnH | sort | md5sum             # listening ports
```

### 7. Secrets setup

```bash
# Create vault file
cat > vars/secrets.yml.vault <<'EOF'
vault_db_password: "hunter2"
vault_api_key: "sk-xxx"
EOF

# Encrypt (vault pass in $HOME, NEVER in repo)
echo "your-strong-vault-password" > ~/.vault-pass
chmod 600 ~/.vault-pass
ansible-vault encrypt vars/secrets.yml.vault
```

Add `~/.vault-pass` to `.gitignore` **before** any `git add`:
```bash
echo ".vault-pass" >> ~/vps-infra/.gitignore
```

### 8. Git push (one-time)

```bash
# Configure git identity
git config user.email "you@example.com" && git config user.name "Your Name"

# Push to GitHub via PAT
source ~/.env.gh   # or paste the PAT directly
git remote add origin https://github.com/<user>/vps-infra.git
git push -u origin main
```

### 9. Ongoing change cycle

```
1. Edit the playbook  →  2. --check --diff  →  3. Apply  →  4. Commit & push
```

No ad-hoc changes. If unavoidable, capture into a playbook immediately.

### 10. Extend layer by layer

Follow the layer order below (each playbook is a separate concern). Skip what you don't need.

---

## Core Workflow

### 0. Baseline summary first

Before writing any playbook or running any task, deliver a **human-readable summary** of the current machine state to the user: OS, users, listening services, Docker containers, key config files, security posture. Use labeled lines or bullets — no tables. This validates what you're working with and catches gaps early.

### 1. Baseline capture (one-time, before any changes)

```bash
mkdir -p ~/vps-infra/{inventory,group_vars,playbooks,vars,scripts}
cd ~/vps-infra && git init && git branch -m main
echo -e "*.vault\n*.env\n*.pem\n.deploy_key*\n" > .gitignore
git add .gitignore && git commit -m "repo skeleton"
```

### 2. Inventory

`inventory/production.ini`:
```ini
[vps]
src ansible_host=127.0.0.1 ansible_connection=local ansible_become=true
ansible_python_interpreter=/usr/bin/python3
```

### 3. Capture baseline hashes FIRST

Run `scripts/capture-hashes.sh` before any playbook applies. Records md5 hashes for:
- Packages (dpkg-query sorted | md5sum)
- Enabled services (systemctl list-unit-files sorted | md5sum)
- Listening ports (ss -tlnH sorted | md5sum)
- Caddyfile sha256
- www file tree sha256 aggregate
- Docker containers (names + images sorted | md5sum)
- Hermes config and metrics source sha256s

### 4. Write playbooks by layer

- **00-base.yml** — users, SSH hardening, UFW, fail2ban, base packages, timezone, chrony
- **01-docker.yml** — Docker engine, container defs (pinned images), volumes
- **02-caddy.yml** — Caddyfile, www/ files, reload handler
- **03-your-app.yml** — your app config, .env (vaulted), metrics, systemd unit
- **04-your-app.yml** — your app Docker stack, env files

`site.yml` imports all in order.

### 5. Secrets

- `vars/secrets.yml.vault` — plaintext then `ansible-vault encrypt`
- Vault password = password manager, NOT repo
- `no_log: true` on vaulted copy tasks
- `.env`, `.vault`, `.pem` in .gitignore

### 6. Drift-check

`scripts/drift-check.sh` compares source vs target with `ansible <host> -m shell`. Must exit 0 before DNS cutover. Document known-acceptable diffs (hostname, IP, cloud-agent packages).

### 7. Change workflow (ongoing)

1. Edit the relevant playbook
2. Dry-run: `ansible-playbook --check --diff site.yml`
3. Apply: `ansible-playbook site.yml --ask-vault-pass`
4. Commit the playbook change
5. Announce what changed

No ad-hoc changes unless emergency. If unavoidable, capture into a playbook immediately after.

### 8. Idempotency verification

First run on a vulnerable source box shows `changed` for hardening. Second `--check` must be all `ok`.

## Secrets inventory

| Secret | Source |
|--------|--------|
| DB credentials | container env or docker-compose.yml |
| Hermes .env API keys | ~/.hermes/.env |
| App env vars | project .env.docker |
| SSH keys | never committed |

## Idempotency patterns

Two common non-idempotent patterns to fix:

### Direct `state: restarted` on services

**WRONG** — restarts every playbook execution:
```yaml
- name: Restart sshd
  ansible.builtin.service:
    name: ssh
    state: restarted
```

**RIGHT** — only restarts when config changes:
```yaml
- name: Disable root SSH login
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin no'
  notify: restart sshd

handlers:
  - name: restart sshd
    ansible.builtin.service:
      name: ssh
      state: restarted
```

### Direct `daemon_reload: true` on systemd

**WRONG** — fires every run even on unchanged unit file:
```yaml
- name: Enable and start metrics service
  ansible.builtin.systemd:
    name: app-metrics
    state: started
    enabled: true
    daemon_reload: true
```

**RIGHT** — only reloads on unit file change:
```yaml
- name: app-metrics systemd unit
  ansible.builtin.copy:
    src: files/app/app-metrics.service
    dest: /etc/systemd/system/app-metrics.service
    mode: "0644"
  notify: reload app-metrics

- name: Enable and start metrics service
  ansible.builtin.systemd:
    name: app-metrics
    state: started
    enabled: true

handlers:
  - name: reload app-metrics
    ansible.builtin.systemd:
      name: app-metrics
      daemon_reload: true
      state: restarted
```

## Tailscale tunnel + SSH lockdown

### Playbook 05 — Tailscale install and connect

Key idempotence pattern: use `creates:` flag so the `tailscale up` command runs only once:
```yaml
- name: Connect to tailnet
  ansible.builtin.shell:
    cmd: tailscale up --authkey="{{ tailscale_authkey }}" --hostname="vm-name"
    creates: /var/lib/tailscale/tailscaled.state
```

Auth key is passed via `-e` flag, sourced from a local `.env` file — never in the vault.

### Playbook 06 — Lock SSH to Tailscale subnet

1. **Safety gate**: check Tailscale is connected before touching sshd
2. **Bind**: `ListenAddress <tailscale-subnet>` in sshd_config
3. **UFW**: open UDP 41641 for Tailscale WireGuard
4. **Rollback**: `scripts/rollback-ssh-lockdown.sh` restores public SSH via VNC

### Setup tokens: NOT in vault

- `GITHUB_TOKEN` in `~/.env.gh` — used once to `git push`
- `TAILSCALE_AUTHKEY` in `~/.env.tailscale` — used once for `tailscale up`
- Both expire or get revoked after use
- Source them from shell at deploy time, never commit to repo
- The vault is for **persistent deployment secrets** (DB passwords, API keys, credentials)

### GitHub git auth from the box

To push the repo from the server with a PAT:

```bash
source ~/.env.gh
git remote set-url origin https://oauth2:$GITHUB_TOKEN@github.com/<user>/<repo>.git
git push -u origin main
```

- **Prefer a CLASSIC PAT with `repo` scope for git push.** Fine-grained PATs can CREATE repos via API (permissions object shows `admin: true`) yet still get `403 Write access to repository not granted` on git push over HTTPS — even after "All repositories" access is granted. Bug pattern, not a permission config error.
- **Tell the two apart**: `curl -sI -H "Authorization: Bearer $TOKEN" https://api.github.com/user | grep -i x-oauth-scopes` — classic tokens return scopes (`repo, workflow`); fine-grained tokens return the header empty.
- **Create the repo via API first** if it doesn't exist: `POST /user/repos` with `{"name":..., "private": true}`, read `full_name` from the response (the repo lands under the token's account — don't hardcode the username).
- **GitHub App vs PAT**: PAT = simple, acts as the user, right for pushing repos from a box. GitHub App = distinct bot identity for commits, per-repo scoped permissions, org-level automation, webhooks — worth it when "hermes-bot authored this" matters. App is registered via a one-time bootstrap classic PAT with `app:creator` scope, or created manually at https://github.com/settings/apps/new (then only the private key + app ID ever touch the box).
- Full detail: `references/github-git-auth.md`

### Rollback strategy

`scripts/rollback-ssh-lockdown.sh` — single script safe to run from VNC web console (no SSH needed):
1. Comment out `ListenAddress` in sshd_config
2. `ufw allow 22/tcp`
3. `systemctl restart ssh`
4. Public SSH restored immediately

To roll back Tailscale separately: `tailscale down && apt remove -y tailscale`

## Phased gated deployment

For zero-danger rollouts of SSH-related changes, use a gated phase script:

```bash
# Phase 1: Tunnel up (needs TAILSCALE_AUTHKEY)
source ~/.env.tailscale
ansible-playbook -l src playbooks/05-tailscale.yml -e tailscale_authkey="$TAILSCALE_AUTHKEY" --become

# Phase 2: Manual verification
ssh user@$(tailscale ip -4)  # from your laptop over tailnet
# Creates .phase-2-done marker

# Phase 3: Lock SSH to tailnet (gated on phase-2-done)
ansible-playbook -l src playbooks/06-ssh-lockdown.yml --become

# Phase 4: Full hardening (gated on phase-2-done)
ansible-playbook -l src playbooks/00-base.yml --become
```

Each phase is independently rollback-able. Phase 3 and 4 refuse to run without the verification marker.

## Vault secrets wiring

Vault variables are NOT auto-loaded from `inventory/vars/`. Each playbook that uses vault vars must include them explicitly:

```yaml
- name: Docker — engine + your containers
  hosts: vps
  become: true
  vars_files:
    - ../inventory/vars/secrets.yml.vault
```

Only `group_vars/` and `host_vars/` are auto-loaded. Keep vault files in a separate `vars/` directory and wire via `vars_files` per playbook.

For vaulted `.env` files (e.g. Hermes, Laravel), use `copy` with `content:` and `no_log: true`:

```yaml
- name: Restore Hermes .env (vaulted)
  ansible.builtin.copy:
    content: "{{ vault_hermes_env }}\n"
    dest: ~/.hermes/.env
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: "0600"
  no_log: true
```

## Ubuntu 24.04 ssh.socket bypasses ListenAddress

A critical Ubuntu 24.04-specific trap: **`ListenAddress` in `sshd_config` is silently ignored while `ssh.socket` (systemd socket activation) is enabled.** The socket pre-binds `0.0.0.0:22` before sshd reads its config.

**Symptoms**: you set `ListenAddress 100.92.194.79` in sshd_config, restart ssh, and `ss -tlnp` still shows `0.0.0.0:22`.

**Fix in the playbook**:
```yaml
- name: Disable ssh.socket (bypasses ListenAddress)
  ansible.builtin.systemd:
    name: ssh.socket
    state: stopped
    enabled: false
```
Then set `ListenAddress` and restart sshd. Must happen in that order.

**Rollback** must re-enable ssh.socket:
```bash
systemctl enable --now ssh.socket
```

This applies to Ubuntu 22.04+ where `ssh.socket` is the default activation mechanism.

## Pitfalls

- **Baseline after hardening** — capture BEFORE playbook hardens SSH/firewall.
- **Hostname/IP/cloud-agent always differ** between source and target.
- **ForceCommand breaks scp** — detect scp/sftp in `SSH_ORIGINAL_COMMAND`.
- **Vault password single point of failure** — password manager.
- **Pin image tags** — untagged images drift on redeploy.
- **Git identity on first commit** — git auto-uses `Ubuntu <ubuntu@localhost>` if unconfigured. Set `git config user.name` and `user.email` before first commit, or amend after.
- **Verify tailnet connectivity BEFORE locking SSH** — gate the action on a manual check.
- **`docker.io` conflicts with Docker CE's `containerd.io`** — The Ubuntu `docker.io` package and Docker's `docker-ce` both install `containerd` but with different package names. Docker CE from the official repo ships its own `containerd.io`. On a machine with Docker CE installed, trying to install `docker.io` from Ubuntu repos in a playbook will fail: `containerd.io.conflicts: containerd`. Pattern: install Docker via the official Docker repo, OR install `docker-ce`, OR install `docker.io` — never both. The playbook packages list must match what the source actually has (check with `dpkg -l`).
- **`copy` with `src:` paths are relative to the playbook directory, not the repo root** — When playbooks live in a subdirectory (e.g. `playbooks/02-caddy.yml`) and source files live at the repo root (e.g. `files/caddy/Caddyfile`), use `{{ playbook_dir }}/../` to resolve: `src: "{{ playbook_dir }}/../files/caddy/Caddyfile"`. Without this, Ansible searches `playbooks/files/caddy/Caddyfile` and fails. Exception: the `inventory/production.ini` inventory file always resolves from the repo root when using `ansible.cfg` with `inventory = inventory/production.ini` — only `copy` `src:` paths have this quirk.
- **`group_vars/` must be inside the inventory directory, not at repo root** — Ansible looks for `group_vars/all.yml` relative to the inventory file. Structure: `inventory/production.ini`, `inventory/group_vars/all.yml`, `inventory/vars/secrets.yml.vault`. Having `group_vars/` at the repo root alongside `production.ini` does NOT work unless the inventory path includes the directory — `ansible-playbook -i production.ini` searches alongside the ini file.
- **Check-mode `authorized_key` fails with non-existent user** — `ansible.posix.authorized_key` requires the target user to exist in check mode. When the playbook creates a user (via `ansible.builtin.user`) and then adds an SSH key (via `authorized_key`), check mode will fail on the key task because `user` module doesn't create users in check mode. This is normal — the real run works fine. Document as expected check-mode noise.
- **Setup tokens are not vault material** — `GITHUB_TOKEN`, `TAILSCALE_AUTHKEY` are ephemeral: used once, then expire/revoke. Source them from local `.env.*` files at deploy time (`source ~/.env.tailscale && ... -e tailscale_authkey="$TAILSCALE_AUTHKEY"`). Never put them in the vault or commit them. The vault is for persistent deployment secrets that must be deployed every playbook run.
- **Vault password file must live OUTSIDE the repo** — `echo "pass" > ~/.vault-pass` (not inside `~/vps-infra/`). A password file written inside the repo gets picked up by `git add -A` and committed; removing it later does NOT purge git history. A leaked vault password exposes every vaulted secret (PAT, DB passwords) → full rotation of all secrets in the vault is required. Protocol: write the file in `$HOME`, add its exact name to `.gitignore` BEFORE the first `ansible-vault encrypt`, use `--vault-password-file $HOME/.vault-pass`, and never blind `git add -A` when a secrets plane exists in the working tree.

## Related skills

- `infrastructure-deployment` — deploying Docker services behind Caddy

## Supporting files

- `scripts/capture-hashes.sh` — baseline before any changes
- `scripts/drift-check.sh` — source vs target comparison
- `scripts/run-phase.sh` — gated phased deployment
- `scripts/rollback-ssh-lockdown.sh` — restore public SSH via VNC
- `references/vps-infra-repo-structure.md` — repo layout
- `references/github-git-auth.md` — PAT/GitHub-App auth for pushing from the box + vault-pass incident
