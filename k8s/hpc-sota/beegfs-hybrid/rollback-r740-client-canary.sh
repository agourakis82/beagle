#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.4}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

echo "==> Rolling back BeeGFS client canary on ${TARGET_HOST}"

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

systemctl disable --now beegfs-client || true
apt-get purge -y beegfs-client beegfs-tools || true
rm -f /etc/apt/sources.list.d/beegfs-trixie.list
rm -f /etc/apt/trusted.gpg.d/beegfs.asc
apt-get update || true

echo "==> Remaining BeeGFS packages"
dpkg -l | egrep '^ii +beegfs-|^ii +libbeegfs' || true
REMOTE
