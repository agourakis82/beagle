#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/shadow-threshold-update}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18783}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B248_SHADOW_THRESHOLD_UPDATE_AND_GUARDED_POLICY_ROLLOUT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B248_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B248_KNOWN_LIMITS.md}"
SHADOW_THRESHOLD_CONTRACT_FILE="${SHADOW_THRESHOLD_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/autonomy-shadow-threshold-schema.yaml}"
ROLLOUT_METRIC_CONTRACT_FILE="${ROLLOUT_METRIC_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/policy-rollout-metric-schema.yaml}"
ROLLOUT_DECISION_CONTRACT_FILE="${ROLLOUT_DECISION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/guarded-rollout-decision-schema.yaml}"
AUTONOMY_CALIBRATION_SOURCE_FILE="${AUTONOMY_CALIBRATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/autonomy_calibration.rs}"
PLAN_EXECUTION_SOURCE_FILE="${PLAN_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/plan_execution.rs}"
EXECUTION_STATE_SOURCE_FILE="${EXECUTION_STATE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/execution_state.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
PRIOR_B247_ARTIFACT_DIR="${PRIOR_B247_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/autonomy-policy-calibration}"

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
  curl -fsS -X "${method}" \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "${BEAGLE_BASE_URL}${path}" | jq '.' > "${output}"
}

curl_json_retry() {
  local attempts="$1"
  local sleep_seconds="$2"
  local method="$3"
  local path="$4"
  local output="$5"
  local attempt=1
  while (( attempt <= attempts )); do
    if curl_json "${method}" "${path}" "${output}"; then
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
SHADOW_THRESHOLD_CONTRACT_PRESENT=0
ROLLOUT_METRIC_CONTRACT_PRESENT=0
ROLLOUT_DECISION_CONTRACT_PRESENT=0
AUTONOMY_CALIBRATION_SOURCE_PRESENT=0
PLAN_EXECUTION_SOURCE_PRESENT=0
EXECUTION_STATE_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
PRIOR_B247_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${SHADOW_THRESHOLD_CONTRACT_FILE}" ]] && SHADOW_THRESHOLD_CONTRACT_PRESENT=1
[[ -f "${ROLLOUT_METRIC_CONTRACT_FILE}" ]] && ROLLOUT_METRIC_CONTRACT_PRESENT=1
[[ -f "${ROLLOUT_DECISION_CONTRACT_FILE}" ]] && ROLLOUT_DECISION_CONTRACT_PRESENT=1

if rg -q "build_guarded_policy_rollout_bundle|beagle-autonomy-shadow-threshold-v1|beagle-guarded-rollout-decision-v1" "${AUTONOMY_CALIBRATION_SOURCE_FILE}"; then
  AUTONOMY_CALIBRATION_SOURCE_PRESENT=1
fi
if rg -q "ensure_guarded_policy_rollout|autonomy-policy-current|rollout-metrics|guarded-rollout-decision" "${PLAN_EXECUTION_SOURCE_FILE}"; then
  PLAN_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "autonomy_policy_rollout_status|latest_guarded_rollout_decision_id|rollout_decision_path" "${EXECUTION_STATE_SOURCE_FILE}"; then
  EXECUTION_STATE_SOURCE_PRESENT=1
fi
if rg -q "/autonomy-policy-current|/autonomy-policy-candidate|/rollout-metrics|/guarded-rollout-decision" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if [[ -f "${PRIOR_B247_ARTIFACT_DIR}/smoke.json" ]]; then
  PRIOR_B247_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson shadow_threshold_contract_present "${SHADOW_THRESHOLD_CONTRACT_PRESENT}" \
  --argjson rollout_metric_contract_present "${ROLLOUT_METRIC_CONTRACT_PRESENT}" \
  --argjson rollout_decision_contract_present "${ROLLOUT_DECISION_CONTRACT_PRESENT}" \
  --argjson autonomy_calibration_source_present "${AUTONOMY_CALIBRATION_SOURCE_PRESENT}" \
  --argjson plan_execution_source_present "${PLAN_EXECUTION_SOURCE_PRESENT}" \
  --argjson execution_state_source_present "${EXECUTION_STATE_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson prior_b247_artifacts_present "${PRIOR_B247_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    shadow_threshold_contract_present: $shadow_threshold_contract_present,
    rollout_metric_contract_present: $rollout_metric_contract_present,
    rollout_decision_contract_present: $rollout_decision_contract_present,
    autonomy_calibration_source_present: $autonomy_calibration_source_present,
    plan_execution_source_present: $plan_execution_source_present,
    execution_state_source_present: $execution_state_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    prior_b247_artifacts_present: $prior_b247_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${PF_LOG}" BEAGLE_PF_PID
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/autonomy-policy-current" "${OUT}/autonomy-policy-current.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/autonomy-policy-candidate" "${OUT}/autonomy-policy-candidate.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/shadow-policy-comparison" "${OUT}/shadow-policy-comparison.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/rollout-metrics" "${OUT}/rollout-metrics.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/guarded-rollout-decision" "${OUT}/rollout-decision.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-after-rollout.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution" "${OUT}/execution-state-after-rollout.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/receipt" "${OUT}/execution-receipt-after-rollout.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/result-links" "${OUT}/execution-result-links-after-rollout.json"

jq -n \
  --arg phase "B24.8" \
  --arg rollout_stage "$(jq -r '.rollout_stage' "${OUT}/rollout-decision.json")" \
  --arg recommended_action "$(jq -r '.recommended_action' "${OUT}/rollout-decision.json")" \
  --argjson guarded_enablement_permitted "$(jq '.guarded_enablement_permitted' "${OUT}/rollout-decision.json")" \
  --argjson guarded_enablement_live "$(jq '.guarded_enablement_live' "${OUT}/rollout-decision.json")" \
  --argjson global_policy_update_permitted "$(jq '.global_policy_update_permitted' "${OUT}/rollout-decision.json")" \
  --argjson current_false_review_required_rate_basis_points "$(jq '.current_false_review_required_rate_basis_points' "${OUT}/rollout-metrics.json")" \
  --argjson candidate_false_review_required_rate_basis_points "$(jq '.candidate_false_review_required_rate_basis_points' "${OUT}/rollout-metrics.json")" \
  --argjson candidate_false_auto_continue_rate_basis_points "$(jq '.candidate_false_auto_continue_rate_basis_points' "${OUT}/rollout-metrics.json")" \
  --argjson improved_alignment_count "$(jq '.improved_alignment_count' "${OUT}/rollout-metrics.json")" \
  --argjson regression_count "$(jq '.regression_count' "${OUT}/rollout-metrics.json")" \
  --argjson implementation_guarded_ready "$(jq 'any(.family_metrics[]; .task_family == "implementation" and .rollout_readiness == "guarded-canary-ready")' "${OUT}/rollout-metrics.json")" \
  --argjson analysis_held_current "$(jq 'any(.current_control_task_families[]; . == "analysis")' "${OUT}/rollout-decision.json")" \
  --argjson manuscript_held_back "$(jq 'any(.blocked_or_hold_task_families[]; . == "manuscript")' "${OUT}/rollout-decision.json")" \
  --argjson rollback_ready "$(jq '(.rollback_trigger | length) > 0 and (.rollback_action | length) > 0' "${OUT}/rollout-decision.json")" \
  --argjson context_rollout_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-canary-staged" and (.packet.retrieval_context.execution.latest_guarded_rollout_decision_id | length) > 0' "${OUT}/context-after-rollout.json")" \
  --argjson execution_summary_rollout_visible "$(jq '.autonomy_policy_rollout_status == "implementation-canary-staged" and (.latest_autonomy_policy_candidate_id | length) > 0 and (.latest_guarded_rollout_decision_id | length) > 0' "${OUT}/execution-state-after-rollout.json")" \
  --argjson result_links_rollout_visible "$(jq 'any(.links[]; .link_kind == "autonomy-policy-current") and any(.links[]; .link_kind == "autonomy-policy-candidate") and any(.links[]; .link_kind == "rollout-metrics") and any(.links[]; .link_kind == "guarded-rollout-decision")' "${OUT}/execution-result-links-after-rollout.json")" \
  --argjson same_beagle_owned_identity "$(jq -n \
      --arg workstream "${EXPECTED_WORKSTREAM}" \
      --arg workspace "${EXPECTED_WORKSPACE}" \
      --arg session "${EXPECTED_SESSION}" \
      --slurpfile current "${OUT}/autonomy-policy-current.json" \
      --slurpfile candidate "${OUT}/autonomy-policy-candidate.json" \
      --slurpfile metrics "${OUT}/rollout-metrics.json" \
      --slurpfile decision "${OUT}/rollout-decision.json" \
      '($current[0].workstream_id == $workstream) and
       ($current[0].workspace_id == $workspace) and
       ($current[0].session_id == $session) and
       ($candidate[0].workstream_id == $workstream) and
       ($candidate[0].workspace_id == $workspace) and
       ($candidate[0].session_id == $session) and
       ($metrics[0].workstream_id == $workstream) and
       ($metrics[0].workspace_id == $workspace) and
       ($metrics[0].session_id == $session) and
       ($decision[0].workstream_id == $workstream) and
       ($decision[0].workspace_id == $workspace) and
       ($decision[0].session_id == $session)')" \
  --argjson restart_recovered_session "$(jq '.current_state == "succeeded" and .autonomy_policy_rollout_status == "implementation-canary-staged"' "${OUT}/execution-state-after-rollout.json")" \
  '{
    phase: $phase,
    rollout_stage: $rollout_stage,
    recommended_action: $recommended_action,
    guarded_enablement_permitted: $guarded_enablement_permitted,
    guarded_enablement_live: $guarded_enablement_live,
    global_policy_update_permitted: $global_policy_update_permitted,
    current_false_review_required_rate_basis_points: $current_false_review_required_rate_basis_points,
    candidate_false_review_required_rate_basis_points: $candidate_false_review_required_rate_basis_points,
    candidate_false_auto_continue_rate_basis_points: $candidate_false_auto_continue_rate_basis_points,
    improved_alignment_count: $improved_alignment_count,
    regression_count: $regression_count,
    implementation_guarded_ready: $implementation_guarded_ready,
    analysis_held_current: $analysis_held_current,
    manuscript_held_back: $manuscript_held_back,
    rollback_ready: $rollback_ready,
    context_rollout_visible: $context_rollout_visible,
    execution_summary_rollout_visible: $execution_summary_rollout_visible,
    result_links_rollout_visible: $result_links_rollout_visible,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
