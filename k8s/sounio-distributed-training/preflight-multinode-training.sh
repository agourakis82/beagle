#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
net_preflight="${root%/sounio-distributed-training}/sounio-networking/preflight-k8s-underlay.sh"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

status=0

echo "=== CLUSTER UNDERLAY ==="
if [[ -x "${net_preflight}" ]]; then
  if ! "${net_preflight}"; then
    status=1
  fi
else
  echo "WARN: networking preflight not found at ${net_preflight}" >&2
fi
echo

echo "=== JOBSET ==="
if ! k get crd jobsets.jobset.x-k8s.io >/dev/null 2>&1; then
  echo "FAIL: JobSet CRD is not installed" >&2
  status=1
else
  echo "OK: JobSet CRD present"
fi

if ! k wait --for=condition=Available -n jobset-system deployment/jobset-controller-manager --timeout=5s >/dev/null 2>&1; then
  echo "FAIL: JobSet controller is not available" >&2
  status=1
else
  echo "OK: JobSet controller available"
fi
echo

echo "=== GPU NODES ==="
gpu_nodes="$(
  k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.sounio\.dev/accelerator}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' \
    | awk -F '\t' 'NF >= 3 && $2 != "" && $3+0 >= 1 {print}'
)"
printf '%s\n' "${gpu_nodes}"

gpu_count="$(printf '%s\n' "${gpu_nodes}" | awk 'NF > 0 {count++} END {print count+0}')"
if (( gpu_count < 2 )); then
  echo "FAIL: need at least 2 schedulable GPU nodes for multi-node DDP smoke" >&2
  status=1
else
  echo "OK: ${gpu_count} GPU nodes available for multi-node DDP smoke"
fi
echo

echo "=== SUMMARY ==="
if (( status == 0 )); then
  echo "OK: cluster is ready for multi-node training smoke tests"
else
  echo "NOT_READY: fix the failed checks above before trusting distributed training" >&2
fi

exit "${status}"
