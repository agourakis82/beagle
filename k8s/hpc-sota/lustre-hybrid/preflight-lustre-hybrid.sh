#!/usr/bin/env bash
set -euo pipefail

nodes=(
  "10.100.100.2:t560-proxmox"
  "10.100.100.3:5860-proxmox"
  "10.100.100.4:r740-proxmox"
  "10.100.100.1:r770-proxmox"
)

password="${SSHPASS:-}"
if [[ -z "${password}" ]]; then
  echo "Set SSHPASS first." >&2
  exit 1
fi

for item in "${nodes[@]}"; do
  ip="${item%%:*}"
  name="${item##*:}"
  echo "=== ${name} (${ip}) ==="
  sshpass -e ssh -o StrictHostKeyChecking=no "root@${ip}" '
    set -e
    hostname
    uname -r
    . /etc/os-release
    echo "$PRETTY_NAME"
    echo "-- block devices --"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
    echo "-- nvme --"
    lspci | egrep -i "nvme|raid|sas|storage"
    echo "-- candidate paths --"
    df -h / /mnt/hpc-local-nvme /mnt/ai-runtime /zfast 2>/dev/null || true
  '
  echo
done
