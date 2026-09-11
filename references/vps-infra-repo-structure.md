# Recommended Repo Structure

A suggested layout for your Ansible IaC repo — adjust to match your services.

```
vps-infra/
├── ansible.cfg                 — inventory path, host_key_checking=false
├── inventory/
│   ├── production.ini          — [vps] src (localhost), optionally tgt (remote)
│   ├── group_vars/
│   │   └── all.yml             — shared defaults (timezone, admin_user, base packages)
│   └── vars/
│       └── secrets.yml.vault   — ansible-vault encrypted secrets
├── playbooks/
│   ├── 00-base.yml             — timezone, packages, users, SSH hardening, firewall
│   ├── 01-docker.yml           — Docker engine + your containers
│   ├── 02-reverse-proxy.yml    — Caddy / Nginx config + static files
│   ├── 03-your-app.yml         — your app: systemd unit, env, config
│   └── site.yml                — imports all playbooks in order
├── files/
│   ├── proxy/                  — config files for your reverse proxy
│   ├── app/                    — app configs, systemd units
│   └── ssh/                    — admin public keys
├── scripts/
│   ├── capture-hashes.sh       — baseline snapshot before any changes
│   ├── drift-check.sh          — source vs target comparison
│   └── rollback-ssh-lockdown.sh— restore public SSH (VNC-safe)
├── README.md                   — this repository
├── .gitignore                  — *.vault, *.env, *.pem, .deploy_key*
└── baseline-hashes.txt         — initial state hashes (captured before first apply)
```

## Key path quirk

In `playbooks/*.yml`, use `{{ playbook_dir }}/../files/...` to reference the repo-root `files/` directory. Ansible resolves `copy` `src:` paths relative to the playbook's own directory, not the repo root.