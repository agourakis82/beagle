#!/usr/bin/env bash
set -euo pipefail

host="${PROXMOX_5860_HOST:-5860-proxmox}"
user="${PROXMOX_5860_USER:-root}"

if [[ -z "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  echo "Set PROXMOX_ROOT_PASSWORD in the environment before running this script." >&2
  exit 1
fi

export SSHPASS="${PROXMOX_ROOT_PASSWORD}"

sshpass -e ssh \
  -o StrictHostKeyChecking=no \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  "${user}@${host}" '
    set -e
    hostname
    echo "--- secure boot ---"
    mokutil --sb-state
    echo "--- mok test ---"
    mokutil --test-key /var/lib/shim-signed/mok/MOK.der || true
    mokutil --test-key /var/lib/dkms/mok.pub || true
    echo "--- pending mok ---"
    mokutil --list-new || true
    echo "--- nvidia userspace ---"
    command -v nvidia-smi || true
    echo "--- device nodes ---"
    ls /dev/nvidia* 2>/dev/null || true
  '
