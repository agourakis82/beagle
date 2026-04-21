#!/usr/bin/env bash
set -euo pipefail

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

echo "== gpu nodes in kubernetes =="
k get nodes -L sounio.dev/accelerator -L sounio.dev/pool \
  -o custom-columns=NAME:.metadata.name,ACCEL:.metadata.labels.sounio\\.dev/accelerator,POOL:.metadata.labels.sounio\\.dev/pool,GPU:.status.allocatable.nvidia\\.com/gpu,INTERNAL_IP:.status.addresses[0].address

echo
echo "== network-operator related CRDs =="
k get crd | grep -Ei 'network-attachment|nicclusterpolicy|macvlan|whereabouts|multus|rdma' || echo "none"

echo
echo "== phase-2 prerequisites =="
echo "- Current underlay is already on 10.100.100.x"
echo "- Secondary fabric should be healthy on 10.200.0.x with MTU 9000"
echo "- Network Operator / Multus / RDMA shared plugin are not required for phase 1"

if [[ -n "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "FAIL: PROXMOX_ROOT_PASSWORD is set but sshpass is not installed" >&2
    exit 1
  fi

  export SSHPASS="${PROXMOX_ROOT_PASSWORD}"
  echo
  echo "== host RDMA spot checks =="
  for host in r770-proxmox r740-proxmox 5860-proxmox; do
    echo "--- ${host} ---"
    sshpass -e ssh -o StrictHostKeyChecking=no root@"${host}" \
      'hostname; lsmod | egrep "mlx5_ib|mlx5_core|ib_core" || true; command -v ibdev2netdev >/dev/null 2>&1 && ibdev2netdev || echo "ibdev2netdev not installed"; command -v rdma >/dev/null 2>&1 && rdma link show || echo "rdma tool not installed"; nvidia-smi -L || true' \
      | sed -n '1,80p'
    echo
  done
fi

