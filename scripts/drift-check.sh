#!/usr/bin/env bash
# Compare source vs target VPS. Exit 0 = in sync.
set -euo pipefail
SRC="${1:-src}"
TGT="${2:-tgt}"
inv="-i inventory/production.ini"
fail=0
check() {
  local name="$1" cmd="$2"
  local a b
  a=$(ansible "$SRC" -m shell -a "$cmd" --become 2>/dev/null | tail -n +2 | tail -1)
  b=$(ansible "$TGT" -m shell -a "$cmd" --become 2>/dev/null | tail -n +2 | tail -1)
  if [ "$a" != "$b" ]; then
    echo "DRIFT [$name]"; fail=1
  fi
  echo "$name $(date -Iseconds) ${a:0:40} ${b:0:40}" >> ~/vps-infra/drift.log
}
check "packages"    "dpkg-query -W -f='\${Package} \${Version}\n' | sort | md5sum"
check "services"    "systemctl list-unit-files --state=enabled --no-pager | awk '{print \$1}' | sort | md5sum"
check "ports"       "ss -tlnH | awk '{print \$4}' | sort | md5sum"
check "caddyfile"   "sha256sum /etc/caddy/Caddyfile"
check "www"         "find /etc/caddy/www -type f | sort | xargs sha256sum | md5sum"
check "containers"  "docker ps -a --format '{{.Names}} {{.Image}}' | sort | md5sum"
exit $fail