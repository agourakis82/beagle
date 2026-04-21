#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/multi-user-gpu-workspace-tenancy}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18490}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
WORKSPACE_ID="${WORKSPACE_ID:-beagle-cluster-pilot}"
TEMPLATE_BASE_OUT="${TEMPLATE_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/template-backed-prebuilt-workspace}"
GPU_BASE_OUT="${GPU_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/advanced-operator-gpu-workflow-smoke}"

WORKSPACE_TENANCY_SOURCE_FILE="${WORKSPACE_TENANCY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_tenancy.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B251_VM_AGNOSTIC_MULTI_USER_GPU_WORKSPACE_AND_COMPUTE_TENANCY.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B251_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B251_KNOWN_LIMITS.md}"
WORKSPACE_SCHEMA_FILE="${WORKSPACE_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-tenancy-schema.yaml}"
COMPUTE_SCHEMA_FILE="${COMPUTE_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/compute-tenancy-schema.yaml}"
PARTNER_SCHEMA_FILE="${PARTNER_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/partner-access-schema.yaml}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require base64
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
  local port="$1"
  local log_file="$2"
  : > "${log_file}"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${port}:8080" >"${log_file}" 2>&1 &
  PF_PID=$!
  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${log_file}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${log_file}" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${log_file}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

wait_for_health() {
  local port="$1"
  local target="$2"
  local ready=0
  for _ in $(seq 1 30); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != "1" ]]; then
    echo "[FAIL] Beagle health endpoint did not become ready on port ${port}" >&2
    exit 1
  fi
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
  stop_port_forward
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"

WORKSPACE_TENANCY_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
WORKSPACE_SCHEMA_PRESENT=0
COMPUTE_SCHEMA_PRESENT=0
PARTNER_SCHEMA_PRESENT=0
TEMPLATE_BASE_PRESENT=0
GPU_BASE_PRESENT=0

if rg -q "workspace-tenancy|compute-tenancy|partner-access" "${WORKSPACE_TENANCY_SOURCE_FILE}"; then
  WORKSPACE_TENANCY_SOURCE_PRESENT=1
fi
if rg -q "pub mod workspace_tenancy|WorkspaceTenancyContract|ComputeTenancyContract|PartnerAccessContract" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/workspace-tenancy|/compute-tenancy|/partner-access|build_multi_user_gpu_workspace_tenancy_bundle" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${WORKSPACE_SCHEMA_FILE}" ]] && WORKSPACE_SCHEMA_PRESENT=1
[[ -f "${COMPUTE_SCHEMA_FILE}" ]] && COMPUTE_SCHEMA_PRESENT=1
[[ -f "${PARTNER_SCHEMA_FILE}" ]] && PARTNER_SCHEMA_PRESENT=1
[[ -f "${TEMPLATE_BASE_OUT}/smoke.json" ]] && TEMPLATE_BASE_PRESENT=1
[[ -f "${GPU_BASE_OUT}/pilot.json" ]] && GPU_BASE_PRESENT=1

jq -nc \
  --argjson workspace_tenancy_source_present "${WORKSPACE_TENANCY_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson workspace_schema_present "${WORKSPACE_SCHEMA_PRESENT}" \
  --argjson compute_schema_present "${COMPUTE_SCHEMA_PRESENT}" \
  --argjson partner_schema_present "${PARTNER_SCHEMA_PRESENT}" \
  --argjson template_base_present "${TEMPLATE_BASE_PRESENT}" \
  --argjson gpu_base_present "${GPU_BASE_PRESENT}" \
  '{
    workspace_tenancy_source_present: $workspace_tenancy_source_present,
    lib_source_present: $lib_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    workspace_schema_present: $workspace_schema_present,
    compute_schema_present: $compute_schema_present,
    partner_schema_present: $partner_schema_present,
    template_base_present: $template_base_present,
    gpu_base_present: $gpu_base_present
  }' > "${OUT}/source-summary.json"

LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-tenancy" \
  > "${OUT}/workspace-tenancy.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/compute-tenancy" \
  > "${OUT}/compute-tenancy.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/partner-access" \
  > "${OUT}/partner-access.json"

jq '.vscode_cursor_access' "${OUT}/workspace-tenancy.json" > "${OUT}/vscode-cursor-access.json"
jq '.repo_hydration' "${OUT}/workspace-tenancy.json" > "${OUT}/repo-hydration.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-after-restart.json"

jq -n \
  --slurpfile workspace "${OUT}/workspace-tenancy.json" \
  --slurpfile compute "${OUT}/compute-tenancy.json" \
  --slurpfile partner "${OUT}/partner-access.json" \
  --slurpfile bootstrap_before "${OUT}/bootstrap-before.json" \
  --slurpfile bootstrap_after "${OUT}/bootstrap-after-restart.json" \
  '{
    status: "ok",
    phase: "B25.1",
    workstream_id: $workspace[0].workstream_id,
    workspace_id: $workspace[0].workspace_id,
    session_id: $workspace[0].session_id,
    same_beagle_owned_identity: (
      $workspace[0].same_beagle_owned_identity and
      $compute[0].same_beagle_owned_identity and
      $partner[0].same_beagle_owned_identity
    ),
    shared_workspace_recommended: $workspace[0].shared_workspace_recommended,
    external_workspace_compatible: $workspace[0].external_workspace_compatible,
    prebuilt_prehydrated_recommended: $workspace[0].prebuilt_prehydrated_recommended,
    canonical_workspace_combination: $workspace[0].canonical_workspace_combination,
    stable_workspace_alias: $workspace[0].stable_workspace_alias,
    vscode_ready: (($workspace[0].vscode_cursor_access.clients | map(select(.client_id == "vscode-desktop" and .access_state == "ready")) | length) == 1),
    cursor_ready: (($workspace[0].vscode_cursor_access.clients | map(select(.client_id == "cursor" and .access_state == "ready")) | length) == 1),
    warm_start_strategy: $workspace[0].repo_hydration.warm_start_strategy,
    startup_mode: $workspace[0].repo_hydration.startup_mode,
    advanced_profile_id: $compute[0].advanced_profile_id,
    live_gpu_access_mode: $compute[0].live_gpu_access_mode,
    shared_gpu_access_state: $compute[0].shared_gpu_access_state,
    partner_access_state: $partner[0].partner_access_state,
    partner_allowed_profile_ids: (
      $partner[0].roles
      | map(select(.role_id == "partner-dev"))[0].allowed_profile_ids
    ),
    bootstrap_recovered_before: $bootstrap_before[0].recovered_session,
    restart_recovered_session: $bootstrap_after[0].recovered_session,
    note: "B25.1 keeps the same Beagle-owned workspace identity while freezing workspace, compute, and partner tenancy into bounded explicit contracts."
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] multi-user GPU workspace tenancy smoke artifacts written to ${OUT}"
