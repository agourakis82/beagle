#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
FABRIC_DIR="${GPU_FABRIC_DIR:-/home/devsounio/beagle/k8s/sounio-gpu-fabric}"
GPU_LEASE="${GPU_LEASE_BIN:-/home/devsounio/beagle/k8s/hpc-sota/ops/gpu-lease}"

usage() {
  cat <<'EOF'
usage: gpu-fabric-gate.sh <command> [args]

Canonical Darwin/Sounio GPU fabric gate.

Commands:
  status
      Read-only summary of GPU/RDMA allocatable resources and fabric objects.

  pilot-preflight
      Run the existing 10.200 pilot-fabric substrate preflight.

  pilot-smoke [--transport socket|ib]
      Run the existing JobSet RDMA/NCCL smoke on the live 10.200 pilot fabric.
      Default transport is the proven socket-over-net1 mode.

  phase3-preflight
      Run the 10.210 dedicated GPU fabric preflight, Multus/Cilium guard, and
      server-side dry-run.

  phase3-external-preflight
      Read-only host-side proof for vmbr210/gpufabric210, MTU 9000, and
      jumbo host-to-host connectivity on 10.210.

  phase3-apply
      Apply the 10.210 NetworkAttachmentDefinition after external fabric work is
      complete.

  phase3-smoke [--transport socket|ib]
      Run the JobSet RDMA/NCCL smoke on the 10.210 dedicated fabric. This
      assumes phase3-apply and external network prerequisites are complete.
      Refuses to run while gpu-lease reports active Slurm/Kubernetes/host GPU
      use unless DARWIN_GPU_FABRIC_ALLOW_BUSY=1 is set.

  phase3-ib-ready
      Read-only readiness check for the next verbs/RoCE attempt. Runs the
      10.210 Kubernetes and host preflights, then checks GPU lease idleness.

Notes:
  - status, pilot-preflight, and phase3-preflight are read-only.
  - phase3-external-preflight is read-only but requires SSH to GPU hosts.
  - phase3-apply mutates the cluster by applying a NetworkAttachmentDefinition.
  - pilot-smoke and phase3-smoke create/delete JobSet smoke workloads.
EOF
}

die() {
  echo "gpu-fabric-gate: $*" >&2
  exit 1
}

require_fabric_dir() {
  [[ -d "${FABRIC_DIR}" ]] || die "fabric directory not found: ${FABRIC_DIR}"
}

kctl() {
  if kubectl config current-context >/dev/null 2>&1; then
    kubectl "$@"
  elif sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf config current-context >/dev/null 2>&1; then
    sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
  else
    die "unable to find a working kubectl context"
  fi
}

status() {
  echo "Darwin/Sounio GPU fabric status"
  echo
  echo "== GPU/RDMA nodes =="
  kctl get nodes \
    -L sounio.dev/accelerator \
    -L sounio.dev/pool \
    -o custom-columns=NAME:.metadata.name,READY:.status.conditions[-1].status,ACCEL:.metadata.labels.sounio\\.dev/accelerator,POOL:.metadata.labels.sounio\\.dev/pool,GPU:.status.allocatable.nvidia\\.com/gpu,RDMA:.status.allocatable.rdma/sounio_gpu_fabric

  echo
  echo "== Network attachments =="
  kctl -n beagle get network-attachment-definitions.k8s.cni.cncf.io 2>/dev/null || true

  echo
  echo "== RDMA substrate pods =="
  kctl get pods -A | awk 'NR == 1 || tolower($0) ~ /rdma|multus|whereabouts|network-operator/'

  echo
  echo "== Gate commands =="
  echo "pilot-preflight: ${SCRIPT_PATH} pilot-preflight"
  echo "pilot-smoke:     ${SCRIPT_PATH} pilot-smoke"
  echo "phase3-preflight:${SCRIPT_PATH} phase3-preflight"
  echo "phase3-apply:    ${SCRIPT_PATH} phase3-apply"
  echo "phase3-smoke:    ${SCRIPT_PATH} phase3-smoke"
  echo "phase3-ib-ready: ${SCRIPT_PATH} phase3-ib-ready"
}

run_smoke() {
  local network="$1"
  local jobset="$2"
  local transport="${3:-socket}"
  local extra_args=()

  case "${transport}" in
    socket)
      ;;
    ib)
      extra_args+=(--transport ib)
      ;;
    *)
      die "unknown transport: ${transport}"
      ;;
  esac

  "${FABRIC_DIR}/run-jobset-rdma-smoke.sh" \
    --network "${network}" \
    --jobset-name "${jobset}" \
    "${extra_args[@]}"
}

require_gpu_fabric_idle() {
  if [[ "${DARWIN_GPU_FABRIC_ALLOW_BUSY:-0}" == "1" ]]; then
    echo "WARN: DARWIN_GPU_FABRIC_ALLOW_BUSY=1; skipping gpu-lease idle guard"
    return 0
  fi

  [[ -x "${GPU_LEASE}" ]] || die "gpu-lease helper not executable: ${GPU_LEASE}"

  local tmp
  tmp="$(mktemp /tmp/gpu-fabric-lease.XXXXXX)"
  if ! "${GPU_LEASE}" --json status >"${tmp}"; then
    rm -f "${tmp}"
    die "unable to read gpu-lease status"
  fi

  if ! python3 - "${tmp}" <<'PY'
import json
import sys

doc = json.load(open(sys.argv[1], encoding="utf-8"))
busy = []
for lease in doc.get("leases", []):
    node = lease.get("node", "<unknown>")
    owner = lease.get("observed_owner", "")
    slurm_jobs = lease.get("slurm_jobs") or []
    k8s_gpu_pods = lease.get("kubernetes_gpu_pods") or []
    host_gpu_processes = lease.get("host_gpu_processes") or []
    if slurm_jobs or k8s_gpu_pods or host_gpu_processes or owner in {"slurm-job", "kubernetes-pod", "host-process"}:
        details = []
        if slurm_jobs:
            details.append("slurm=" + ",".join(job.get("id", "?") for job in slurm_jobs))
        if k8s_gpu_pods:
            details.append("k8s=" + ",".join(pod.get("name", "?") for pod in k8s_gpu_pods))
        if host_gpu_processes:
            details.append("host=" + ",".join(proc.get("pid", "?") for proc in host_gpu_processes))
        busy.append(f"{node} owner={owner} {' '.join(details)}")

if busy:
    print("GPU fabric smoke refused because GPUs are busy:", file=sys.stderr)
    for line in busy:
        print(f"  - {line}", file=sys.stderr)
    print("Set DARWIN_GPU_FABRIC_ALLOW_BUSY=1 only for an intentional override.", file=sys.stderr)
    sys.exit(1)
PY
  then
    rm -f "${tmp}"
    return 1
  fi

  rm -f "${tmp}"
}

ssh_host() {
  local host="$1"
  shift
  timeout 10 ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=3 \
    "root@${host}" "$@"
}

phase3_multus_guard() {
  local failures=0
  local hosts=(r770-proxmox r740-proxmox 5860-proxmox)

  echo "== cilium / multus guard =="
  local exclusive
  exclusive="$(kctl -n kube-system get configmap cilium-config -o jsonpath='{.data.cni-exclusive}' 2>/dev/null || true)"
  if [[ "${exclusive}" == "false" ]]; then
    echo "cilium cni-exclusive=false: PASS"
  else
    echo "cilium cni-exclusive=${exclusive:-<unset>}: FAIL"
    failures=$((failures + 1))
  fi

  for host in "${hosts[@]}"; do
    printf '%s 00-multus.conf: ' "${host}"
    if ssh_host "${host}" "test -f /etc/cni/net.d/00-multus.conf && grep -q 'multus-shim' /etc/cni/net.d/00-multus.conf"; then
      echo "PASS"
    else
      echo "FAIL"
      failures=$((failures + 1))
    fi
  done

  if (( failures > 0 )); then
    echo "Multus secondary networks are not active on every GPU node."
    return 1
  fi
}

phase3_external_preflight() {
  local failures=0
  local warnings=0
  local hosts=(r770-proxmox r740-proxmox 5860-proxmox)
  local expected_ips=(10.210.0.1 10.210.0.4 10.210.0.3)

  echo "== 10.210 host bridge checks =="
  for i in "${!hosts[@]}"; do
    host="${hosts[$i]}"
    expected_ip="${expected_ips[$i]}"
    echo "--- ${host} ---"
    if ! ssh_host "${host}" "set -euo pipefail
      ip -br addr show vmbr210
      ip -d link show vmbr210 | sed -n '1,12p'
      ip -br addr show vmbr210 | grep -q '${expected_ip}/24'
      ip -d link show vmbr210 | grep -q 'mtu 9000'
      ip -d link show vmbr210 | grep -q 'altname gpufabric210'
    "; then
      echo "FAIL: ${host} is missing vmbr210/gpufabric210/MTU/IP requirements" >&2
      failures=$((failures + 1))
    fi
  done

  echo
  echo "== 10.210 jumbo host-to-host checks =="
  for i in "${!hosts[@]}"; do
    src="${hosts[$i]}"
    for j in "${!hosts[@]}"; do
      [[ "${i}" -ne "${j}" ]] || continue
      dst_ip="${expected_ips[$j]}"
      printf '%s -> %s: ' "${src}" "${dst_ip}"
      if ssh_host "${src}" "ping -c 2 -W 1 -M do -s 8972 '${dst_ip}' >/dev/null"; then
        echo "PASS"
      else
        echo "FAIL"
        failures=$((failures + 1))
      fi
    done
  done

  echo
  echo "== 10.210 gateway check =="
  for i in "${!hosts[@]}"; do
    host="${hosts[$i]}"
    printf '%s -> 10.210.0.254: ' "${host}"
    if ssh_host "${host}" "ping -c 2 -W 1 -M do -s 8972 10.210.0.254 >/dev/null"; then
      echo "PASS"
    else
      echo "WARN"
      warnings=$((warnings + 1))
    fi
  done

  if (( failures > 0 )); then
    echo
    echo "10.210 external preflight: FAIL (${failures} failure(s), ${warnings} warning(s))"
    return 1
  fi

  if (( warnings > 0 )); then
    echo
    echo "10.210 external preflight: PASS WITH WARNINGS (${warnings} gateway warning(s))"
    echo "Host-to-host jumbo fabric works; SVI/gateway 10.210.0.254 is not proven."
    return 0
  fi

  echo
  echo "10.210 external preflight: PASS"
}

phase3_ib_ready() {
  local failures=0

  phase3_multus_guard || failures=$((failures + 1))
  "${FABRIC_DIR}/preflight-gpu-fabric-10-210.sh" || failures=$((failures + 1))
  phase3_external_preflight || failures=$((failures + 1))
  require_gpu_fabric_idle || failures=$((failures + 1))

  echo
  if (( failures > 0 )); then
    echo "phase3 IB readiness: NOT READY (${failures} failed gate(s))"
    echo "Next command when ready:"
    echo "  ${SCRIPT_PATH} phase3-smoke --transport ib"
    return 1
  fi

  echo "phase3 IB readiness: READY"
  echo "Next command:"
  echo "  ${SCRIPT_PATH} phase3-smoke --transport ib"
}

command="${1:-}"
if [[ -z "${command}" ]]; then
  usage >&2
  exit 2
fi
shift || true

require_fabric_dir

case "${command}" in
  status)
    status
    ;;
  pilot-preflight)
    "${FABRIC_DIR}/preflight-rdma-secondary-fabric.sh"
    ;;
  pilot-smoke)
    transport="socket"
    if [[ "${1:-}" == "--transport" ]]; then
      transport="${2:-}"
    fi
    require_gpu_fabric_idle
    run_smoke "gpu-fabric-10-200-pilot" "sounio-rdma-ddp-smoke" "${transport}"
    ;;
  phase3-preflight)
    phase3_multus_guard
    "${FABRIC_DIR}/preflight-gpu-fabric-10-210.sh"
    ;;
  phase3-external-preflight)
    phase3_external_preflight
    ;;
  phase3-apply)
    "${FABRIC_DIR}/cutover-gpu-fabric-10-210.sh" --apply
    ;;
  phase3-smoke)
    transport="socket"
    if [[ "${1:-}" == "--transport" ]]; then
      transport="${2:-}"
    fi
    require_gpu_fabric_idle
    run_smoke "gpu-fabric-10-210" "rdma210" "${transport}"
    ;;
  phase3-ib-ready)
    phase3_ib_ready
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    die "unknown command: ${command}"
    ;;
esac
