#!/usr/bin/env bash
# Rollback: undo SSH lockdown on this machine.
# Run via Tencent VNC web console if Tailscale breaks.
set -eu

echo "=== Rollback: Restoring SSH to public listen ==="

if grep -q '^ListenAddress' /etc/ssh/sshd_config; then
  sed -i 's/^ListenAddress.*/#&/' /etc/ssh/sshd_config
  echo "[OK] Removed ListenAddress directive"
fi

ufw allow 22/tcp 2>/dev/null && echo "[OK] UFW allowed port 22"
systemctl restart ssh
echo "[OK] sshd restarted — public SSH restored"

ss -tln | grep :22

echo "=== Rollback complete ==="
echo "To disable Tailscale entirely if needed:"
echo "  tailscale down && apt remove -y tailscale"