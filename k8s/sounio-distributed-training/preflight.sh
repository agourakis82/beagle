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

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
network_preflight="/home/devsounio/beagle/k8s/sounio-networking/preflight-k8s-underlay.sh"

echo "== distributed-training preflight =="

if [[ -x "${network_preflight}" ]]; then
  "${network_preflight}"
else
  echo "FAIL: missing network preflight at ${network_preflight}" >&2
  exit 1
fi

echo
echo "== jobset CRD/controller =="
k get crd jobsets.jobset.x-k8s.io >/dev/null
k -n jobset-system get deploy jobset-controller-manager >/dev/null
k -n jobset-system get pods -o wide

echo
echo "== gpu-batch nodes =="
gpu_nodes_json="$(k get nodes -o json)"
gpu_ready_count="$(jq '[.items[] | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch") | select(any(.status.conditions[]; .type=="Ready" and .status=="True")) | select((.status.allocatable["nvidia.com/gpu"] // "0") != "0")] | length' <<<"${gpu_nodes_json}")"
jq -r '.items[]
  | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch")
  | [.metadata.name, (.metadata.labels["sounio.dev/accelerator"] // "-"), (.status.allocatable["nvidia.com/gpu"] // "0")]
  | @tsv' <<<"${gpu_nodes_json}"

if [[ "${gpu_ready_count}" -lt 2 ]]; then
  echo "FAIL: need at least 2 Ready gpu-batch nodes for meaningful distributed training" >&2
  exit 1
fi

echo
echo "OK: cluster is ready for phase-1 distributed training"

