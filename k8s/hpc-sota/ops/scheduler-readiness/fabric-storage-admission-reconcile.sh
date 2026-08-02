#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
OPS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CHECK_NAME="${CHECK_NAME:-fabric-storage-readiness}"
CONTROLLER_NAME="${CONTROLLER_NAME:-sounio.dev/fabric-storage-readiness}"
ORANGEFS_MOUNT="${ORANGEFS_MOUNT:-/var/lib/orangefs-lab/client-runtime/mnt}"
GPU_FABRIC_GATE="${GPU_FABRIC_GATE:-${OPS_DIR}/supercomputer-readiness/gpu-fabric-gate.sh}"
GPU_LEASE="${GPU_LEASE:-${OPS_DIR}/gpu-lease}"
DRY_RUN=0

usage() {
  cat <<'EOF'
usage: fabric-storage-admission-reconcile.sh [--dry-run]

Reconcile Kueue Workload status for AdmissionCheck/fabric-storage-readiness.

This is intentionally conservative:
- it only touches Workloads that already list fabric-storage-readiness in
  status.admissionChecks
- it marks the check Ready only when GPU fabric, OrangeFS, and GPU lease policy
  are all healthy
- if GPUs are owned by Slurm/Kubernetes/host processes, it leaves the check in
  Retry so Kueue does not admit new GPU work over an active owner
EOF
}

die() {
  echo "fabric-storage-admission-reconcile: $*" >&2
  exit 1
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require jq
require date

reason="Ready"
message="fabric, OrangeFS, and GPU lease policy are ready"
state="Ready"

if [[ ! -x "${GPU_FABRIC_GATE}" ]]; then
  state="Retry"
  reason="MissingGpuFabricGate"
  message="GPU fabric gate is not executable: ${GPU_FABRIC_GATE}"
elif ! "${GPU_FABRIC_GATE}" phase3-preflight >/dev/null 2>&1; then
  state="Retry"
  reason="GpuFabricPreflightFailed"
  message="GPU fabric 10.210 Kubernetes-side preflight failed"
elif ! "${GPU_FABRIC_GATE}" phase3-external-preflight >/dev/null 2>&1; then
  state="Retry"
  reason="GpuFabricExternalPreflightFailed"
  message="GPU fabric 10.210 external host-to-host preflight failed"
elif ! findmnt -T "${ORANGEFS_MOUNT}" -n -o FSTYPE 2>/dev/null | grep -qx 'pvfs2'; then
  state="Retry"
  reason="OrangeFSMountMissing"
  message="OrangeFS mount is not active at ${ORANGEFS_MOUNT}"
elif [[ ! -x "${GPU_LEASE}" ]]; then
  state="Retry"
  reason="MissingGpuLease"
  message="gpu-lease helper is not executable: ${GPU_LEASE}"
else
  lease_json="$("${GPU_LEASE}" --json status 2>/dev/null || true)"
  if [[ -z "${lease_json}" ]]; then
    state="Retry"
    reason="GpuLeaseUnavailable"
    message="gpu-lease status could not be read"
  elif jq -e '
      any(.leases[]?;
        ((.observed_owner // "") | IN("slurm-job", "kubernetes-pod", "host-process")) or
        ((.slurm_jobs // []) | length > 0) or
        ((.kubernetes_gpu_pods // []) | length > 0) or
        ((.host_gpu_processes // []) | length > 0)
      )
    ' >/dev/null <<<"${lease_json}"; then
    state="Retry"
    reason="GpuLeaseBusy"
    message="GPU lease reports active Slurm/Kubernetes/host GPU ownership"
  fi
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
workloads_json="$(kctl get workloads.kueue.x-k8s.io -A -o json)"
targets="$(
  jq -r --arg check "${CHECK_NAME}" '
    .items[]
    | select(any(.status.admissionChecks[]?; .name == $check and (.state == "Pending" or .state == "Retry")))
    | [.metadata.namespace, .metadata.name] | @tsv
  ' <<<"${workloads_json}"
)"

echo "AdmissionCheck/${CHECK_NAME}: state=${state} reason=${reason}"
echo "message=${message}"

if [[ -z "${targets}" ]]; then
  echo "No pending Workloads require ${CHECK_NAME}."
  exit 0
fi

while IFS=$'\t' read -r namespace name; do
  [[ -n "${namespace}" && -n "${name}" ]] || continue

  workload_json="$(kctl -n "${namespace}" get workloads.kueue.x-k8s.io "${name}" -o json)"
  status_json="$(
    jq \
      --arg check "${CHECK_NAME}" \
      --arg state "${state}" \
      --arg message "${message}" \
      --arg timestamp "${timestamp}" '
      .status.admissionChecks =
        ((.status.admissionChecks // []) | map(
          if .name == $check then
            .state = $state
            | .message = $message
            | .lastTransitionTime = $timestamp
            | if $state == "Retry" then .requeueAfterSeconds = 60 else del(.requeueAfterSeconds) end
          else
            .
          end
        ))
      | {status: .status}
    ' <<<"${workload_json}"
  )"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[dry-run] would patch ${namespace}/${name} to ${state}"
  else
    printf '%s\n' "${status_json}" |
      kctl -n "${namespace}" patch workloads.kueue.x-k8s.io "${name}" \
        --subresource=status \
        --type merge \
        --patch-file -
  fi
done <<<"${targets}"
