#!/usr/bin/env bash
# Records baseline config hashes for drift-check.
# Run on source box before any playbook changes.
set -euo pipefail
LOG=~/vps-infra/baseline-hashes.txt

echo "=== Baseline $(date -Iseconds) ===" > "$LOG"
echo "packages:     $(dpkg-query -W -f='${Package} ${Version}\n' | sort | md5sum)" >> "$LOG"
echo "services:     $(systemctl list-unit-files --state=enabled --no-pager | awk '{print $1}' | sort | md5sum)" >> "$LOG"
echo "ports:        $(ss -tlnH | awk '{print $4}' | sort | md5sum)" >> "$LOG"
echo "caddyfile:    $(sha256sum /etc/caddy/Caddyfile)" >> "$LOG"
echo "www:          $(find /etc/caddy/www -type f | sort | xargs sha256sum | md5sum)" >> "$LOG"
echo "containers:   $(docker ps -a --format '{{.Names}} {{.Image}}' | sort | md5sum)" >> "$LOG"
echo "hermes_conf:  $(sha256sum /home/ubuntu/.hermes/config.yaml)" >> "$LOG"
echo "metrics_src:  $(sha256sum /home/ubuntu/couchdb-obsidian/metrics_server.py)" >> "$LOG"
cat "$LOG"