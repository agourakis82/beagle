#!/usr/bin/env bash
set -euo pipefail

if (($#)); then
  NODES=("$@")
else
  NODES=(t560-proxmox r770-proxmox r740-proxmox 5860-proxmox)
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_TOML="${SOURCE_DIR}/containerd-lab-push-registry-hosts.toml"

if [[ -n "${SSHPASS:-}" ]]; then
  SSH_CMD=(sshpass -e ssh -o StrictHostKeyChecking=no)
  SCP_CMD=(sshpass -e scp -q -o StrictHostKeyChecking=no)
else
  SSH_CMD=(ssh -o StrictHostKeyChecking=no)
  SCP_CMD=(scp -q -o StrictHostKeyChecking=no)
fi

for node in "${NODES[@]}"; do
  echo "[INFO] configuring lab push registry on ${node}"
  "${SCP_CMD[@]}" "${HOSTS_TOML}" "root@${node}:/tmp/lab-push-registry-hosts.toml"
  "${SSH_CMD[@]}" "root@${node}" '
    set -euo pipefail
    mkdir -p /etc/containerd/certs.d/192.168.3.207:5003
    install -m 0644 /tmp/lab-push-registry-hosts.toml /etc/containerd/certs.d/192.168.3.207:5003/hosts.toml
    systemctl restart containerd
    sleep 2
    systemctl is-active containerd >/dev/null
    cat /etc/containerd/certs.d/192.168.3.207:5003/hosts.toml
  '
done
