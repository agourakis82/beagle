#!/usr/bin/env bash
set -euo pipefail

hosts=(t560-proxmox r770-proxmox r740-proxmox 5860-proxmox)

if [[ -n "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  remote() {
    SSHPASS="${PROXMOX_ROOT_PASSWORD}" sshpass -e ssh -o StrictHostKeyChecking=no "root@$1" "${@:2}"
  }
else
  remote() {
    ssh -o StrictHostKeyChecking=no "root@$1" "${@:2}"
  }
fi

for host in "${hosts[@]}"; do
  echo "=== ${host} ==="
  remote "$host" '
set -e
hostname
ip -br addr | egrep "10.200.0.|vmbr200|vmbr1"
echo ---
lsmod | egrep "mlx5_ib|mlx5_core|ib_core" || true
echo ---
if command -v ibdev2netdev >/dev/null 2>&1; then
  ibdev2netdev || true
fi
echo ---
ip link show vmbr200 2>/dev/null | sed -n "1,2p" || true
ip link show vmbr1 2>/dev/null | sed -n "1,2p" || true
' || true
  echo
done
