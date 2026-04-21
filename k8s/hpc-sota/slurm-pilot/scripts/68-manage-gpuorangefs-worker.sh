#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
NODE="${NODE:-${1:-}}"
ACTION="${ACTION:-${2:-}}"
NS="${NS:-slurm-pilot}"
WAIT_SEC="${WAIT_SEC:-120}"
GATE_TIMEOUT_SEC="${GATE_TIMEOUT_SEC:-420}"
LOCK_DIR="${LOCK_DIR:-/tmp}"
LOCK_FILE="${LOCK_DIR}/gpuorangefs-${NODE}.lock"
ADMISSION_ANNOTATION="sounio.dev/gpuorangefs-admission-id"
ADMISSION_ANNOTATION_JSONPATH='{.metadata.annotations.sounio\.dev/gpuorangefs-admission-id}'

usage() {
  cat <<'EOF'
Usage:
  68-manage-gpuorangefs-worker.sh <node> <admit|quarantine|repair|status>

Examples:
  68-manage-gpuorangefs-worker.sh r740-proxmox status
  68-manage-gpuorangefs-worker.sh r740-proxmox quarantine
  68-manage-gpuorangefs-worker.sh r770-proxmox admit
  68-manage-gpuorangefs-worker.sh r740-proxmox repair

Behavior:
  - status:
      prints whether the node currently carries the
      sounio.dev/slurm-worker-gpuorangefs=true label
  - quarantine:
      removes the worker admission label and deletes any lingering worker pod
  - admit:
      temporarily labels the node, waits for the worker pod, runs the canonical
      gate, and keeps the label only if the gate passes
  - repair:
      restarts the node-local Cilium pod and the matching worker pod, then
      re-runs the canonical gate. If the gate fails, the node is returned to
      quarantine.
EOF
}

if [[ -z "${NODE}" || -z "${ACTION}" ]]; then
  usage >&2
  exit 1
fi

current_label() {
  ${KUBECTL_BIN} get node "${NODE}" -o jsonpath='{.metadata.labels.sounio\.dev/slurm-worker-gpuorangefs}' 2>/dev/null || true
}

current_admission_id() {
  ${KUBECTL_BIN} get node "${NODE}" -o jsonpath="${ADMISSION_ANNOTATION_JSONPATH}" 2>/dev/null || true
}

set_admission_id() {
  local admission_id="$1"
  ${KUBECTL_BIN} annotate node "${NODE}" "${ADMISSION_ANNOTATION}=${admission_id}" --overwrite >/dev/null
}

clear_admission_id() {
  ${KUBECTL_BIN} annotate node "${NODE}" "${ADMISSION_ANNOTATION}-" >/dev/null 2>&1 || true
}

worker_pod_name() {
  ${KUBECTL_BIN} -n "${NS}" get pods \
    -l app.kubernetes.io/instance=slurm-pilot-worker-gpuorangefs,app.kubernetes.io/name=slurmd \
    --field-selector "spec.nodeName=${NODE}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

delete_worker_pod() {
  local name
  name="$(worker_pod_name)"
  [[ -n "${name}" ]] || return 0
  ${KUBECTL_BIN} -n "${NS}" delete pod "${name}" --wait=false >/dev/null 2>&1 || true
}

cilium_pod_name() {
  ${KUBECTL_BIN} -n kube-system get pods \
    -l k8s-app=cilium \
    --field-selector "spec.nodeName=${NODE}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

restart_cilium_pod() {
  local name
  name="$(cilium_pod_name)"
  [[ -n "${name}" ]] || return 1
  ${KUBECTL_BIN} -n kube-system delete pod "${name}" >/dev/null
}

wait_for_cilium_pod() {
  local i
  local name
  for i in $(seq 1 "${WAIT_SEC}"); do
    name="$(cilium_pod_name)"
    if [[ -n "${name}" ]]; then
      if ${KUBECTL_BIN} -n kube-system wait --for=condition=Ready "pod/${name}" --timeout=1s >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

safe_return_to_quarantine() {
  local admission_id="${1:-}"
  local active_id
  active_id="$(current_admission_id)"
  if [[ -n "${admission_id}" && -n "${active_id}" && "${active_id}" != "${admission_id}" ]]; then
    return 0
  fi
  ${KUBECTL_BIN} label node "${NODE}" sounio.dev/slurm-worker-gpuorangefs- --overwrite >/dev/null 2>&1 || true
  clear_admission_id
  delete_worker_pod
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

wait_for_worker_pod() {
  local i
  for i in $(seq 1 "${WAIT_SEC}"); do
    if worker_pod_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

exec 9>"${LOCK_FILE}"
flock 9

case "${ACTION}" in
status)
  value="$(current_label)"
  if [[ "${value}" == "true" ]]; then
    echo "[gpuorangefs] ${NODE}: admitted id=$(current_admission_id)"
  else
    echo "[gpuorangefs] ${NODE}: quarantined"
  fi
  ;;
quarantine)
  safe_return_to_quarantine ""
  echo "[gpuorangefs] ${NODE}: quarantined"
  ;;
admit)
  admission_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  had_label="$(current_label)"
  set_admission_id "${admission_id}"
  if [[ "${had_label}" != "true" ]]; then
    ${KUBECTL_BIN} label node "${NODE}" sounio.dev/slurm-worker-gpuorangefs=true --overwrite >/dev/null
    if ! wait_for_worker_pod; then
      safe_return_to_quarantine "${admission_id}"
      echo "[gpuorangefs] ${NODE}: failed to bring worker pod up during temporary admission" >&2
      exit 1
    fi
  fi

  if TARGET_NODE="${NODE}" timeout --foreground "${GATE_TIMEOUT_SEC}s" "${SCRIPT_DIR}/66-gpuorangefs-gate.sh"; then
    echo "[gpuorangefs] ${NODE}: admitted id=${admission_id}"
  else
    rc=$?
    safe_return_to_quarantine "${admission_id}"
    if [[ "${rc}" -eq 124 ]]; then
      echo "[gpuorangefs] ${NODE}: gate timed out after ${GATE_TIMEOUT_SEC}s, node returned to quarantine" >&2
    else
      echo "[gpuorangefs] ${NODE}: gate failed, node returned to quarantine" >&2
    fi
    exit 1
  fi
  ;;
repair)
  admission_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  had_label="$(current_label)"
  set_admission_id "${admission_id}"
  if [[ "${had_label}" != "true" ]]; then
    ${KUBECTL_BIN} label node "${NODE}" sounio.dev/slurm-worker-gpuorangefs=true --overwrite >/dev/null
  fi

  if ! restart_cilium_pod; then
    safe_return_to_quarantine "${admission_id}"
    echo "[gpuorangefs] ${NODE}: failed to locate cilium pod for repair" >&2
    exit 1
  fi
  if ! wait_for_cilium_pod; then
    safe_return_to_quarantine "${admission_id}"
    echo "[gpuorangefs] ${NODE}: cilium did not become ready during repair" >&2
    exit 1
  fi

  delete_worker_pod
  if ! wait_for_worker_pod; then
    safe_return_to_quarantine "${admission_id}"
    echo "[gpuorangefs] ${NODE}: worker pod did not recover during repair" >&2
    exit 1
  fi

  if TARGET_NODE="${NODE}" timeout --foreground "${GATE_TIMEOUT_SEC}s" "${SCRIPT_DIR}/66-gpuorangefs-gate.sh"; then
    echo "[gpuorangefs] ${NODE}: repaired id=${admission_id}"
  else
    rc=$?
    safe_return_to_quarantine "${admission_id}"
    if [[ "${rc}" -eq 124 ]]; then
      echo "[gpuorangefs] ${NODE}: repair gate timed out after ${GATE_TIMEOUT_SEC}s, node returned to quarantine" >&2
    else
      echo "[gpuorangefs] ${NODE}: repair gate failed, node returned to quarantine" >&2
    fi
    exit 1
  fi
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
