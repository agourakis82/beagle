#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-quality-uplift}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18810}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B2418_MANUSCRIPT_QUALITY_UPLIFT_EDITORIAL_TRAJECTORY_TUNING.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B2418_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B2418_KNOWN_LIMITS.md}"
MANUSCRIPT_TRAJECTORY_QUALITY_CONTRACT_FILE="${MANUSCRIPT_TRAJECTORY_QUALITY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-trajectory-quality-schema.yaml}"
MANUSCRIPT_CONTEXT_ADEQUACY_CONTRACT_FILE="${MANUSCRIPT_CONTEXT_ADEQUACY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-context-adequacy-schema.yaml}"
MANUSCRIPT_TUNING_RECOMMENDATION_CONTRACT_FILE="${MANUSCRIPT_TUNING_RECOMMENDATION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-tuning-recommendation-schema.yaml}"
AUTONOMY_CALIBRATION_SOURCE_FILE="${AUTONOMY_CALIBRATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/autonomy_calibration.rs}"
TRAJECTORY_EVAL_SOURCE_FILE="${TRAJECTORY_EVAL_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/trajectory_eval.rs}"
PLAN_EXECUTION_SOURCE_FILE="${PLAN_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/plan_execution.rs}"
EXECUTION_REFLECTION_SOURCE_FILE="${EXECUTION_REFLECTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/execution_reflection.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
PRIOR_B2417_ARTIFACT_DIR="${PRIOR_B2417_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/manuscript-alignment-signal}"
PRIOR_B2416_ARTIFACT_DIR="${PRIOR_B2416_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/manuscript-alignment-labeling}"

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
MANUSCRIPT_TRAJECTORY_QUALITY_CONTRACT_PRESENT=0
MANUSCRIPT_CONTEXT_ADEQUACY_CONTRACT_PRESENT=0
MANUSCRIPT_TUNING_RECOMMENDATION_CONTRACT_PRESENT=0
AUTONOMY_CALIBRATION_SOURCE_PRESENT=0
TRAJECTORY_EVAL_SOURCE_PRESENT=0
PLAN_EXECUTION_SOURCE_PRESENT=0
EXECUTION_REFLECTION_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
PRIOR_B2417_ARTIFACTS_PRESENT=0
PRIOR_B2416_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${MANUSCRIPT_TRAJECTORY_QUALITY_CONTRACT_FILE}" ]] && MANUSCRIPT_TRAJECTORY_QUALITY_CONTRACT_PRESENT=1
[[ -f "${MANUSCRIPT_CONTEXT_ADEQUACY_CONTRACT_FILE}" ]] && MANUSCRIPT_CONTEXT_ADEQUACY_CONTRACT_PRESENT=1
[[ -f "${MANUSCRIPT_TUNING_RECOMMENDATION_CONTRACT_FILE}" ]] && MANUSCRIPT_TUNING_RECOMMENDATION_CONTRACT_PRESENT=1

if rg -q "build_manuscript_quality_uplift_bundle|beagle-manuscript-trajectory-quality-v1|beagle-manuscript-context-adequacy-v1|beagle-manuscript-tuning-recommendation-v1" "${AUTONOMY_CALIBRATION_SOURCE_FILE}"; then
  AUTONOMY_CALIBRATION_SOURCE_PRESENT=1
fi
if rg -q "manuscript_trajectory_uplift_label|shadow-tuning-required|needs-replan" "${TRAJECTORY_EVAL_SOURCE_FILE}"; then
  TRAJECTORY_EVAL_SOURCE_PRESENT=1
fi
if rg -q "ensure_manuscript_quality_uplift|manuscript-trajectory-quality|manuscript-context-adequacy|manuscript-tuning-recommendation" "${PLAN_EXECUTION_SOURCE_FILE}"; then
  PLAN_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "editorial_acceptance_fit_label|FIT_LABEL_GOOD|FIT_LABEL_PARTIAL" "${EXECUTION_REFLECTION_SOURCE_FILE}"; then
  EXECUTION_REFLECTION_SOURCE_PRESENT=1
fi
if rg -q "/manuscript-trajectory-quality|/manuscript-context-adequacy|/manuscript-tuning-recommendation|ensure_manuscript_quality_uplift" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if rg -q "ensure_manuscript_quality_uplift|read_manuscript_trajectory_quality|read_manuscript_context_adequacy|read_manuscript_tuning_recommendation" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if [[ -f "${PRIOR_B2417_ARTIFACT_DIR}/smoke.json" ]] && [[ -f "${PRIOR_B2417_ARTIFACT_DIR}/manuscript-promotion-gate.json" ]] && jq -e '.phase == "B24.17" and .promotion_gate_decision == "keep-shadow" and .restart_recovered_session == true' "${PRIOR_B2417_ARTIFACT_DIR}/smoke.json" >/dev/null && jq -e '.promotion_gate_decision == "keep-shadow" and .shadow_sample_count >= 4 and .operator_alignment_labeled_count > 0 and .execution_outcome_alignment_labeled_count > 0' "${PRIOR_B2417_ARTIFACT_DIR}/manuscript-promotion-gate.json" >/dev/null; then
  PRIOR_B2417_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_B2416_ARTIFACT_DIR}/smoke.json" ]] && [[ -f "${PRIOR_B2416_ARTIFACT_DIR}/manuscript-promotion-gate.json" ]] && jq -e '.phase == "B24.16" and .promotion_gate_decision == "keep-shadow" and .restart_recovered_session == true' "${PRIOR_B2416_ARTIFACT_DIR}/smoke.json" >/dev/null && jq -e '.promotion_gate_decision == "keep-shadow" and .shadow_sample_count >= 4' "${PRIOR_B2416_ARTIFACT_DIR}/manuscript-promotion-gate.json" >/dev/null; then
  PRIOR_B2416_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson manuscript_trajectory_quality_contract_present "${MANUSCRIPT_TRAJECTORY_QUALITY_CONTRACT_PRESENT}" \
  --argjson manuscript_context_adequacy_contract_present "${MANUSCRIPT_CONTEXT_ADEQUACY_CONTRACT_PRESENT}" \
  --argjson manuscript_tuning_recommendation_contract_present "${MANUSCRIPT_TUNING_RECOMMENDATION_CONTRACT_PRESENT}" \
  --argjson autonomy_calibration_source_present "${AUTONOMY_CALIBRATION_SOURCE_PRESENT}" \
  --argjson trajectory_eval_source_present "${TRAJECTORY_EVAL_SOURCE_PRESENT}" \
  --argjson plan_execution_source_present "${PLAN_EXECUTION_SOURCE_PRESENT}" \
  --argjson execution_reflection_source_present "${EXECUTION_REFLECTION_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson prior_b2417_artifacts_present "${PRIOR_B2417_ARTIFACTS_PRESENT}" \
  --argjson prior_b2416_artifacts_present "${PRIOR_B2416_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    manuscript_trajectory_quality_contract_present: $manuscript_trajectory_quality_contract_present,
    manuscript_context_adequacy_contract_present: $manuscript_context_adequacy_contract_present,
    manuscript_tuning_recommendation_contract_present: $manuscript_tuning_recommendation_contract_present,
    autonomy_calibration_source_present: $autonomy_calibration_source_present,
    trajectory_eval_source_present: $trajectory_eval_source_present,
    plan_execution_source_present: $plan_execution_source_present,
    execution_reflection_source_present: $execution_reflection_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    lib_source_present: $lib_source_present,
    prior_b2417_artifacts_present: $prior_b2417_artifacts_present,
    prior_b2416_artifacts_present: $prior_b2416_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${PF_LOG}" BEAGLE_PF_PID
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-trajectory-quality" "${OUT}/manuscript-trajectory-quality.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-context-adequacy" "${OUT}/manuscript-context-adequacy.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-tuning-recommendation" "${OUT}/manuscript-tuning-recommendation.json"
curl_json_retry 3 2 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-promotion-gate" "${OUT}/manuscript-promotion-gate.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-after-manuscript-quality-uplift.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution" "${OUT}/execution-state-after-manuscript-quality-uplift.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/receipt" "${OUT}/execution-receipt-after-manuscript-quality-uplift.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/result-links" "${OUT}/execution-result-links-after-manuscript-quality-uplift.json"

jq -n \
  --arg phase "B24.18" \
  --arg promotion_gate_decision "$(jq -r '.promotion_gate_decision' "${OUT}/manuscript-promotion-gate.json")" \
  --arg trajectory_quality "$(jq -r '.trajectory_quality' "${OUT}/manuscript-trajectory-quality.json")" \
  --arg review_quality_label "$(jq -r '.review_quality_label' "${OUT}/manuscript-trajectory-quality.json")" \
  --arg context_sufficiency "$(jq -r '.context_sufficiency' "${OUT}/manuscript-context-adequacy.json")" \
  --arg retrieval_lane_fit "$(jq -r '.retrieval_lane_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg graphrag_mode_fit "$(jq -r '.graphrag_mode_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg truth_view_fit "$(jq -r '.truth_view_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg compiler_profile_fit "$(jq -r '.compiler_profile_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg task_profile_fit "$(jq -r '.task_profile_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg subagent_fit "$(jq -r '.subagent_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg handoff_quality "$(jq -r '.handoff_quality' "${OUT}/manuscript-context-adequacy.json")" \
  --arg editorial_acceptance_fit "$(jq -r '.editorial_acceptance_fit' "${OUT}/manuscript-context-adequacy.json")" \
  --arg candidate_policy_mode "$(jq -r '.candidate_policy_mode' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_task_family "$(jq -r '.candidate_task_family' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_selected_subagent_id "$(jq -r '.candidate_selected_subagent_id' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_retrieval_query_type "$(jq -r '.candidate_retrieval_query_type' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_compiler_profile_id "$(jq -r '.candidate_compiler_profile_id' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_graphrag_query_mode "$(jq -r '.candidate_graphrag_query_mode' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_temporal_truth_view "$(jq -r '.candidate_temporal_truth_view' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_context_task_profile "$(jq -r '.candidate_context_task_profile' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_context_budget_profile_id "$(jq -r '.candidate_context_budget_profile_id' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_handoff_package "$(jq -r '.candidate_handoff_package' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_assembly_package "$(jq -r '.candidate_assembly_package' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg editorial_acceptance_target "$(jq -r '.editorial_acceptance_target' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg highest_impact_fix "$(jq -r '.highest_impact_fix' "${OUT}/manuscript-tuning-recommendation.json")" \
  --argjson quality_uplift_required "$(jq '.quality_uplift_required' "${OUT}/manuscript-trajectory-quality.json")" \
  --argjson compiled_context_sufficient "$(jq '.compiled_context_sufficient' "${OUT}/manuscript-context-adequacy.json")" \
  --argjson manuscript_must_remain_shadow "$(jq '.manuscript_must_remain_shadow' "${OUT}/manuscript-tuning-recommendation.json")" \
  --argjson recommended_change_count "$(jq '.recommended_changes | length' "${OUT}/manuscript-tuning-recommendation.json")" \
  --argjson implementation_canary_retained "$(jq '.implementation_canary_retained' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson analysis_canary_retained "$(jq '.analysis_canary_retained' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson gate_still_shadow "$(jq '.promotion_gate_decision == "keep-shadow"' "${OUT}/manuscript-promotion-gate.json")" \
  --argjson context_calibration_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-quality-uplifted"' "${OUT}/context-after-manuscript-quality-uplift.json")" \
  --argjson context_rollout_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"' "${OUT}/context-after-manuscript-quality-uplift.json")" \
  --argjson execution_summary_calibration_visible "$(jq '.autonomy_policy_calibration_status == "manuscript-quality-uplifted"' "${OUT}/execution-state-after-manuscript-quality-uplift.json")" \
  --argjson execution_summary_rollout_visible "$(jq '.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"' "${OUT}/execution-state-after-manuscript-quality-uplift.json")" \
  --argjson result_links_quality_visible "$(jq 'any(.links[]; .link_kind == "manuscript-trajectory-quality") and any(.links[]; .link_kind == "manuscript-context-adequacy") and any(.links[]; .link_kind == "manuscript-tuning-recommendation") and any(.links[]; .link_kind == "manuscript-promotion-gate")' "${OUT}/execution-result-links-after-manuscript-quality-uplift.json")" \
  --argjson same_beagle_owned_identity "$(jq -n \
      --arg workstream "${EXPECTED_WORKSTREAM}" \
      --arg workspace "${EXPECTED_WORKSPACE}" \
      --arg session "${EXPECTED_SESSION}" \
      --slurpfile trajectory "${OUT}/manuscript-trajectory-quality.json" \
      --slurpfile context "${OUT}/manuscript-context-adequacy.json" \
      --slurpfile tuning "${OUT}/manuscript-tuning-recommendation.json" \
      --slurpfile gate "${OUT}/manuscript-promotion-gate.json" \
      '($trajectory[0].workstream_id == $workstream) and
       ($trajectory[0].workspace_id == $workspace) and
       ($trajectory[0].session_id == $session) and
       ($context[0].workstream_id == $workstream) and
       ($context[0].workspace_id == $workspace) and
       ($context[0].session_id == $session) and
       ($tuning[0].workstream_id == $workstream) and
       ($tuning[0].workspace_id == $workspace) and
       ($tuning[0].session_id == $session) and
       ($gate[0].workstream_id == $workstream) and
       ($gate[0].workspace_id == $workspace) and
       ($gate[0].session_id == $session) and
       ($trajectory[0].same_beagle_owned_identity == true) and
       ($context[0].same_beagle_owned_identity == true) and
       ($tuning[0].same_beagle_owned_identity == true) and
       ($gate[0].same_beagle_owned_identity == true)')" \
  --argjson restart_recovered_session "$(jq '.current_state == "succeeded" and .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and .autonomy_policy_calibration_status == "manuscript-quality-uplifted"' "${OUT}/execution-state-after-manuscript-quality-uplift.json")" \
  '{
    phase: $phase,
    promotion_gate_decision: $promotion_gate_decision,
    trajectory_quality: $trajectory_quality,
    review_quality_label: $review_quality_label,
    context_sufficiency: $context_sufficiency,
    retrieval_lane_fit: $retrieval_lane_fit,
    graphrag_mode_fit: $graphrag_mode_fit,
    truth_view_fit: $truth_view_fit,
    compiler_profile_fit: $compiler_profile_fit,
    task_profile_fit: $task_profile_fit,
    subagent_fit: $subagent_fit,
    handoff_quality: $handoff_quality,
    editorial_acceptance_fit: $editorial_acceptance_fit,
    quality_uplift_required: $quality_uplift_required,
    compiled_context_sufficient: $compiled_context_sufficient,
    candidate_policy_mode: $candidate_policy_mode,
    candidate_task_family: $candidate_task_family,
    candidate_selected_subagent_id: $candidate_selected_subagent_id,
    candidate_retrieval_query_type: $candidate_retrieval_query_type,
    candidate_compiler_profile_id: $candidate_compiler_profile_id,
    candidate_graphrag_query_mode: $candidate_graphrag_query_mode,
    candidate_temporal_truth_view: $candidate_temporal_truth_view,
    candidate_context_task_profile: $candidate_context_task_profile,
    candidate_context_budget_profile_id: $candidate_context_budget_profile_id,
    candidate_handoff_package: $candidate_handoff_package,
    candidate_assembly_package: $candidate_assembly_package,
    editorial_acceptance_target: $editorial_acceptance_target,
    highest_impact_fix: $highest_impact_fix,
    recommended_change_count: $recommended_change_count,
    manuscript_must_remain_shadow: $manuscript_must_remain_shadow,
    implementation_canary_retained: $implementation_canary_retained,
    analysis_canary_retained: $analysis_canary_retained,
    gate_still_shadow: $gate_still_shadow,
    context_calibration_visible: $context_calibration_visible,
    context_rollout_visible: $context_rollout_visible,
    execution_summary_calibration_visible: $execution_summary_calibration_visible,
    execution_summary_rollout_visible: $execution_summary_rollout_visible,
    result_links_quality_visible: $result_links_quality_visible,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
