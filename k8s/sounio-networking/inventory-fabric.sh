#!/usr/bin/env bash
set -euo pipefail

hosts=(t560-proxmox r770-proxmox r740-proxmox 5860-proxmox)
remote_user="${REMOTE_USER:-root}"
remote_pass="${PROXMOX_ROOT_PASSWORD:-}"

if ! command -v kubectl >/dev/null 2>&1 && ! sudo kubectl version >/dev/null 2>&1; then
  echo "kubectl or sudo kubectl is required" >&2
  exit 1
fi

if [[ -z "${remote_pass}" ]]; then
  echo "Set PROXMOX_ROOT_PASSWORD to inspect the Proxmox hosts over SSH." >&2
  exit 1
fi

export SSHPASS="${remote_pass}"

for host in "${hosts[@]}"; do
  echo "=== ${host} ==="
  sshpass -e ssh \
    -o StrictHostKeyChecking=no \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o ConnectTimeout=8 \
    "${remote_user}@${host}" '
      hostname
      echo "--- LINK ---"
      ip -br link
      echo "--- ADDR ---"
      ip -br addr
      echo "--- BRIDGES ---"
      bridge link 2>/dev/null | sed -n "1,120p" || true
    ' || echo "SSH_FAIL ${host}"
  echo
done

echo "=== KUBERNETES NODES ==="
if kubectl config current-context >/dev/null 2>&1; then
  kubectl get nodes -o wide
  echo
  kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.routing-mode}{"\n"}{.data.tunnel-protocol}{"\n"}{.data.auto-direct-node-routes}{"\n"}'
else
  sudo kubectl get nodes -o wide
  echo
  sudo kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.routing-mode}{"\n"}{.data.tunnel-protocol}{"\n"}{.data.auto-direct-node-routes}{"\n"}'
fi

