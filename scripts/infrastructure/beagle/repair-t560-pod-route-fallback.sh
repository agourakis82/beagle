#!/usr/bin/env bash
set -euo pipefail

# Restore worker -> t560 pod routing while the t560 service-fabric bridge has
# no physical uplink. Cilium runs in native-routing mode and otherwise installs
# 10.0.0.0/24 via 10.100.100.2, which is unreachable at L2 in this topology.
#
# Safe default: inspect only. Pass --apply to replace the route on each worker.

mode="${1:---check}"
namespace="kube-system"
cilium_selector="k8s-app=cilium"
t560_pod_cidr="10.0.0.0/24"
t560_management_ip="192.168.3.169"
management_interface="vmbr0"
workers=(r770-proxmox r740-proxmox 5860-proxmox)

usage() {
  cat <<'EOF'
Usage: repair-t560-pod-route-fallback.sh [--check|--apply]

  --check  Show the current route and t560 fabric-neighbor state (default).
  --apply  Route the t560 pod CIDR through its management IP on every worker.

This is a runtime fallback. The canonical fix is restoring a physical uplink
on t560's vmbr100, then returning Cilium to direct service-fabric routing.
EOF
}

case "$mode" in
  --check|--apply) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require kubectl

cilium_pod_for_node() {
  local node="$1"
  kubectl -n "$namespace" get pods \
    -l "$cilium_selector" \
    --field-selector "spec.nodeName=$node" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

check_route() {
  local node="$1"
  local pod="$2"
  echo "[INFO] $node current route"
  kubectl -n "$namespace" exec "$pod" -- ip route get 10.0.0.1
  echo "[INFO] $node neighbor for t560 fabric IP"
  kubectl -n "$namespace" exec "$pod" -- ip neigh show 10.100.100.2 || true
}

for node in "${workers[@]}"; do
  pod="$(cilium_pod_for_node "$node")"
  if [[ -z "$pod" ]]; then
    echo "[FAIL] no Cilium pod found on $node" >&2
    exit 1
  fi

  if [[ "$mode" == "--apply" ]]; then
    echo "[APPLY] $node: $t560_pod_cidr via $t560_management_ip dev $management_interface"
    kubectl -n "$namespace" exec "$pod" -- \
      ip route replace "$t560_pod_cidr" via "$t560_management_ip" dev "$management_interface"
  fi

  check_route "$node" "$pod"
done

if [[ "$mode" == "--check" ]]; then
  echo "[OK] check complete; no routes changed"
else
  echo "[OK] fallback route applied on ${#workers[@]} workers"
fi
