#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/plan-execution-orchestrator}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18740}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
PRIOR_PLANNER_ARTIFACT_DIR="${PRIOR_PLANNER_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/intent-to-execution-planner}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B242_PLAN_APPROVAL_AND_BOUNDED_EXECUTION_ORCHESTRATOR.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B242_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B242_KNOWN_LIMITS.md}"
STATE_CONTRACT_FILE="${STATE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/execution-state-schema.yaml}"
RECEIPT_CONTRACT_FILE="${RECEIPT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/execution-receipt-schema.yaml}"
APPROVAL_CONTRACT_FILE="${APPROVAL_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/plan-approval-schema.yaml}"
PLAN_EXECUTION_SOURCE_FILE="${PLAN_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/plan_execution.rs}"
EXECUTION_STATE_SOURCE_FILE="${EXECUTION_STATE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/execution_state.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
WORKSTREAM_COCKPIT_SOURCE_FILE="${WORKSTREAM_COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
SUBAGENT_ROUTING_SOURCE_FILE="${SUBAGENT_ROUTING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_routing.rs}"
SUBAGENT_HANDOFF_SOURCE_FILE="${SUBAGENT_HANDOFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_handoff.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"

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
  local service_name="$1"
  local local_port="$2"
  local remote_port="$3"
  local pf_log="$4"
  local pid_var="$5"

  : > "${pf_log}"
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

curl_json() {
  local method="$1"
  local path="$2"
  local output="$3"
  local payload="${4:-}"
  if [[ -n "${payload}" ]]; then
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      -H "${JSON_HEADER}" \
      --data "${payload}" \
      "${BEAGLE_BASE_URL}${path}" | jq '.' > "${output}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "${BEAGLE_BASE_URL}${path}" | jq '.' > "${output}"
  fi
}

curl_json_retry() {
  local attempts="$1"
  local sleep_seconds="$2"
  local method="$3"
  local path="$4"
  local output="$5"
  local payload="${6:-}"
  local attempt=1

  while (( attempt <= attempts )); do
    if curl_json "${method}" "${path}" "${output}" "${payload}"; then
      return 0
    fi
    rm -f "${output}"
    if (( attempt == attempts )); then
      echo "[FAIL] request ${method} ${path} failed after ${attempts} attempts" >&2
      return 1
    fi
    sleep "${sleep_seconds}"
    attempt=$((attempt + 1))
  done
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
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"

DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
STATE_CONTRACT_PRESENT=0
RECEIPT_CONTRACT_PRESENT=0
APPROVAL_CONTRACT_PRESENT=0
PLAN_EXECUTION_SOURCE_PRESENT=0
EXECUTION_STATE_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
WORKSTREAM_COCKPIT_SOURCE_PRESENT=0
SUBAGENT_ROUTING_SOURCE_PRESENT=0
SUBAGENT_HANDOFF_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
PRIOR_PLANNER_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${STATE_CONTRACT_FILE}" ]] && STATE_CONTRACT_PRESENT=1
[[ -f "${RECEIPT_CONTRACT_FILE}" ]] && RECEIPT_CONTRACT_PRESENT=1
[[ -f "${APPROVAL_CONTRACT_FILE}" ]] && APPROVAL_CONTRACT_PRESENT=1

if rg -q "approve_execution_plan|start_execution_plan|stop_execution_plan|execution_status_summary_for_packet" "${PLAN_EXECUTION_SOURCE_FILE}"; then
  PLAN_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "PlanApproval|ExecutionStatePlane|ExecutionReceipt|ExecutionResultLinksDocument" "${EXECUTION_STATE_SOURCE_FILE}"; then
  EXECUTION_STATE_SOURCE_PRESENT=1
fi
if rg -q "execution: Option<PlanExecutionStatusSummary>" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "execution: Option<PlanExecutionStatusSummary>" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "plan_execution_path|execution: Option<PlanExecutionStatusSummary>" "${WORKSTREAM_COCKPIT_SOURCE_FILE}"; then
  WORKSTREAM_COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "execution: Option<PlanExecutionStatusSummary>" "${SUBAGENT_ROUTING_SOURCE_FILE}"; then
  SUBAGENT_ROUTING_SOURCE_PRESENT=1
fi
if rg -q "execution_state_present|execution_plan_id|execution_receipt_id" "${SUBAGENT_HANDOFF_SOURCE_FILE}"; then
  SUBAGENT_HANDOFF_SOURCE_PRESENT=1
fi
if rg -q "/plan-execution|approve_execution_plan|start_execution_plan|stop_execution_plan|apply_plan_execution_to_packet" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi

if [[ -f "${PRIOR_PLANNER_ARTIFACT_DIR}/planner-policy.json" ]] && \
   [[ -f "${PRIOR_PLANNER_ARTIFACT_DIR}/execution-plan-analysis.json" ]] && \
   [[ -f "${PRIOR_PLANNER_ARTIFACT_DIR}/execution-plan-implementation.json" ]] && \
   [[ -f "${PRIOR_PLANNER_ARTIFACT_DIR}/execution-plan-manuscript.json" ]]; then
  PRIOR_PLANNER_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson state_contract_present "${STATE_CONTRACT_PRESENT}" \
  --argjson receipt_contract_present "${RECEIPT_CONTRACT_PRESENT}" \
  --argjson approval_contract_present "${APPROVAL_CONTRACT_PRESENT}" \
  --argjson plan_execution_source_present "${PLAN_EXECUTION_SOURCE_PRESENT}" \
  --argjson execution_state_source_present "${EXECUTION_STATE_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_cockpit_source_present "${WORKSTREAM_COCKPIT_SOURCE_PRESENT}" \
  --argjson subagent_routing_source_present "${SUBAGENT_ROUTING_SOURCE_PRESENT}" \
  --argjson subagent_handoff_source_present "${SUBAGENT_HANDOFF_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson prior_planner_artifacts_present "${PRIOR_PLANNER_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_program: $expected_program,
    expected_campaign: $expected_campaign,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    state_contract_present: $state_contract_present,
    receipt_contract_present: $receipt_contract_present,
    approval_contract_present: $approval_contract_present,
    plan_execution_source_present: $plan_execution_source_present,
    execution_state_source_present: $execution_state_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    workstream_cockpit_source_present: $workstream_cockpit_source_present,
    subagent_routing_source_present: $subagent_routing_source_present,
    subagent_handoff_source_present: $subagent_handoff_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    prior_planner_artifacts_present: $prior_planner_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
JSON_HEADER="Content-Type: application/json"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${PF_LOG}" BEAGLE_PF_PID
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

INTENT_PAYLOAD="$(jq -n \
  --arg task_family "analysis" \
  --arg intent_text "Run the bounded operator-visible analysis loop and keep receipts plus result links on the same Beagle-owned identity." \
  --arg tool_id "claude-code" \
  --arg work_mode "analysis" \
  --arg query_text "bounded operator cpu loop receipts expedition 002 analysis context" \
  '{task_family: $task_family, intent_text: $intent_text, tool_id: $tool_id, work_mode: $work_mode, query_text: $query_text}')"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/intent-plan" "${OUT}/intent-plan-response.json" "${INTENT_PAYLOAD}"
jq '.execution_plan' "${OUT}/intent-plan-response.json" > "${OUT}/execution-plan.json"

APPROVAL_PAYLOAD="$(jq -n \
  --slurpfile plan "${OUT}/execution-plan.json" \
  --arg approved_by "beagle-operator" \
  --arg approval_note "Approve the canonical bounded analysis execution for B24.2 smoke." \
  '{execution_plan: $plan[0], approved_by: $approved_by, approval_note: $approval_note}')"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/approve" "${OUT}/execution-approval.json" "${APPROVAL_PAYLOAD}"

START_PAYLOAD="$(jq -n \
  --arg plan_id "$(jq -r '.plan_id' "${OUT}/execution-plan.json")" \
  --arg started_by "beagle-operator" \
  --arg start_note "Start the canonical bounded analysis execution for B24.2 smoke." \
  '{plan_id: $plan_id, started_by: $started_by, start_note: $start_note}')"

curl_json_retry 3 2 POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/start" "${OUT}/execution-state.json" "${START_PAYLOAD}"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/receipt" "${OUT}/execution-receipt.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/result-links" "${OUT}/execution-result-links.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-after-execution.json"
curl_json GET "/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" "${OUT}/program-context-after-execution.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/claude-code" "${OUT}/tool-claude-code-after-execution.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-route?tool_id=claude-code&work_mode=analysis" "${OUT}/workspace-subagent-route-after-execution.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-handoff" "${OUT}/workspace-subagent-handoff-after-execution.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution" "${OUT}/execution-state-reread.json"

jq -n \
  --arg phase "B24.2" \
  --arg planner_policy_id "$(jq -r '.planner_policy_id' "${OUT}/execution-state.json")" \
  --arg current_state "$(jq -r '.current_state' "${OUT}/execution-state.json")" \
  --arg selected_subagent_id "$(jq -r '.selected_subagent_id' "${OUT}/execution-state.json")" \
  --arg retrieval_query_type "$(jq -r '.retrieval_query_type' "${OUT}/execution-state.json")" \
  --arg compiler_profile_id "$(jq -r '.compiler_profile_id' "${OUT}/execution-state.json")" \
  --arg graphrag_query_mode "$(jq -r '.graphrag_query_mode' "${OUT}/execution-state.json")" \
  --arg temporal_truth_view "$(jq -r '.temporal_truth_view' "${OUT}/execution-state.json")" \
  --arg recipe_kind "$(jq -r '.recipe_kind // ""' "${OUT}/execution-state.json")" \
  --arg experiment_id "$(jq -r '.experiment_id // ""' "${OUT}/execution-state.json")" \
  --arg approval_state "$(jq -r '.approval_state' "${OUT}/execution-approval.json")" \
  --arg receipt_final_state "$(jq -r '.final_state' "${OUT}/execution-receipt.json")" \
  --argjson result_link_count "$(jq '.links | length' "${OUT}/execution-result-links.json")" \
  --argjson handoff_updated "$(jq '.handoff_updated' "${OUT}/execution-receipt.json")" \
  --argjson planner_artifacts_present "${PRIOR_PLANNER_ARTIFACTS_PRESENT}" \
  --argjson context_execution_present "$(jq '.packet.retrieval_context.execution != null' "${OUT}/context-after-execution.json")" \
  --argjson program_execution_present "$(jq '.packet.retrieval_context.execution != null' "${OUT}/program-context-after-execution.json")" \
  --argjson tool_execution_present "$(jq '.tool.execution != null' "${OUT}/tool-claude-code-after-execution.json")" \
  --argjson route_execution_present "$(jq '.route.execution != null' "${OUT}/workspace-subagent-route-after-execution.json")" \
  --argjson handoff_execution_present "$(jq '.propagation.execution_state_present' "${OUT}/workspace-subagent-handoff-after-execution.json")" \
  --argjson same_beagle_owned_identity "$(jq -n \
      --arg workstream "${EXPECTED_WORKSTREAM}" \
      --arg workspace "${EXPECTED_WORKSPACE}" \
      --arg session "${EXPECTED_SESSION}" \
      --slurpfile state "${OUT}/execution-state.json" \
      --slurpfile plan "${OUT}/execution-plan.json" \
      '($state[0].workstream_id == $workstream) and ($state[0].workspace_id == $workspace) and ($state[0].session_id == $session) and ($plan[0].workstream_id == $workstream) and ($plan[0].workspace_id == $workspace) and ($plan[0].session_id == $session)')" \
  --argjson restart_recovered_session "$(jq -n \
      --slurpfile state "${OUT}/execution-state.json" \
      --slurpfile reread "${OUT}/execution-state-reread.json" \
      '($state[0].execution_id == $reread[0].execution_id) and ($state[0].session_id == $reread[0].session_id) and ($reread[0].current_state == "succeeded")')" \
  '{
    phase: $phase,
    planner_policy_id: $planner_policy_id,
    current_state: $current_state,
    selected_subagent_id: $selected_subagent_id,
    retrieval_query_type: $retrieval_query_type,
    compiler_profile_id: $compiler_profile_id,
    graphrag_query_mode: $graphrag_query_mode,
    temporal_truth_view: $temporal_truth_view,
    recipe_kind: $recipe_kind,
    experiment_id: $experiment_id,
    approval_state: $approval_state,
    receipt_final_state: $receipt_final_state,
    result_link_count: $result_link_count,
    handoff_updated: $handoff_updated,
    planner_artifacts_present: $planner_artifacts_present,
    context_execution_present: $context_execution_present,
    program_execution_present: $program_execution_present,
    tool_execution_present: $tool_execution_present,
    route_execution_present: $route_execution_present,
    handoff_execution_present: $handoff_execution_present,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
