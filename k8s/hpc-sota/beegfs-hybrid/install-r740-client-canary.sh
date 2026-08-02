#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.4}"
BEEGFS_VERSION="${BEEGFS_VERSION:-8.3}"
BEEGFS_DIST="${BEEGFS_DIST:-trixie}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

echo "==> Installing BeeGFS client canary on ${TARGET_HOST}"

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 /etc/apt/trusted.gpg.d
curl -fsSL https://www.beegfs.io/release/beegfs_8.3/gpg/GPG-KEY-beegfs \
  -o /etc/apt/trusted.gpg.d/beegfs.asc
curl -fsSL https://www.beegfs.io/release/beegfs_8.3/dists/beegfs-trixie.list \
  -o /etc/apt/sources.list.d/beegfs-trixie.list

apt-get update
apt-get install -y --no-install-recommends \
  beegfs-client \
  beegfs-tools \
  proxmox-headers-$(uname -r)

/opt/beegfs/sbin/beegfs-client rebuild
systemctl enable beegfs-client

echo "==> Installed packages"
dpkg -l | egrep '^ii +beegfs-|^ii +libbeegfs|^ii +proxmox-headers' | sed -n '1,120p'

echo "==> beegfs-client status"
systemctl --no-pager --full status beegfs-client || true

echo "==> kernel module presence"
find /lib/modules/$(uname -r) -path '*beegfs*' | sed -n '1,40p'
REMOTE
