#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/risk-gated-autonomy}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18781}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B246_RISK_GATED_AUTONOMY_AND_APPROVAL_POLICY.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B246_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B246_KNOWN_LIMITS.md}"
AUTONOMY_POLICY_CONTRACT_FILE="${AUTONOMY_POLICY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/autonomy-policy-schema.yaml}"
RISK_EVALUATION_CONTRACT_FILE="${RISK_EVALUATION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/risk-evaluation-schema.yaml}"
APPROVAL_GATING_DECISION_CONTRACT_FILE="${APPROVAL_GATING_DECISION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/approval-gating-decision-schema.yaml}"
AUTONOMY_POLICY_SOURCE_FILE="${AUTONOMY_POLICY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/autonomy_policy.rs}"
RISK_EVALUATION_SOURCE_FILE="${RISK_EVALUATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/risk_evaluation.rs}"
APPROVAL_GATE_SOURCE_FILE="${APPROVAL_GATE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/approval_gate.rs}"
PLAN_EXECUTION_SOURCE_FILE="${PLAN_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/plan_execution.rs}"
EXECUTION_STATE_SOURCE_FILE="${EXECUTION_STATE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/execution_state.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
SUBAGENT_HANDOFF_SOURCE_FILE="${SUBAGENT_HANDOFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_handoff.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
PRIOR_B243_ARTIFACT_DIR="${PRIOR_B243_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/execution-reflection}"
PRIOR_B245_ARTIFACT_DIR="${PRIOR_B245_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/review-to-dispatch-continuation}"

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
AUTONOMY_POLICY_CONTRACT_PRESENT=0
RISK_EVALUATION_CONTRACT_PRESENT=0
APPROVAL_GATING_DECISION_CONTRACT_PRESENT=0
AUTONOMY_POLICY_SOURCE_PRESENT=0
RISK_EVALUATION_SOURCE_PRESENT=0
APPROVAL_GATE_SOURCE_PRESENT=0
PLAN_EXECUTION_SOURCE_PRESENT=0
EXECUTION_STATE_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
SUBAGENT_HANDOFF_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
PRIOR_B243_ARTIFACTS_PRESENT=0
PRIOR_B245_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${AUTONOMY_POLICY_CONTRACT_FILE}" ]] && AUTONOMY_POLICY_CONTRACT_PRESENT=1
[[ -f "${RISK_EVALUATION_CONTRACT_FILE}" ]] && RISK_EVALUATION_CONTRACT_PRESENT=1
[[ -f "${APPROVAL_GATING_DECISION_CONTRACT_FILE}" ]] && APPROVAL_GATING_DECISION_CONTRACT_PRESENT=1

if rg -q "build_autonomy_policy|beagle-autonomy-policy-v1" "${AUTONOMY_POLICY_SOURCE_FILE}"; then
  AUTONOMY_POLICY_SOURCE_PRESENT=1
fi
if rg -q "build_risk_evaluation|beagle-risk-evaluation-v1|recommended_decision_class" "${RISK_EVALUATION_SOURCE_FILE}"; then
  RISK_EVALUATION_SOURCE_PRESENT=1
fi
if rg -q "build_approval_gating_decision|beagle-approval-gating-decision-v1|auto-continue|review-required|blocked" "${APPROVAL_GATE_SOURCE_FILE}"; then
  APPROVAL_GATE_SOURCE_PRESENT=1
fi
if rg -q "read_autonomy_policy|read_risk_evaluation|read_approval_gating_decision|B24.6|auto-continue|review-required|blocked" "${PLAN_EXECUTION_SOURCE_FILE}"; then
  PLAN_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "approval_gating_decision_class|approval_gating_dispatch_ready|approval_gating_blocked" "${EXECUTION_STATE_SOURCE_FILE}"; then
  EXECUTION_STATE_SOURCE_PRESENT=1
fi
if rg -q "execution: Option<PlanExecutionStatusSummary>" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "execution_approval_gating_decision_class|execution_approval_gating_dispatch_ready|execution_approval_gating_blocked" "${SUBAGENT_HANDOFF_SOURCE_FILE}"; then
  SUBAGENT_HANDOFF_SOURCE_PRESENT=1
fi
if rg -q "/autonomy-policy|/risk-evaluation|/approval-gating-decision" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if [[ -f "${PRIOR_B243_ARTIFACT_DIR}/smoke.json" ]]; then
  PRIOR_B243_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_B245_ARTIFACT_DIR}/smoke.json" ]]; then
  PRIOR_B245_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson autonomy_policy_contract_present "${AUTONOMY_POLICY_CONTRACT_PRESENT}" \
  --argjson risk_evaluation_contract_present "${RISK_EVALUATION_CONTRACT_PRESENT}" \
  --argjson approval_gating_decision_contract_present "${APPROVAL_GATING_DECISION_CONTRACT_PRESENT}" \
  --argjson autonomy_policy_source_present "${AUTONOMY_POLICY_SOURCE_PRESENT}" \
  --argjson risk_evaluation_source_present "${RISK_EVALUATION_SOURCE_PRESENT}" \
  --argjson approval_gate_source_present "${APPROVAL_GATE_SOURCE_PRESENT}" \
  --argjson plan_execution_source_present "${PLAN_EXECUTION_SOURCE_PRESENT}" \
  --argjson execution_state_source_present "${EXECUTION_STATE_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson subagent_handoff_source_present "${SUBAGENT_HANDOFF_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson prior_b243_artifacts_present "${PRIOR_B243_ARTIFACTS_PRESENT}" \
  --argjson prior_b245_artifacts_present "${PRIOR_B245_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    autonomy_policy_contract_present: $autonomy_policy_contract_present,
    risk_evaluation_contract_present: $risk_evaluation_contract_present,
    approval_gating_decision_contract_present: $approval_gating_decision_contract_present,
    autonomy_policy_source_present: $autonomy_policy_source_present,
    risk_evaluation_source_present: $risk_evaluation_source_present,
    approval_gate_source_present: $approval_gate_source_present,
    plan_execution_source_present: $plan_execution_source_present,
    execution_state_source_present: $execution_state_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    subagent_handoff_source_present: $subagent_handoff_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    prior_b243_artifacts_present: $prior_b243_artifacts_present,
    prior_b245_artifacts_present: $prior_b245_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
JSON_HEADER="Content-Type: application/json"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${PF_LOG}" BEAGLE_PF_PID
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/replan-suggestion" "${OUT}/replan-suggestion-source.json"

INBOX_PAYLOAD="$(jq -n \
  --arg created_by "beagle-operator" \
  --arg create_note "Materialize the operator-visible follow-on review item for B24.6 risk-gated autonomy." \
  '{created_by: $created_by, create_note: $create_note}')"
curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/review-inbox" "${OUT}/review-inbox-item-initial.json" "${INBOX_PAYLOAD}"

DECISION_PAYLOAD="$(jq -n \
  --arg inbox_item_id "$(jq -r '.inbox_item_id' "${OUT}/review-inbox-item-initial.json")" \
  --arg decision_action "approve" \
  --arg decided_by "beagle-operator" \
  --arg decision_note "Approve the bounded follow-on plan so B24.6 can evaluate whether the same identity may auto-continue." \
  '{inbox_item_id: $inbox_item_id, decision_action: $decision_action, decided_by: $decided_by, decision_note: $decision_note}')"
curl_json_retry 3 2 POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/review-inbox/decision" "${OUT}/review-decision.json" "${DECISION_PAYLOAD}"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/review-inbox" "${OUT}/review-inbox-item.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/follow-on-plan" "${OUT}/follow-on-plan.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/autonomy-policy" "${OUT}/autonomy-policy.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/risk-evaluation" "${OUT}/risk-evaluation.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/approval-gating-decision" "${OUT}/approval-gating-decision.json"
curl_json_retry 5 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/continuation-dispatch" "${OUT}/continuation-dispatch.json"
curl_json_retry 5 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/continuation-receipt" "${OUT}/continuation-receipt.json"
curl_json_retry 5 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/continuation-state" "${OUT}/continuation-state-after-gating.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-after-gating.json"
curl_json GET "/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" "${OUT}/program-context-after-gating.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-handoff" "${OUT}/workspace-subagent-handoff-after-gating.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution" "${OUT}/execution-state-after-gating.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/receipt" "${OUT}/execution-receipt-after-gating.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/result-links" "${OUT}/execution-result-links-after-gating.json"

jq -n \
  --arg phase "B24.6" \
  --arg decision_class "$(jq -r '.decision_class' "${OUT}/approval-gating-decision.json")" \
  --arg matched_policy_rule "$(jq -r '.matched_policy_rule' "${OUT}/approval-gating-decision.json")" \
  --arg risk_level "$(jq -r '.risk_level' "${OUT}/risk-evaluation.json")" \
  --argjson risk_score "$(jq '.risk_score' "${OUT}/risk-evaluation.json")" \
  --arg review_action "$(jq -r '.review_action' "${OUT}/continuation-dispatch.json")" \
  --arg follow_on_state "$(jq -r '.follow_on_state' "${OUT}/follow-on-plan.json")" \
  --arg dispatch_state "$(jq -r '.dispatch_state' "${OUT}/continuation-dispatch.json")" \
  --arg selected_subagent_id "$(jq -r '.next_selected_subagent_id' "${OUT}/continuation-dispatch.json")" \
  --arg operator_followup_action "$(jq -r '.operator_followup_action' "${OUT}/execution-state-after-gating.json")" \
  --arg continuation_current_state "$(jq -r '.current_state' "${OUT}/continuation-state-after-gating.json")" \
  --argjson context_gate_visible "$(jq '.packet.retrieval_context.execution.approval_gating_decision_class == "auto-continue" and .packet.retrieval_context.execution.approval_gating_dispatch_ready == true and .packet.retrieval_context.execution.continuation_dispatched == true' "${OUT}/context-after-gating.json")" \
  --argjson handoff_gate_visible "$(jq '.propagation.execution_approval_gating_decision_class == "auto-continue" and .propagation.execution_approval_gating_dispatch_ready == true and .propagation.execution_continuation_dispatched == true' "${OUT}/workspace-subagent-handoff-after-gating.json")" \
  --argjson same_beagle_owned_identity "$(jq -n \
      --arg workstream "${EXPECTED_WORKSTREAM}" \
      --arg workspace "${EXPECTED_WORKSPACE}" \
      --arg session "${EXPECTED_SESSION}" \
      --slurpfile inbox "${OUT}/review-inbox-item.json" \
      --slurpfile decision "${OUT}/review-decision.json" \
      --slurpfile follow_on "${OUT}/follow-on-plan.json" \
      --slurpfile policy "${OUT}/autonomy-policy.json" \
      --slurpfile risk "${OUT}/risk-evaluation.json" \
      --slurpfile gate "${OUT}/approval-gating-decision.json" \
      --slurpfile dispatch "${OUT}/continuation-dispatch.json" \
      --slurpfile state "${OUT}/continuation-state-after-gating.json" \
      '($inbox[0].workstream_id == $workstream) and
       ($inbox[0].workspace_id == $workspace) and
       ($inbox[0].session_id == $session) and
       ($decision[0].workstream_id == $workstream) and
       ($decision[0].workspace_id == $workspace) and
       ($decision[0].session_id == $session) and
       ($follow_on[0].workstream_id == $workstream) and
       ($follow_on[0].workspace_id == $workspace) and
       ($follow_on[0].session_id == $session) and
       ($policy[0].workstream_id == $workstream) and
       ($policy[0].workspace_id == $workspace) and
       ($policy[0].session_id == $session) and
       ($risk[0].workstream_id == $workstream) and
       ($risk[0].workspace_id == $workspace) and
       ($risk[0].session_id == $session) and
       ($gate[0].workstream_id == $workstream) and
       ($gate[0].workspace_id == $workspace) and
       ($gate[0].session_id == $session) and
       ($dispatch[0].workstream_id == $workstream) and
       ($dispatch[0].workspace_id == $workspace) and
       ($dispatch[0].session_id == $session) and
       ($state[0].workstream_id == $workstream) and
       ($state[0].workspace_id == $workspace) and
       ($state[0].session_id == $session)')" \
  --argjson restart_recovered_session "$(jq -n \
      --slurpfile dispatch "${OUT}/continuation-dispatch.json" \
      --slurpfile state "${OUT}/continuation-state-after-gating.json" \
      '($dispatch[0].dispatch_state == "dispatched") and
       ($state[0].current_state == "succeeded")')" \
  '{
    phase: $phase,
    decision_class: $decision_class,
    matched_policy_rule: $matched_policy_rule,
    risk_level: $risk_level,
    risk_score: $risk_score,
    review_action: $review_action,
    follow_on_state: $follow_on_state,
    dispatch_state: $dispatch_state,
    selected_subagent_id: $selected_subagent_id,
    operator_followup_action: $operator_followup_action,
    continuation_current_state: $continuation_current_state,
    context_gate_visible: $context_gate_visible,
    handoff_gate_visible: $handoff_gate_visible,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
