#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/template-backed-prebuilt-workspace}"
BASE_OUT="${BASE_OUT:-${OUT}/launch-resume-plane}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18301}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
BASE_SMOKE="${BASE_SMOKE:-${ROOT}/scripts/infrastructure/darwin-hpc/run_managed_workspace_launch_resume_smoke.sh}"
TEMPLATE_SOURCE_FILE="${TEMPLATE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_template.rs}"
WORKSPACE_HABITAT_SOURCE_FILE="${WORKSPACE_HABITAT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_habitat.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
K8S_CONFIGMAP_FILE="${K8S_CONFIGMAP_FILE:-${ROOT}/k8s/beagle-workspace/configmap.yaml}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-template-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B206_TEMPLATE_BACKED_PREBUILT_WORKSPACE_EXTERNAL_REGISTRATION.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B206_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B206_KNOWN_LIMITS.md}"
WARM_SENTINEL_FILE="${WARM_SENTINEL_FILE:-/workspace/beagle/.beagle/context/template-backed-warm-sentinel.txt}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require base64
require cp
require curl
require jq
require rg
require ss
require sudo

resolve_kubectl() {
  if [[ -n "${KUBECTL}" ]]; then
    printf '%s\n' "${KUBECTL}"
    return 0
  fi

  if [[ -r /etc/kubernetes/admin.conf ]]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    printf '%s\n' kubectl
    return 0
  fi

  if [[ -f /etc/kubernetes/admin.conf ]]; then
    printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
    return 0
  fi

  printf '%s\n' kubectl
}

resolve_operator_api_token() {
  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token in secret ${SECRET_NAME}" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

choose_local_port() {
  local port="$1"
  local tries=0

  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done

  echo "[FAIL] unable to find a free local port starting at $1" >&2
  exit 1
}

start_port_forward() {
  local service_name="$1"
  local local_port="$2"
  local remote_port="$3"
  local pf_log="$4"
  local pid_var="$5"

  : > "${pf_log}"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${service_name}" "${local_port}:${remote_port}" >"${pf_log}" 2>&1 &
  local pf_pid=$!

  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
      printf -v "${pid_var}" '%s' "${pf_pid}"
      return 0
    fi
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${local_port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${local_port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

stop_port_forward() {
  local pid_var="$1"
  local pid="${!pid_var:-}"
  if [[ -n "${pid}" ]]; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    printf -v "${pid_var}" '%s' ""
  fi
}

exec_workspace_file() {
  local remote_path="$1"
  local target="$2"
  ${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- sh -lc "cat '${remote_path}'" > "${target}"
}

rollout_deployment() {
  local deployment="$1"
  local restart_log="$2"
  local rollout_log="$3"
  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${deployment}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${deployment}" --timeout=900s > "${rollout_log}"
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -l app.kubernetes.io/part-of=beagle -o wide || true
    echo
    echo "## nodes"
    ${KUBECTL} get nodes -o wide || true
    echo
    if command -v scontrol >/dev/null 2>&1; then
      echo "## scontrol-ping"
      scontrol ping || true
      echo
    fi
    if command -v sinfo >/dev/null 2>&1; then
      echo "## sinfo"
      sinfo -N -l || true
      echo
    fi
  } > "${OUT}/final-cluster-health.txt"
}

cleanup() {
  stop_port_forward BEAGLE_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"

TEMPLATE_SOURCE_PRESENT=0
WORKSPACE_HABITAT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
K8S_TEMPLATE_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "template-backed-prebuilt-workspace|workspace-template" "${TEMPLATE_SOURCE_FILE}"; then
  TEMPLATE_SOURCE_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_TEMPLATE_PATH|BEAGLE_WORKSPACE_TEMPLATE_FILE|BEAGLE_EXTERNAL_WORKSPACE_REGISTRATION_FILE|BEAGLE_WORKSPACE_HYDRATION_FILE" "${WORKSPACE_HABITAT_SOURCE_FILE}"; then
  WORKSPACE_HABITAT_SOURCE_PRESENT=1
fi
if rg -q "/workspace-template|build_workstream_workspace_template" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_TEMPLATE_FILE|BEAGLE_EXTERNAL_WORKSPACE_REGISTRATION_FILE|BEAGLE_WORKSPACE_HYDRATION_FILE|BEAGLE_WORKSPACE_REPRODUCIBILITY_MODE" "${K8S_CONFIGMAP_FILE}"; then
  K8S_TEMPLATE_PRESENT=1
fi
if [[ -f "${CONTRACT_FILE}" ]]; then
  CONTRACT_PRESENT=1
fi
if [[ -f "${DOC_FILE}" ]]; then
  DOC_PRESENT=1
fi
if [[ -f "${GO_NO_GO_FILE}" ]]; then
  GO_NO_GO_PRESENT=1
fi
if [[ -f "${KNOWN_LIMITS_FILE}" ]]; then
  KNOWN_LIMITS_PRESENT=1
fi

jq -nc \
  --argjson template_source_present "${TEMPLATE_SOURCE_PRESENT}" \
  --argjson workspace_habitat_source_present "${WORKSPACE_HABITAT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson k8s_template_present "${K8S_TEMPLATE_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    template_source_present: $template_source_present,
    workspace_habitat_source_present: $workspace_habitat_source_present,
    http_source_present: $http_source_present,
    k8s_template_present: $k8s_template_present,
    contract_present: $contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

ROOT="${ROOT}" KUBECTL="${KUBECTL}" OUT="${BASE_OUT}" bash "${BASE_SMOKE}"

cp "${BASE_OUT}/workspace-context.json" "${OUT}/workspace-context.json"
cp "${BASE_OUT}/workspace-context-after-restart.json" "${OUT}/workspace-context-after-restart.json"
cp "${BASE_OUT}/workspace-runtime-summary.json" "${OUT}/workspace-runtime-summary.json"
cp "${BASE_OUT}/workspace-health.txt" "${OUT}/workspace-health.txt"
cp "${BASE_OUT}/tool-cursor.json" "${OUT}/tool-cursor.json"

WORKSPACE_ID="$(jq -r '.launch.workspace_id' "${BASE_OUT}/workspace-launch-resume.json")"
SESSION_ID="$(jq -r '.launch.session_id' "${BASE_OUT}/workspace-launch-resume.json")"
printf -v WARM_SENTINEL_TEXT $'%s\t%s\t%s\ttemplate-backed-warm' \
  "${EXPECTED_WORKSTREAM}" \
  "${WORKSPACE_ID}" \
  "${SESSION_ID}"

BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-template" \
  > "${OUT}/workspace-template.json"
stop_port_forward BEAGLE_PF_PID

TEMPLATE_FILE="$(jq -r '.template.metadata.template_file' "${OUT}/workspace-template.json")"
REGISTRATION_FILE="$(jq -r '.template.metadata.registration_file' "${OUT}/workspace-template.json")"
HYDRATION_FILE="$(jq -r '.template.metadata.hydration_file' "${OUT}/workspace-template.json")"

exec_workspace_file "${TEMPLATE_FILE}" "${OUT}/workspace-template-file.json"
exec_workspace_file "${REGISTRATION_FILE}" "${OUT}/external-workspace-registration.json"
exec_workspace_file "${HYDRATION_FILE}" "${OUT}/workspace-hydration.json"

${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- \
  sh -lc "printf '%s\n' '${WARM_SENTINEL_TEXT}' > '${WARM_SENTINEL_FILE}'"

rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/workspace-template-restart.txt" "${OUT}/workspace-template-rollout.log"

exec_workspace_file "${TEMPLATE_FILE}" "${OUT}/workspace-template-file-after-restart.json"
exec_workspace_file "${REGISTRATION_FILE}" "${OUT}/external-workspace-registration-after-restart.json"
exec_workspace_file "${HYDRATION_FILE}" "${OUT}/workspace-hydration-after-restart.json"
exec_workspace_file "${WARM_SENTINEL_FILE}" "${OUT}/warm-sentinel-after-restart.txt"

capture_cluster_health

TEMPLATE_ID="$(jq -r '.template.metadata.template_id' "${OUT}/workspace-template.json")"
TEMPLATE_VERSION="$(jq -r '.template.metadata.template_version' "${OUT}/workspace-template.json")"
REGISTRATION_STATE="$(jq -r '.template.external_registration.registration_state' "${OUT}/workspace-template.json")"
HYDRATION_MODE="$(jq -r '.startup_mode' "${OUT}/workspace-hydration-after-restart.json")"
WARM_START_USED="$(jq -r '.warm_start_used' "${OUT}/workspace-hydration-after-restart.json")"
RESTART_RECOVERED_SESSION="$(jq -r '.restart_recovered_session' "${BASE_OUT}/smoke.json")"

jq -nc \
  --arg status "ok" \
  --arg phase "B20.6" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg template_id "${TEMPLATE_ID}" \
  --arg template_version "${TEMPLATE_VERSION}" \
  --arg registration_state "${REGISTRATION_STATE}" \
  --arg hydration_mode "${HYDRATION_MODE}" \
  --arg warm_sentinel_file "${WARM_SENTINEL_FILE}" \
  --arg warm_start_used "${WARM_START_USED}" \
  --arg browser_url "$(jq -r '.template.external_registration.browser_url' "${OUT}/workspace-template.json")" \
  --arg managed_attach_state "$(jq -r '.template.metadata.managed_attach_state' "${OUT}/workspace-template.json")" \
  --arg attach_host_alias "$(jq -r '.template.metadata.stable_attach_alias' "${OUT}/workspace-template.json")" \
  --argjson restart_recovered_session "${RESTART_RECOVERED_SESSION}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    template_id: $template_id,
    template_version: $template_version,
    registration_state: $registration_state,
    hydration_mode: $hydration_mode,
    warm_sentinel_file: $warm_sentinel_file,
    warm_start_used: ($warm_start_used == "true"),
    browser_url: $browser_url,
    managed_attach_state: $managed_attach_state,
    attach_host_alias: $attach_host_alias,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

echo "[OK] template-backed prebuilt workspace smoke completed"
