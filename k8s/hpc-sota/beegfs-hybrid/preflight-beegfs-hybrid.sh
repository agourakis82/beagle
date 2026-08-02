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
    echo "-- rdma --"
    lspci | egrep -i "mellanox|infiniband|ethernet|nvme|raid" || true
    echo "-- local candidates --"
    df -h / /zfast /mnt/hpc-local-nvme /mnt/ai-runtime 2>/dev/null || true
    echo "-- block overview --"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | sed -n "1,40p"
  '
  echo
done
