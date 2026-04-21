#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-sample-accumulation}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18790}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B2415_MANUSCRIPT_SAMPLE_ACCUMULATION_PROMOTION_GATE_RECHECK.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B2415_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B2415_KNOWN_LIMITS.md}"
MANUSCRIPT_SAMPLE_ACCUMULATION_CONTRACT_FILE="${MANUSCRIPT_SAMPLE_ACCUMULATION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-sample-accumulation-schema.yaml}"
MANUSCRIPT_PROMOTION_GATE_RECHECK_CONTRACT_FILE="${MANUSCRIPT_PROMOTION_GATE_RECHECK_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-promotion-gate-recheck-schema.yaml}"
AUTONOMY_CALIBRATION_SOURCE_FILE="${AUTONOMY_CALIBRATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/autonomy_calibration.rs}"
PLAN_EXECUTION_SOURCE_FILE="${PLAN_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/plan_execution.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
PRIOR_B2414_ARTIFACT_DIR="${PRIOR_B2414_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/manuscript-shadow-calibration}"
PRIOR_B2413_ARTIFACT_DIR="${PRIOR_B2413_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/analysis-canary-activation}"

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
MANUSCRIPT_SAMPLE_ACCUMULATION_CONTRACT_PRESENT=0
MANUSCRIPT_PROMOTION_GATE_RECHECK_CONTRACT_PRESENT=0
AUTONOMY_CALIBRATION_SOURCE_PRESENT=0
PLAN_EXECUTION_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
PRIOR_B2414_ARTIFACTS_PRESENT=0
PRIOR_B2413_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${MANUSCRIPT_SAMPLE_ACCUMULATION_CONTRACT_FILE}" ]] && MANUSCRIPT_SAMPLE_ACCUMULATION_CONTRACT_PRESENT=1
[[ -f "${MANUSCRIPT_PROMOTION_GATE_RECHECK_CONTRACT_FILE}" ]] && MANUSCRIPT_PROMOTION_GATE_RECHECK_CONTRACT_PRESENT=1

if rg -q "build_manuscript_sample_accumulation_bundle|beagle-manuscript-sample-accumulation-v1|beagle-manuscript-promotion-gate-recheck-v1" "${AUTONOMY_CALIBRATION_SOURCE_FILE}"; then
  AUTONOMY_CALIBRATION_SOURCE_PRESENT=1
fi
if rg -q "ensure_manuscript_sample_accumulation|manuscript-shadow-history|manuscript-promotion-gate" "${PLAN_EXECUTION_SOURCE_FILE}"; then
  PLAN_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "/manuscript-shadow-history|/manuscript-soak-metrics|/manuscript-promotion-gate" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if [[ -f "${PRIOR_B2414_ARTIFACT_DIR}/smoke.json" ]] && [[ -f "${PRIOR_B2414_ARTIFACT_DIR}/manuscript-rollout-metrics.json" ]] && jq -e '.phase == "B24.14" and .decision_output == "keep-shadow" and .restart_recovered_session == true' "${PRIOR_B2414_ARTIFACT_DIR}/smoke.json" >/dev/null && jq -e '.manuscript_sample_count == 1 and .recommendation_for_manuscript == "keep-shadow"' "${PRIOR_B2414_ARTIFACT_DIR}/manuscript-rollout-metrics.json" >/dev/null; then
  PRIOR_B2414_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_B2413_ARTIFACT_DIR}/smoke.json" ]] && jq -e '.phase == "B24.13" and .analysis_canary_live == true and .implementation_canary_retained == true and .manuscript_control_retained == true and .restart_recovered_session == true' "${PRIOR_B2413_ARTIFACT_DIR}/smoke.json" >/dev/null; then
  PRIOR_B2413_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson manuscript_sample_accumulation_contract_present "${MANUSCRIPT_SAMPLE_ACCUMULATION_CONTRACT_PRESENT}" \
  --argjson manuscript_promotion_gate_recheck_contract_present "${MANUSCRIPT_PROMOTION_GATE_RECHECK_CONTRACT_PRESENT}" \
  --argjson autonomy_calibration_source_present "${AUTONOMY_CALIBRATION_SOURCE_PRESENT}" \
  --argjson plan_execution_source_present "${PLAN_EXECUTION_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson prior_b2414_artifacts_present "${PRIOR_B2414_ARTIFACTS_PRESENT}" \
  --argjson prior_b2413_artifacts_present "${PRIOR_B2413_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    manuscript_sample_accumulation_contract_present: $manuscript_sample_accumulation_contract_present,
    manuscript_promotion_gate_recheck_contract_present: $manuscript_promotion_gate_recheck_contract_present,
    autonomy_calibration_source_present: $autonomy_calibration_source_present,
    plan_execution_source_present: $plan_execution_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    prior_b2414_artifacts_present: $prior_b2414_artifacts_present,
    prior_b2413_artifacts_present: $prior_b2413_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${PF_LOG}" BEAGLE_PF_PID
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-shadow-history" "${OUT}/manuscript-shadow-history.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-soak-metrics" "${OUT}/manuscript-soak-metrics.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-promotion-gate" "${OUT}/manuscript-promotion-gate.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-after-manuscript-sample-accumulation.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution" "${OUT}/execution-state-after-manuscript-sample-accumulation.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/receipt" "${OUT}/execution-receipt-after-manuscript-sample-accumulation.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/result-links" "${OUT}/execution-result-links-after-manuscript-sample-accumulation.json"

jq -n \
  --arg phase "B24.15" \
  --arg promotion_gate_decision "$(jq -r '.promotion_gate_decision' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson prior_shadow_sample_count "$(jq '.prior_shadow_sample_count' "${OUT}/manuscript-shadow-history.json")" \
  --argjson additional_shadow_sample_count "$(jq '.additional_shadow_sample_count' "${OUT}/manuscript-shadow-history.json")" \
  --argjson shadow_sample_count "$(jq '.shadow_sample_count' "${OUT}/manuscript-shadow-history.json")" \
  --argjson minimum_shadow_sample_count "$(jq '.minimum_shadow_sample_count' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson crossed_minimum_threshold "$(jq '.shadow_sample_count >= .minimum_shadow_sample_count' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson promotion_criteria_met "$(jq '.promotion_criteria_met' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson false_auto_continue_rate_basis_points "$(jq '.false_auto_continue_rate_basis_points' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson false_review_required_rate_basis_points "$(jq '.false_review_required_rate_basis_points' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson alignment_with_operator_decision_basis_points "$(jq '.alignment_with_operator_decision_basis_points' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson alignment_with_execution_outcome_basis_points "$(jq '.alignment_with_execution_outcome_basis_points' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson regression_count "$(jq '.regression_count' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson implementation_canary_retained "$(jq '.implementation_canary_retained' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson analysis_canary_retained "$(jq '.analysis_canary_retained' "${OUT}/manuscript-soak-metrics.json")" \
  --argjson promotion_gate_preview_matches "$(jq -n --slurpfile metrics "${OUT}/manuscript-soak-metrics.json" --slurpfile gate "${OUT}/manuscript-promotion-gate.json" '$metrics[0].promotion_gate_decision_preview == $gate[0].promotion_gate_decision')" \
  --argjson context_calibration_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-shadow-rechecked"' "${OUT}/context-after-manuscript-sample-accumulation.json")" \
  --argjson context_rollout_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"' "${OUT}/context-after-manuscript-sample-accumulation.json")" \
  --argjson execution_summary_calibration_visible "$(jq '.autonomy_policy_calibration_status == "manuscript-shadow-rechecked"' "${OUT}/execution-state-after-manuscript-sample-accumulation.json")" \
  --argjson execution_summary_rollout_visible "$(jq '.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"' "${OUT}/execution-state-after-manuscript-sample-accumulation.json")" \
  --argjson result_links_manuscript_visible "$(jq 'any(.links[]; .link_kind == "autonomy-policy-manuscript-control") and any(.links[]; .link_kind == "autonomy-policy-manuscript-candidate") and any(.links[]; .link_kind == "manuscript-shadow-comparison") and any(.links[]; .link_kind == "manuscript-rollout-metrics") and any(.links[]; .link_kind == "manuscript-rollout-decision") and any(.links[]; .link_kind == "manuscript-shadow-history") and any(.links[]; .link_kind == "manuscript-soak-metrics") and any(.links[]; .link_kind == "manuscript-promotion-gate")' "${OUT}/execution-result-links-after-manuscript-sample-accumulation.json")" \
  --argjson same_beagle_owned_identity "$(jq -n \
      --arg workstream "${EXPECTED_WORKSTREAM}" \
      --arg workspace "${EXPECTED_WORKSPACE}" \
      --arg session "${EXPECTED_SESSION}" \
      --slurpfile history "${OUT}/manuscript-shadow-history.json" \
      --slurpfile metrics "${OUT}/manuscript-soak-metrics.json" \
      --slurpfile gate "${OUT}/manuscript-promotion-gate.json" \
      '($history[0].workstream_id == $workstream) and
       ($history[0].workspace_id == $workspace) and
       ($history[0].session_id == $session) and
       ($metrics[0].workstream_id == $workstream) and
       ($metrics[0].workspace_id == $workspace) and
       ($metrics[0].session_id == $session) and
       ($gate[0].workstream_id == $workstream) and
       ($gate[0].workspace_id == $workspace) and
       ($gate[0].session_id == $session)')" \
  --argjson restart_recovered_session "$(jq '.current_state == "succeeded" and .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and .autonomy_policy_calibration_status == "manuscript-shadow-rechecked"' "${OUT}/execution-state-after-manuscript-sample-accumulation.json")" \
  '{
    phase: $phase,
    promotion_gate_decision: $promotion_gate_decision,
    prior_shadow_sample_count: $prior_shadow_sample_count,
    additional_shadow_sample_count: $additional_shadow_sample_count,
    shadow_sample_count: $shadow_sample_count,
    minimum_shadow_sample_count: $minimum_shadow_sample_count,
    crossed_minimum_threshold: $crossed_minimum_threshold,
    promotion_criteria_met: $promotion_criteria_met,
    false_auto_continue_rate_basis_points: $false_auto_continue_rate_basis_points,
    false_review_required_rate_basis_points: $false_review_required_rate_basis_points,
    alignment_with_operator_decision_basis_points: $alignment_with_operator_decision_basis_points,
    alignment_with_execution_outcome_basis_points: $alignment_with_execution_outcome_basis_points,
    regression_count: $regression_count,
    implementation_canary_retained: $implementation_canary_retained,
    analysis_canary_retained: $analysis_canary_retained,
    promotion_gate_preview_matches: $promotion_gate_preview_matches,
    context_calibration_visible: $context_calibration_visible,
    context_rollout_visible: $context_rollout_visible,
    execution_summary_calibration_visible: $execution_summary_calibration_visible,
    execution_summary_rollout_visible: $execution_summary_rollout_visible,
    result_links_manuscript_visible: $result_links_manuscript_visible,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
