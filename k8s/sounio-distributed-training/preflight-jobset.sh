#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

"$root/../sounio-networking/preflight-k8s-underlay.sh"

echo
echo "=== JOBSET CRD ==="
k get crd jobsets.jobset.x-k8s.io >/dev/null
echo "OK: jobsets.jobset.x-k8s.io present"

echo
echo "=== JOBSET CONTROLLER ==="
k -n jobset-system get deploy jobset-controller-manager
k -n jobset-system get pods -o wide

echo
echo "=== GPU NODES ==="
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.sounio\.dev/accelerator}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' \
  | awk 'NF && $2 != "" && $3 != ""'

echo
echo "=== READY CHECK ==="
ready_count="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.labels.sounio\.dev/accelerator}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | awk '$1 != "" && $2 != "" && $2 != "<none>" {count++} END{print count+0}')"
if [[ "$ready_count" -lt 2 ]]; then
  echo "FAIL: need at least 2 GPU nodes for a multi-node smoke, found $ready_count" >&2
  exit 1
fi

echo "OK: distributed training preflight passed"
