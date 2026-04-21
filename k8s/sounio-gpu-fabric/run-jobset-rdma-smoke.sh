#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--network <nad-name>] [--jobset-name <name>] [--manifest <path>] [--ifname <iface>] [--transport <socket|ib>]" >&2
}

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf config current-context >/dev/null 2>&1; then
  k() { sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${root}/jobset-rdma-gpu-smoke.v2.yaml"
jobset_name="sounio-rdma-ddp-smoke"
namespace="beagle"
network_name="gpu-fabric-10-200-pilot"
socket_ifname="net1"
transport="socket"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network)
      network_name="${2:?missing value for --network}"
      shift 2
      ;;
    --jobset-name)
      jobset_name="${2:?missing value for --jobset-name}"
      shift 2
      ;;
    --manifest)
      manifest="${2:?missing value for --manifest}"
      shift 2
      ;;
    --ifname)
      socket_ifname="${2:?missing value for --ifname}"
      shift 2
      ;;
    --transport)
      transport="${2:?missing value for --transport}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

case "${transport}" in
  socket|ib)
    ;;
  *)
    usage
    echo "invalid --transport: ${transport}" >&2
    exit 1
    ;;
esac

if [[ -z "${socket_ifname}" ]]; then
  echo "--ifname must not be empty" >&2
  exit 1
fi

if [[ "${transport}" == "socket" ]]; then
  nccl_ib_disable="1"
else
  nccl_ib_disable="0"
fi

underlay_preflight="/home/devsounio/beagle/k8s/sounio-networking/preflight-k8s-underlay.sh"
if [[ -x "${underlay_preflight}" ]]; then
  "${underlay_preflight}"
fi

echo
echo "== jobset / multus / rdma preflight =="
k get crd jobsets.jobset.x-k8s.io >/dev/null
k -n "${namespace}" get network-attachment-definition "${network_name}" >/dev/null
k -n kube-system get ds kube-multus-ds >/dev/null
k -n kube-system get ds whereabouts >/dev/null
k -n kube-system get ds rdma-shared-dp-ds >/dev/null
k -n kube-system get ds nvidia-device-plugin-daemonset >/dev/null

gpu_nodes_json="$(k get nodes -o json)"
ready_nodes="$(jq '[.items[]
  | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch")
  | select(any(.status.conditions[]; .type=="Ready" and .status=="True"))
  | select((.status.allocatable["nvidia.com/gpu"] // "0") != "0")
  | select((.status.allocatable["rdma/sounio_gpu_fabric"] // "0") != "0")
] | length' <<<"${gpu_nodes_json}")"

jq -r '.items[]
  | select(.metadata.labels["sounio.dev/pool"]=="gpu-batch")
  | [
      .metadata.name,
      (.metadata.labels["sounio.dev/accelerator"] // "-"),
      (.status.allocatable["nvidia.com/gpu"] // "0"),
      (.status.allocatable["rdma/sounio_gpu_fabric"] // "0")
    ]
  | @tsv' <<<"${gpu_nodes_json}"

if [[ "${ready_nodes}" -lt 2 ]]; then
  echo "FAIL: need at least 2 Ready gpu-batch nodes with both GPU and rdma/sounio_gpu_fabric allocatable" >&2
  exit 1
fi

echo
echo "== applying ${jobset_name} =="
k -n "${namespace}" delete jobset "${jobset_name}" --ignore-not-found --wait=true >/dev/null
for _ in $(seq 1 60); do
  old_pods="$(k -n "${namespace}" get pods -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  old_jobs="$(k -n "${namespace}" get jobs -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${old_pods}" == "0" && "${old_jobs}" == "0" ]]; then
    break
  fi
  sleep 2
done

rendered_manifest="$(mktemp)"
trap '[[ -n "${rendered_manifest}" ]] && rm -f "${rendered_manifest}"' EXIT

rendered_source="$(mktemp)"
trap '[[ -n "${rendered_source}" ]] && rm -f "${rendered_source}"; [[ -n "${rendered_manifest}" ]] && rm -f "${rendered_manifest}"' EXIT

if [[ "${network_name}" != "gpu-fabric-10-200-pilot" || "${jobset_name}" != "sounio-rdma-ddp-smoke" ]]; then
  sed \
    -e "s/name: sounio-rdma-ddp-smoke/name: ${jobset_name}/g" \
    -e "s/sounio-rdma-ddp-smoke/${jobset_name}/g" \
    -e "s/beagle\\/gpu-fabric-10-200-pilot/beagle\\/${network_name}/g" \
    -e "s/__NCCL_SOCKET_IFNAME__/${socket_ifname}/g" \
    -e "s/__NCCL_IB_DISABLE__/${nccl_ib_disable}/g" \
    "${manifest}" >"${rendered_source}"
else
  sed \
    -e "s/__NCCL_SOCKET_IFNAME__/${socket_ifname}/g" \
    -e "s/__NCCL_IB_DISABLE__/${nccl_ib_disable}/g" \
    "${manifest}" >"${rendered_source}"
fi

perl -0pe \
  "s/(name:\\s+NCCL_SOCKET_IFNAME\\n\\s+value:\\s+).*/\${1}\"${socket_ifname}\"/g; \
   s/(name:\\s+GLOO_SOCKET_IFNAME\\n\\s+value:\\s+).*/\${1}\"${socket_ifname}\"/g; \
   s/(name:\\s+NCCL_IB_DISABLE\\n\\s+value:\\s+).*/\${1}\"${nccl_ib_disable}\"/g" \
  "${rendered_source}" >"${rendered_manifest}"

manifest="${rendered_manifest}"

echo "using network=${network_name} transport=${transport} nccl_socket_ifname=${socket_ifname}"

k apply -f "${manifest}"

echo
echo "== waiting for ${jobset_name} =="
wait_result=""
saw_jobs=0
for _ in $(seq 1 180); do
  jobset_json="$(k -n "${namespace}" get jobset "${jobset_name}" -o json 2>/dev/null || true)"
  if [[ -n "${jobset_json}" ]]; then
    terminal_state="$(jq -r '.status.terminalState // empty' <<<"${jobset_json}")"
    if [[ "${terminal_state}" == "Completed" ]]; then
      wait_result="completed"
      break
    fi
    if [[ "${terminal_state}" == "Failed" ]]; then
      echo "FAIL: jobset terminalState=Failed" >&2
      wait_result="failed"
      break
    fi
  fi

  jobs_json="$(k -n "${namespace}" get jobs -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" -o json 2>/dev/null || echo '{"items":[]}' )"
  total="$(jq '.items | length' <<<"${jobs_json}")"
  complete="$(jq '[.items[] | select((.status.succeeded // 0) >= 1)] | length' <<<"${jobs_json}")"
  failed="$(jq '[.items[] | select((.status.failed // 0) >= 1)] | length' <<<"${jobs_json}")"
  if [[ "${total}" -gt 0 ]]; then
    saw_jobs=1
  fi
  if [[ "${failed}" -gt 0 ]]; then
    echo "FAIL: one or more child jobs failed" >&2
    wait_result="failed"
    break
  fi
  if [[ "${total}" -ge 2 && "${complete}" -eq "${total}" ]]; then
    wait_result="completed"
    break
  fi
  sleep 2
done

if [[ -z "${wait_result}" ]]; then
  echo "FAIL: timed out waiting for ${jobset_name} to reach a terminal state" >&2
fi

echo
echo "== placements =="
k -n "${namespace}" get jobs,pods -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" -o wide || true

echo
echo "== logs =="
pod_names="$(k -n "${namespace}" get pods -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
if [[ -z "${pod_names}" && "${saw_jobs}" -eq 1 ]]; then
  echo "(pods already gone; check cluster events if you need deeper forensics)"
fi
for pod in ${pod_names}; do
  echo "--- ${pod} ---"
  k -n "${namespace}" logs "${pod}" || true
done

if [[ "${wait_result}" == "failed" || -z "${wait_result}" ]]; then
  exit 1
fi
