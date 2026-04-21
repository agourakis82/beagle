#!/usr/bin/env bash
set -euo pipefail

host="${PROXMOX_5860_HOST:-5860-proxmox}"
user="${PROXMOX_5860_USER:-root}"
delay="${1:-+1}"

if [[ -z "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  echo "Set PROXMOX_ROOT_PASSWORD in the environment before running this script." >&2
  exit 1
fi

export SSHPASS="${PROXMOX_ROOT_PASSWORD}"

sshpass -e ssh \
  -o StrictHostKeyChecking=no \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  "${user}@${host}" \
  "shutdown -r ${delay} '5860 reboot for MOK enrollment'"

cat <<EOF
Reboot queued on ${host}.

At the blue MOK screen:
1. Enroll MOK
2. Continue
3. Yes
4. Enter the one-time password you used with queue-5860-mok-remote.sh
5. Reboot
EOF
