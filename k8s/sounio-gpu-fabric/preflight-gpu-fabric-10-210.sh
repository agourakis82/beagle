#!/usr/bin/env bash
set -euo pipefail

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf config current-context >/dev/null 2>&1; then
  k() { sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nad_manifest="${root}/networkattachmentdefinition-gpu-fabric-10-210.example.yaml"

echo "== cluster substrate =="
k get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null
k get crd jobsets.jobset.x-k8s.io >/dev/null
k -n kube-system get ds kube-multus-ds >/dev/null
k -n kube-system get ds whereabouts >/dev/null
k -n kube-system get ds rdma-shared-dp-ds >/dev/null
k -n kube-system get ds nvidia-device-plugin-daemonset >/dev/null
echo "ok: multus / whereabouts / rdma shared / nvidia device plugin present"

echo
echo "== gpu fleet =="
gpu_nodes_json="$(k get nodes -o json)"
jq -r '.items[]
  | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch")
  | [
      .metadata.name,
      (.metadata.labels["sounio.dev/accelerator"] // "-"),
      (.status.allocatable["nvidia.com/gpu"] // "0"),
      (.status.allocatable["rdma/sounio_gpu_fabric"] // "0")
    ]
  | @tsv' <<<"${gpu_nodes_json}"

ready_nodes="$(jq '[.items[]
  | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch")
  | select(any(.status.conditions[]; .type=="Ready" and .status=="True"))
  | select((.status.allocatable["nvidia.com/gpu"] // "0") != "0")
  | select((.status.allocatable["rdma/sounio_gpu_fabric"] // "0") != "0")
] | length' <<<"${gpu_nodes_json}")"

if [[ "${ready_nodes}" -lt 2 ]]; then
  echo "FAIL: need at least 2 Ready gpu-batch nodes with both nvidia.com/gpu and rdma/sounio_gpu_fabric allocatable" >&2
  exit 1
fi

echo
echo "== dry-run 10.210 network attachment =="
k apply --dry-run=server -f "${nad_manifest}" >/dev/null
echo "ok: ${nad_manifest} passes server dry-run"

echo
echo "== required out-of-cluster prerequisites =="
cat <<'EOF'
Before promoting 10.210 from plan to live, confirm these outside Kubernetes:
- Arista VLAN/SVI for 10.210.0.0/24 exists
- gateway 10.210.0.254 is reserved and reachable from GPU hosts
- GPU hosts expose the final bridge/master consistently as gpufabric210
- jumbo MTU 9000 is clean end-to-end on the 10.210 path
- if RoCE tuning is desired, contain PFC/ECN to the GPU VLAN only
EOF
