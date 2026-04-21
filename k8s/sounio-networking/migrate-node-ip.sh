#!/usr/bin/env bash
set -euo pipefail

declare -A NODE_IPS=(
  [t560-proxmox]=10.100.100.2
  [r770-proxmox]=10.100.100.1
  [5860-proxmox]=10.100.100.3
  [r740-proxmox]=10.100.100.4
)

hosts=("$@")
if [[ ${#hosts[@]} -eq 0 ]]; then
  hosts=(r770-proxmox r740-proxmox 5860-proxmox t560-proxmox)
fi

if [[ -z "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  echo "Set PROXMOX_ROOT_PASSWORD before running this script." >&2
  exit 1
fi

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

export SSHPASS="${PROXMOX_ROOT_PASSWORD}"

for host in "${hosts[@]}"; do
  target_ip="${NODE_IPS[$host]:-}"
  if [[ -z "${target_ip}" ]]; then
    echo "unknown host: ${host}" >&2
    exit 1
  fi

  echo "=== ${host} -> ${target_ip} ==="
  sshpass -e ssh \
    -o StrictHostKeyChecking=no \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    root@"${host}" "
      set -euo pipefail
      mkdir -p /root/kubelet-nodeip-backups
      ts=\$(date +%Y%m%d%H%M%S)
      cp -a /var/lib/kubelet/kubeadm-flags.env /root/kubelet-nodeip-backups/kubeadm-flags.env.\$ts 2>/dev/null || true
      cp -a /etc/default/kubelet /root/kubelet-nodeip-backups/default-kubelet.\$ts 2>/dev/null || true
      cat >/etc/default/kubelet <<'EOF'
KUBELET_EXTRA_ARGS=--node-ip=${target_ip}
EOF
      systemctl daemon-reload
      systemctl restart kubelet
      systemctl is-active kubelet
    "

  echo "waiting for ${host} to report InternalIP=${target_ip}"
  deadline=$((SECONDS + 180))
  while true; do
    current_ip="$(k get node "${host}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
    ready_status="$(k get node "${host}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
    if [[ "${current_ip}" == "${target_ip}" && "${ready_status}" == "True" ]]; then
      echo "OK ${host} now advertises ${current_ip}"
      break
    fi
    if (( SECONDS > deadline )); then
      echo "timeout waiting for ${host}; current_ip=${current_ip:-<none>} ready=${ready_status:-<none>}" >&2
      exit 1
    fi
    sleep 3
  done
  echo
done

echo "=== final node addresses ==="
k get nodes -o wide
