# GitHub auth from a server — PAT vs App + vault-pass incident

## Classic vs Fine-grained PAT

| Type | Git push over HTTPS | API scopes header | Works for `git push` |
|------|--------------------|--------------------|----------------------|
| **Classic PAT** (`repo` scope) | ✅ Works | `x-oauth-scopes: repo, workflow` | Always |
| **Fine-grained PAT** | ❌ 403 even on own repos | Header is empty (not returned by design) | Often fails despite API showing `push: true` |

**Tell them apart**: `curl -sI -H "Authorization: Bearer $TOKEN" https://api.github.com/user 2>&1 | grep -i x-oauth-scopes` — classic returns scopes; fine-grained returns nothing.

**When fine-grained fails**: the API at `/repos/<owner>/<repo>` shows `{"permissions": {"admin": true, "push": true}}` and you granted "All repositories" — but `git push` still gets `403 Write access to repository not granted`. This is a known GitHub bug pattern, not a misconfiguration. Switch to a classic PAT with `repo` scope.

## PAT workflow

### Create repo via API (if it doesn't exist)

```bash
# POST without guessing the username — response tells you the full_name
curl -s -X POST https://api.github.com/user/repos \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -d '{"name":"my-new-repo","private":true}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('full_name','ERROR: '+d.get('message','?')))"
```

### Set remote and push

```bash
source /home/ubuntu/.env.gh
git remote set-url origin https://oauth2:$GITHUB_TOKEN@github.com/<owner>/<repo>.git
git push -u origin main
```

The `oauth2:` prefix avoids URL-encoding issues with special chars in the token.

## GitHub App

A GitHub App creates a distinct bot identity (commits show as "hermes-agent-bot") with per-repo scoped permissions. Useful when:
- You want bot-authored commits distinguishable from user commits
- You need org-level repo management without full account access
- You need webhooks (auto-deploy on push, PR checks)

### Bootstrap via PAT (from the server)

1. Create a classic PAT with `app:creator` + `repo` scopes
2. Register the app via `POST /orgs/{org}/apps` or `POST /user/apps` with the app manifest
3. The private key is generated and returned — store in the Ansible vault
4. Revoke the bootstrap PAT immediately
5. Authenticate all future git operations via JWT signed with the app private key

### Manual creation (no PAT on the server)

1. Go to https://github.com/settings/apps/new
2. Name: e.g. `hermes-agent-bot`, Permissions → Repository → Contents (Read & write), Metadata (Read-only)
3. Generate private key → download PEM
4. Install on repos
5. Send the private key path / content + app ID to the agent → stored in secrets.yml.vault

This path never exposes a PAT to the server.

## Vault-pass incident: what to do when .vault-pass leaks into git

If the plaintext vault password file gets committed (e.g. via `git add -A` while it sits inside the repo):

1. **Rotate every secret in the vault immediately** — the vault password + every encrypted value is compromised
2. **Create new secrets**: new CouchDB admin password, new Hermes API tokens, new DB passwords, new GitHub PAT
3. **Rewrite git history** to purge the leaked commit:
   ```bash
   # Find the last clean commit
   git log --oneline
   # Reset to that commit preserving working tree changes
   git reset --soft <last-clean-commit>
   # Re-stage only the files that belong, NOT .vault-pass
   git add -A
   git commit -m "message"
   git push --force-with-lease origin main
   ```
4. **Add the password file path to `.gitignore`** BEFORE the next `git add -A`
5. Update the vault password everywhere (local `.vault-pass` file, password manager)
6. Re-encrypt the vault with the new password:
   ```bash
   echo "new-password" > $HOME/.vault-pass
   chmod 600 $HOME/.vault-pass
   ansible-vault decrypt inventory/vars/secrets.yml.vault --vault-password-file $HOME/.vault-pass-old
   # edit secrets to new values
   ansible-vault encrypt inventory/vars/secrets.yml.vault --vault-password-file $HOME/.vault-pass
   rm $HOME/.vault-pass-old
   ```

**Better: never have the vault password file inside the repo directory.** Keep it in `$HOME` and use an absolute path in `--vault-password-file $HOME/.vault-pass`.

## Standing user preferences

- **Always dry-run before applying** to a live box: `--check --diff`. The user explicitly required this.
- **All server changes must go through the playbook** and be committed. No ad-hoc unless emergency, then captured into a playbook immediately after.
- **Phased rollout for SSH-critical changes**: tunnel → verify connectivity → lock → harden. Each phase independently rollbackable via VNC script.
- **Setup tokens**: source at runtime, never commit to repo or vault.

## Changelog

### 2026-09-09 — Extracted from Tailscale implementation session

- Classic vs fine-grained PAT gotcha documented
- Vault-pass incident recovery documented
- Standing user preferences for change workflow added