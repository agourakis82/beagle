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

echo "== unsupported operator staging preflight =="
echo

version_json="$(k version -o json)"
server_minor="$(jq -r '.serverVersion.minor' <<<"${version_json}" | tr -d '+')"
server_git="$(jq -r '.serverVersion.gitVersion' <<<"${version_json}")"

echo "== kubernetes =="
echo "server_version=${server_git:-unknown}"
if [[ "${server_minor:-}" == "35" ]]; then
  echo "vendor_k8s_window=SUPPORTED_BY_CURRENT_NVIDIA_DOCS"
else
  echo "vendor_k8s_window=OUTSIDE_EXPECTED_1.35_FOCUS"
fi
echo

echo "== node os / kernel reality =="
nodes_json="$(k get nodes -o json)"
jq -r '.items[]
  | [
      .metadata.name,
      .status.nodeInfo.osImage,
      .status.nodeInfo.kernelVersion,
      .status.nodeInfo.containerRuntimeVersion
    ]
  | @tsv' <<<"${nodes_json}"

unsupported_os_count="$(jq '[.items[] | select((.status.nodeInfo.osImage // "") | test("Debian"))] | length' <<<"${nodes_json}")"
unsupported_kernel_count="$(jq '[.items[] | select((.status.nodeInfo.kernelVersion // "") | test("-pve$"))] | length' <<<"${nodes_json}")"
echo
if [[ "${unsupported_os_count}" -gt 0 || "${unsupported_kernel_count}" -gt 0 ]]; then
  echo "cluster_support_posture=UNSUPPORTED_IN_THIS_LAB (Debian/PVE not in the operator support matrix)"
else
  echo "cluster_support_posture=closer_to_vendor_matrix"
fi
echo

echo "== existing manual stack that operators would overlap with =="
k -n kube-system get ds kube-multus-ds whereabouts rdma-shared-dp-ds nvidia-device-plugin-daemonset 2>/dev/null || true
echo "---"
k get runtimeclass nvidia 2>/dev/null || true
echo "---"
k -n beagle get network-attachment-definition gpu-fabric-10-200-pilot 2>/dev/null || true
echo

echo "== allocatable on current gpu nodes =="
jq -r '.items[]
  | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch")
  | [
      .metadata.name,
      (.metadata.labels["sounio.dev/accelerator"] // "-"),
      ("gpu=" + (.status.allocatable["nvidia.com/gpu"] // "0")),
      ("rdma=" + (.status.allocatable["rdma/sounio_gpu_fabric"] // "0"))
    ]
  | @tsv' <<<"${nodes_json}"
echo

echo "== operator namespaces =="
k get ns gpu-operator nvidia-network-operator 2>/dev/null || true
echo "---"
k -n gpu-operator get all 2>/dev/null || true
echo "---"
k -n nvidia-network-operator get all 2>/dev/null || true
echo "---"
gpu_operator_objects="$(k -n gpu-operator get all --ignore-not-found --no-headers 2>/dev/null | wc -l | tr -d ' ')"
network_operator_objects="$(k -n nvidia-network-operator get all --ignore-not-found --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${gpu_operator_objects}" != "0" || "${network_operator_objects}" != "0" ]]; then
  echo "staging_cleanliness=DIRTY (operator namespaces already contain objects)"
else
  echo "staging_cleanliness=CLEAN"
fi
echo

echo "== node feature discovery =="
k get ns node-feature-discovery 2>/dev/null || true
echo "---"
k get pods -A 2>/dev/null | egrep 'node-feature-discovery|nfd' || true
echo "---"
jq -r '.items[]
  | [
      .metadata.name,
      ([.metadata.labels | keys[] | select(startswith("feature.node.kubernetes.io"))] | length | tostring)
    ]
  | @tsv' <<<"${nodes_json}"
echo

echo "== tooling =="
command -v helm >/dev/null 2>&1 && echo "helm=present" || echo "helm=missing"
command -v jq >/dev/null 2>&1 && echo "jq=present" || echo "jq=missing"
echo

echo "== summary =="
echo "1. Kubernetes 1.35.x itself is inside current NVIDIA docs."
echo "2. Debian 13 + Proxmox kernels make this cluster unsupported/experimental for operator takeover."
echo "3. The manual stack is already live; first operator attempt must be controller-only."
echo "4. Do not deploy a live NicClusterPolicy on the first pass."
