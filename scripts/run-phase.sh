#!/usr/bin/env bash
# Phased deployment runner for VPS changes.
# Usage: source scripts/run-phase.sh <1|2|3|4>
set -euo pipefail
cd "$(dirname "$0")/.."

PHASE="${1:?Usage: source run-phase.sh <1|2|3|4>}"
INV="-i inventory/production.ini"

case "$PHASE" in
  1)
    echo "=== PHASE 1: Tailscale install ==="
    source /home/ubuntu/.env.tailscale 2>/dev/null || { echo "FATAL: Fill /home/ubuntu/.env.tailscale first"; exit 1; }
    ansible-playbook $INV -l src playbooks/05-tailscale.yml \
      -e tailscale_authkey="$TAILSCALE_AUTHKEY" \
      --become
    echo "Phase 1 done. Verify with: tailscale status"
    ;;

  2)
    echo "=== PHASE 2: Verify SSH over Tailscale ==="
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -z "$TS_IP" ]; then
      echo "FATAL: Tailscale not connected. Run phase 1 first."
      exit 1
    fi
    echo "Tailscale IP: $TS_IP"
    echo "From your MacBook, run: ssh ubuntu@$TS_IP"
    echo "Then: touch ~/vps-infra/.phase-2-done"
    ;;

  3)
    echo "=== PHASE 3: Lock SSH to Tailscale subnet ==="
    if [ ! -f ~/vps-infra/.phase-2-done ]; then
      echo "FATAL: Verify SSH over Tailscale first (phase 2)"
      exit 1
    fi
    ansible-playbook $INV -l src playbooks/06-ssh-lockdown.yml --become
    echo "Phase 3 done. SSH now only listens on Tailscale."
    echo "ROLLBACK: VNC -> bash scripts/rollback-ssh-lockdown.sh"
    ;;

  4)
    echo "=== PHASE 4: Full SSH hardening + UFW + fail2ban ==="
    if [ ! -f ~/vps-infra/.phase-2-done ]; then
      echo "FATAL: Verify SSH over Tailscale first (phase 2)"
      exit 1
    fi
    ansible-playbook $INV -l src playbooks/00-base.yml --become
    echo "Phase 4 done. Root login disabled, password auth off, UFW active."
    echo "ROLLBACK: VNC -> bash scripts/rollback-ssh-lockdown.sh"
    ;;

  *)
    echo "Invalid phase: $PHASE. Use 1, 2, 3, or 4."
    exit 1
    ;;
esac