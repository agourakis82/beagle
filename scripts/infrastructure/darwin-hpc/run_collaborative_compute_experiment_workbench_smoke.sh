#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/collaborative-compute-experiment-workbench}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18520}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
WORKSPACE_ID="${WORKSPACE_ID:-beagle-cluster-pilot}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B252_COLLABORATIVE_COMPUTE_AND_EXPERIMENT_WORKBENCH.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B252_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B252_KNOWN_LIMITS.md}"
SESSION_SCHEMA_FILE="${SESSION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/workbench-session-schema.yaml}"
COMPUTE_SCHEMA_FILE="${COMPUTE_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/compute-selection-schema.yaml}"
COLLABORATION_SCHEMA_FILE="${COLLABORATION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/collaboration-access-schema.yaml}"
RUN_SCHEMA_FILE="${RUN_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/workbench-run-schema.yaml}"
COLLABORATIVE_WORKBENCH_SCHEMA_FILE="${COLLABORATIVE_WORKBENCH_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/collaborative-workbench-schema.yaml}"

WORKBENCH_SOURCE_FILE="${WORKBENCH_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/collaborative_workbench.rs}"
WORKSPACE_TENANCY_SOURCE_FILE="${WORKSPACE_TENANCY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_tenancy.rs}"
WORKSPACE_SUBAGENTS_SOURCE_FILE="${WORKSPACE_SUBAGENTS_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagents.rs}"
EXECUTION_STATE_SOURCE_FILE="${EXECUTION_STATE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/execution_state.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"

TENANCY_BASE_OUT="${TENANCY_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/multi-user-gpu-workspace-tenancy}"
EXECUTION_BASE_OUT="${EXECUTION_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/plan-execution-orchestrator}"
ANALYSIS_CANARY_OUT="${ANALYSIS_CANARY_OUT:-${ROOT}/.artifacts/darwin-hpc/analysis-canary-activation}"

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

DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
SESSION_SCHEMA_PRESENT=0
COMPUTE_SCHEMA_PRESENT=0
COLLABORATION_SCHEMA_PRESENT=0
RUN_SCHEMA_PRESENT=0
COLLABORATIVE_WORKBENCH_SCHEMA_PRESENT=0
WORKBENCH_SOURCE_PRESENT=0
WORKSPACE_TENANCY_SOURCE_PRESENT=0
WORKSPACE_SUBAGENTS_SOURCE_PRESENT=0
EXECUTION_STATE_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
PRIOR_B251_ARTIFACTS_PRESENT=0
PRIOR_B242_ARTIFACTS_PRESENT=0
PRIOR_B2413_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${SESSION_SCHEMA_FILE}" ]] && SESSION_SCHEMA_PRESENT=1
[[ -f "${COMPUTE_SCHEMA_FILE}" ]] && COMPUTE_SCHEMA_PRESENT=1
[[ -f "${COLLABORATION_SCHEMA_FILE}" ]] && COLLABORATION_SCHEMA_PRESENT=1
[[ -f "${RUN_SCHEMA_FILE}" ]] && RUN_SCHEMA_PRESENT=1
[[ -f "${COLLABORATIVE_WORKBENCH_SCHEMA_FILE}" ]] && COLLABORATIVE_WORKBENCH_SCHEMA_PRESENT=1
if rg -q "build_collaborative_compute_experiment_workbench|collaborative-compute-experiment-workbench|workbench-session|workbench-run" "${WORKBENCH_SOURCE_FILE}"; then
  WORKBENCH_SOURCE_PRESENT=1
fi
if rg -q "build_multi_user_gpu_workspace_tenancy_bundle|workspace-tenancy|compute-tenancy|partner-access" "${WORKSPACE_TENANCY_SOURCE_FILE}"; then
  WORKSPACE_TENANCY_SOURCE_PRESENT=1
fi
if rg -q "build_workstream_workspace_subagents|WorkspaceSubAgentRole|workspace-subagents" "${WORKSPACE_SUBAGENTS_SOURCE_FILE}"; then
  WORKSPACE_SUBAGENTS_SOURCE_PRESENT=1
fi
if rg -q "PlanExecutionStatusSummary|execution_state_path|execution_result_links_path" "${EXECUTION_STATE_SOURCE_FILE}"; then
  EXECUTION_STATE_SOURCE_PRESENT=1
fi
if rg -q "/collaborative-workbench|/workbench-session|/compute-selection|/collaboration-access|/workbench-run|build_collaborative_compute_experiment_workbench" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${TENANCY_BASE_OUT}/smoke.json" ]] && PRIOR_B251_ARTIFACTS_PRESENT=1
[[ -f "${EXECUTION_BASE_OUT}/smoke.json" ]] && PRIOR_B242_ARTIFACTS_PRESENT=1
[[ -f "${ANALYSIS_CANARY_OUT}/smoke.json" ]] && PRIOR_B2413_ARTIFACTS_PRESENT=1

jq -nc \
  --arg expected_workstream "${WORKSTREAM_ID}" \
  --arg expected_workspace "${WORKSPACE_ID}" \
  --arg expected_session "ws-cluster-workspace-habitat" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson session_schema_present "${SESSION_SCHEMA_PRESENT}" \
  --argjson compute_schema_present "${COMPUTE_SCHEMA_PRESENT}" \
  --argjson collaboration_schema_present "${COLLABORATION_SCHEMA_PRESENT}" \
  --argjson run_schema_present "${RUN_SCHEMA_PRESENT}" \
  --argjson collaborative_workbench_schema_present "${COLLABORATIVE_WORKBENCH_SCHEMA_PRESENT}" \
  --argjson workbench_source_present "${WORKBENCH_SOURCE_PRESENT}" \
  --argjson workspace_tenancy_source_present "${WORKSPACE_TENANCY_SOURCE_PRESENT}" \
  --argjson workspace_subagents_source_present "${WORKSPACE_SUBAGENTS_SOURCE_PRESENT}" \
  --argjson execution_state_source_present "${EXECUTION_STATE_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson prior_b251_artifacts_present "${PRIOR_B251_ARTIFACTS_PRESENT}" \
  --argjson prior_b242_artifacts_present "${PRIOR_B242_ARTIFACTS_PRESENT}" \
  --argjson prior_b2413_artifacts_present "${PRIOR_B2413_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    session_schema_present: $session_schema_present,
    compute_schema_present: $compute_schema_present,
    collaboration_schema_present: $collaboration_schema_present,
    run_schema_present: $run_schema_present,
    collaborative_workbench_schema_present: $collaborative_workbench_schema_present,
    workbench_source_present: $workbench_source_present,
    workspace_tenancy_source_present: $workspace_tenancy_source_present,
    workspace_subagents_source_present: $workspace_subagents_source_present,
    execution_state_source_present: $execution_state_source_present,
    http_source_present: $http_source_present,
    prior_b251_artifacts_present: $prior_b251_artifacts_present,
    prior_b242_artifacts_present: $prior_b242_artifacts_present,
    prior_b2413_artifacts_present: $prior_b2413_artifacts_present
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
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-session" \
  | jq '.' > "${OUT}/workbench-session.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/compute-selection" \
  | jq '.' > "${OUT}/compute-selection.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/collaboration-access" \
  | jq '.' > "${OUT}/collaboration-access.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-run" \
  | jq '.' > "${OUT}/workbench-run.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/collaborative-workbench" \
  | jq '.' > "${OUT}/collaborative-workbench.json"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=300s > "${OUT}/rollout-after.txt"

stop_port_forward
LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/collaborative-workbench" \
  | jq '.' > "${OUT}/collaborative-workbench-after-restart.json"

VSCODE_READY=0
CURSOR_READY=0
jq -e '[.client_access[] | select(.client_id == "vscode-desktop" and .access_state == "ready")] | length == 1' "${OUT}/workbench-session.json" >/dev/null && VSCODE_READY=1
jq -e '[.client_access[] | select(.client_id == "cursor" and .access_state == "ready")] | length == 1' "${OUT}/workbench-session.json" >/dev/null && CURSOR_READY=1

STABLE_ALIAS="$(jq -r '.stable_workspace_alias' "${OUT}/workbench-session.json")"
RECOMMENDED_SUBAGENT_ID="$(jq -r '.recommended_subagent_id // ""' "${OUT}/workbench-session.json")"
LIVE_SELECTED_SUBAGENT_ID="$(jq -r '.live_selected_subagent_id // ""' "${OUT}/workbench-session.json")"
EXECUTION_CURRENT_STATE="$(jq -r '.current_state // ""' "${OUT}/workbench-run.json")"
SUGGESTED_PROFILE_ID="$(jq -r '.suggested_profile_id' "${OUT}/compute-selection.json")"
SUGGESTED_PROFILE_REASON="$(jq -r '.suggested_profile_reason' "${OUT}/compute-selection.json")"
PARTNER_ACCESS_STATE="$(jq -r '.partner_access_state' "${OUT}/collaboration-access.json")"
MEMORY_QUERY_TYPE="$(jq -r '.memory_context.query_type // ""' "${OUT}/workbench-session.json")"
RESTART_RECOVERED_SESSION="$(jq -r '.recovered_session' "${OUT}/bootstrap-after-restart.json")"

jq -nc \
  --arg phase "B25.2" \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "$(jq -r '.session_id' "${OUT}/workbench-session.json")" \
  --arg stable_workspace_alias "${STABLE_ALIAS}" \
  --arg recommended_subagent_id "${RECOMMENDED_SUBAGENT_ID}" \
  --arg live_selected_subagent_id "${LIVE_SELECTED_SUBAGENT_ID}" \
  --arg execution_current_state "${EXECUTION_CURRENT_STATE}" \
  --arg suggested_profile_id "${SUGGESTED_PROFILE_ID}" \
  --arg suggested_profile_reason "${SUGGESTED_PROFILE_REASON}" \
  --arg partner_access_state "${PARTNER_ACCESS_STATE}" \
  --arg memory_query_type "${MEMORY_QUERY_TYPE}" \
  --argjson vscode_ready "${VSCODE_READY}" \
  --argjson cursor_ready "${CURSOR_READY}" \
  --argjson same_beagle_owned_identity "$(jq '.same_beagle_owned_identity' "${OUT}/collaborative-workbench.json")" \
  --argjson partner_allowed_profile_ids "$(jq '[.roles[] | select(.role_id == "partner-dev")][0].allowed_profile_ids' "${OUT}/collaboration-access.json")" \
  --argjson restart_recovered_session "${RESTART_RECOVERED_SESSION}" \
  '{
    status: "ok",
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    stable_workspace_alias: $stable_workspace_alias,
    vscode_ready: ($vscode_ready == 1),
    cursor_ready: ($cursor_ready == 1),
    recommended_subagent_id: (if $recommended_subagent_id == "" then null else $recommended_subagent_id end),
    live_selected_subagent_id: (if $live_selected_subagent_id == "" then null else $live_selected_subagent_id end),
    execution_current_state: (if $execution_current_state == "" then null else $execution_current_state end),
    suggested_profile_id: $suggested_profile_id,
    suggested_profile_reason: $suggested_profile_reason,
    partner_access_state: $partner_access_state,
    partner_allowed_profile_ids: $partner_allowed_profile_ids,
    memory_query_type: (if $memory_query_type == "" then null else $memory_query_type end),
    bootstrap_recovered_before: input.recovered_session,
    restart_recovered_session: $restart_recovered_session,
    note: "B25.2 keeps workspace, compute, collaboration, execution, and retrieval context in one bounded Beagle-owned workbench."
  }' "${OUT}/bootstrap-before.json" > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] collaborative compute experiment workbench smoke artifacts written to ${OUT}"
