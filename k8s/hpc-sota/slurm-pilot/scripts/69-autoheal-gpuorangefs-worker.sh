#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/lib-kubeconfig.sh
source "${SCRIPT_DIR}/lib-kubeconfig.sh"

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
NS="${NS:-slurm-pilot}"
NODE="${NODE:-${1:-}}"
SLURM_NODE_NAME="${SLURM_NODE_NAME:-gpuorangefs-${NODE}}"
FORCE_REPAIR="${FORCE_REPAIR:-0}"

usage() {
  cat <<'EOF'
Usage:
  69-autoheal-gpuorangefs-worker.sh <k8s-node>

Examples:
  69-autoheal-gpuorangefs-worker.sh r740-proxmox
  FORCE_REPAIR=1 69-autoheal-gpuorangefs-worker.sh r740-proxmox

Behavior:
  - checks whether the node is admitted to the gpuorangefs pool
  - inspects worker pod readiness and Slurm node state
  - if healthy, exits 0 without mutation
  - if unhealthy and idle, runs the canonical repair action
  - if unhealthy but the Slurm node still has active jobs, exits non-zero
    unless FORCE_REPAIR=1 is set
EOF
}

if [[ -z "${NODE}" ]]; then
  usage >&2
  exit 1
fi

current_label() {
  ${KUBECTL_BIN} get node "${NODE}" -o jsonpath='{.metadata.labels.sounio\.dev/slurm-worker-gpuorangefs}' 2>/dev/null || true
}

resolve_login_pod() {
  ${KUBECTL_BIN} -n "${NS}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | awk '/^slurm-pilot-login-/{print; exit}'
}

worker_pod_name() {
  ${KUBECTL_BIN} -n "${NS}" get pods \
    -l app.kubernetes.io/instance=slurm-pilot-worker-gpuorangefs,app.kubernetes.io/name=slurmd \
    --field-selector "spec.nodeName=${NODE}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

worker_pod_ready() {
  local name
  local ready_statuses
  name="$(worker_pod_name)"
  [[ -n "${name}" ]] || return 1
  [[ "$(${KUBECTL_BIN} -n "${NS}" get pod "${name}" -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Running" ]] || return 1
  ready_statuses="$(${KUBECTL_BIN} -n "${NS}" get pod "${name}" -o jsonpath='{range .status.containerStatuses[*]}{.ready}{"\n"}{end}' 2>/dev/null || true)"
  [[ -n "${ready_statuses}" ]] || return 1
  if grep -qx 'false' <<<"${ready_statuses}"; then
    return 1
  fi
}

LOGIN_POD="$(resolve_login_pod)"
if [[ -z "${LOGIN_POD}" ]]; then
  echo "[gpuorangefs-autoheal] FAIL: could not resolve login pod in ${NS}" >&2
  exit 1
fi

if [[ "$(current_label)" != "true" ]]; then
  echo "[gpuorangefs-autoheal] ${NODE}: quarantined; nothing to heal"
  exit 0
fi

NODE_STATE="$(${KUBECTL_BIN} -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "scontrol show node '${SLURM_NODE_NAME}' | tr '\n' ' '" 2>/dev/null || true)"
if [[ -z "${NODE_STATE}" ]]; then
  echo "[gpuorangefs-autoheal] ${NODE}: Slurm node ${SLURM_NODE_NAME} not registered"
  NODE_HEALTHY=0
else
  NODE_HEALTHY=1
  if grep -Eq 'State=[^ ]*NOT_RESPONDING' <<<"${NODE_STATE}"; then
    NODE_HEALTHY=0
  fi
fi

POD_HEALTHY=1
if ! worker_pod_ready; then
  POD_HEALTHY=0
fi

if [[ "${NODE_HEALTHY}" -eq 1 && "${POD_HEALTHY}" -eq 1 ]]; then
  echo "[gpuorangefs-autoheal] ${NODE}: healthy"
  exit 0
fi

ACTIVE_JOBS="$(${KUBECTL_BIN} -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "squeue -h -w '${SLURM_NODE_NAME}' -t R,CG -o '%i' | xargs" 2>/dev/null || true)"
if [[ -n "${ACTIVE_JOBS}" && "${FORCE_REPAIR}" != "1" ]]; then
  echo "[gpuorangefs-autoheal] ${NODE}: unhealthy but active jobs still present on ${SLURM_NODE_NAME}: ${ACTIVE_JOBS}" >&2
  echo "[gpuorangefs-autoheal] ${NODE}: refusing repair without FORCE_REPAIR=1" >&2
  exit 2
fi

echo "[gpuorangefs-autoheal] ${NODE}: unhealthy; invoking canonical repair"
exec "${SCRIPT_DIR}/68-manage-gpuorangefs-worker.sh" "${NODE}" repair
