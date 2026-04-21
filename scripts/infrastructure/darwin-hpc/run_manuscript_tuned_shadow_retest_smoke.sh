#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-tuned-shadow-retest}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18811}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B2419_MANUSCRIPT_TUNED_SHADOW_RETEST_PROMOTION_GATE_RECHECK.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B2419_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B2419_KNOWN_LIMITS.md}"
MANUSCRIPT_SHADOW_RETEST_CONTRACT_FILE="${MANUSCRIPT_SHADOW_RETEST_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-shadow-retest-schema.yaml}"
MANUSCRIPT_QUALITY_GATE_RECHECK_CONTRACT_FILE="${MANUSCRIPT_QUALITY_GATE_RECHECK_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-quality-gate-recheck-schema.yaml}"
AUTONOMY_CALIBRATION_SOURCE_FILE="${AUTONOMY_CALIBRATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/autonomy_calibration.rs}"
PLAN_EXECUTION_SOURCE_FILE="${PLAN_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/plan_execution.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
PRIOR_B2418_ARTIFACT_DIR="${PRIOR_B2418_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/manuscript-quality-uplift}"
PRIOR_B2417_ARTIFACT_DIR="${PRIOR_B2417_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/manuscript-alignment-signal}"

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
MANUSCRIPT_SHADOW_RETEST_CONTRACT_PRESENT=0
MANUSCRIPT_QUALITY_GATE_RECHECK_CONTRACT_PRESENT=0
AUTONOMY_CALIBRATION_SOURCE_PRESENT=0
PLAN_EXECUTION_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
PRIOR_B2418_ARTIFACTS_PRESENT=0
PRIOR_B2417_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${MANUSCRIPT_SHADOW_RETEST_CONTRACT_FILE}" ]] && MANUSCRIPT_SHADOW_RETEST_CONTRACT_PRESENT=1
[[ -f "${MANUSCRIPT_QUALITY_GATE_RECHECK_CONTRACT_FILE}" ]] && MANUSCRIPT_QUALITY_GATE_RECHECK_CONTRACT_PRESENT=1

if rg -q "build_manuscript_quality_uplift_bundle|MANUSCRIPT_TUNING_RECOMMENDATION_VERSION|MANUSCRIPT_PROMOTION_GATE_RECHECK_VERSION" "${AUTONOMY_CALIBRATION_SOURCE_FILE}"; then
  AUTONOMY_CALIBRATION_SOURCE_PRESENT=1
fi
if rg -q "ensure_manuscript_quality_uplift|manuscript-tuning-recommendation|manuscript-promotion-gate" "${PLAN_EXECUTION_SOURCE_FILE}"; then
  PLAN_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "/manuscript-trajectory-quality|/manuscript-context-adequacy|/manuscript-tuning-recommendation|/manuscript-promotion-gate" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if rg -q "ensure_manuscript_quality_uplift|read_manuscript_tuning_recommendation|read_manuscript_promotion_gate" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi

if [[ -f "${PRIOR_B2418_ARTIFACT_DIR}/smoke.json" ]] && [[ -f "${PRIOR_B2418_ARTIFACT_DIR}/manuscript-tuning-recommendation.json" ]] && jq -e '.phase == "B24.18" and .promotion_gate_decision == "keep-shadow" and .quality_uplift_required == true and .candidate_policy_mode == "shadow-retest"' "${PRIOR_B2418_ARTIFACT_DIR}/smoke.json" >/dev/null; then
  PRIOR_B2418_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_B2417_ARTIFACT_DIR}/smoke.json" ]] && [[ -f "${PRIOR_B2417_ARTIFACT_DIR}/manuscript-promotion-gate.json" ]] && jq -e '.phase == "B24.17" and .promotion_gate_decision == "keep-shadow"' "${PRIOR_B2417_ARTIFACT_DIR}/smoke.json" >/dev/null; then
  PRIOR_B2417_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson manuscript_shadow_retest_contract_present "${MANUSCRIPT_SHADOW_RETEST_CONTRACT_PRESENT}" \
  --argjson manuscript_quality_gate_recheck_contract_present "${MANUSCRIPT_QUALITY_GATE_RECHECK_CONTRACT_PRESENT}" \
  --argjson autonomy_calibration_source_present "${AUTONOMY_CALIBRATION_SOURCE_PRESENT}" \
  --argjson plan_execution_source_present "${PLAN_EXECUTION_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson prior_b2418_artifacts_present "${PRIOR_B2418_ARTIFACTS_PRESENT}" \
  --argjson prior_b2417_artifacts_present "${PRIOR_B2417_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    manuscript_shadow_retest_contract_present: $manuscript_shadow_retest_contract_present,
    manuscript_quality_gate_recheck_contract_present: $manuscript_quality_gate_recheck_contract_present,
    autonomy_calibration_source_present: $autonomy_calibration_source_present,
    plan_execution_source_present: $plan_execution_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    lib_source_present: $lib_source_present,
    prior_b2418_artifacts_present: $prior_b2418_artifacts_present,
    prior_b2417_artifacts_present: $prior_b2417_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/port-forward.log" BEAGLE_PF_PID

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-trajectory-quality" "${OUT}/manuscript-trajectory-quality.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-context-adequacy" "${OUT}/manuscript-context-adequacy.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-tuning-recommendation" "${OUT}/manuscript-tuning-recommendation.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-promotion-evidence" "${OUT}/manuscript-promotion-evidence.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/manuscript-promotion-gate" "${OUT}/manuscript-promotion-gate.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-after-manuscript-tuned-shadow-retest.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution" "${OUT}/execution-state-after-manuscript-tuned-shadow-retest.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/receipt" "${OUT}/execution-receipt-after-manuscript-tuned-shadow-retest.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/plan-execution/result-links" "${OUT}/execution-result-links-after-manuscript-tuned-shadow-retest.json"

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg stage "implementation-and-analysis-canary-live-manuscript-tuned-shadow-retest" \
  --slurpfile trajectory "${OUT}/manuscript-trajectory-quality.json" \
  --slurpfile context "${OUT}/manuscript-context-adequacy.json" \
  --slurpfile recommendation "${OUT}/manuscript-tuning-recommendation.json" \
  --slurpfile gate "${OUT}/manuscript-promotion-gate.json" \
  '
  ($trajectory[0]) as $trajectory |
  ($context[0]) as $context |
  ($recommendation[0]) as $recommendation |
  ($gate[0]) as $gate |
  def observed_compiler: ($context.compiled_context_budget_profile_id // "unknown");
  def observed_graphrag: ($context.compiled_context_graphrag_query_mode // $context.active_graphrag_query_mode // "unknown");
  def observed_truth: ($context.temporal_truth_view // "unknown");
  def observed_task_profile: ($context.compiled_context_task_profile // $trajectory.task_family);
  def mismatch_dimensions:
    [
      (if $recommendation.candidate_task_family != $trajectory.task_family then "task_family" else empty end),
      (if $recommendation.candidate_selected_subagent_id != $trajectory.selected_subagent_id then "selected_subagent_id" else empty end),
      (if $recommendation.candidate_compiler_profile_id != observed_compiler then "compiler_profile_id" else empty end),
      (if $recommendation.candidate_graphrag_query_mode != observed_graphrag then "graphrag_query_mode" else empty end),
      (if $recommendation.candidate_temporal_truth_view != observed_truth then "temporal_truth_view" else empty end),
      (if $recommendation.candidate_context_task_profile != observed_task_profile then "context_task_profile" else empty end)
    ];
  {
    retest_version: "beagle-manuscript-shadow-retest-v1",
    manuscript_shadow_retest_id: ($gate.manuscript_promotion_gate_id + "-manuscript-shadow-retest"),
    manuscript_tuning_recommendation_id: $recommendation.manuscript_tuning_recommendation_id,
    manuscript_context_adequacy_id: $context.manuscript_context_adequacy_id,
    manuscript_trajectory_quality_id: $trajectory.manuscript_trajectory_quality_id,
    manuscript_promotion_gate_id: $gate.manuscript_promotion_gate_id,
    workstream_id: $trajectory.workstream_id,
    workspace_id: $trajectory.workspace_id,
    session_id: $trajectory.session_id,
    generated_at: $generated_at,
    rollout_stage: $stage,
    candidate_policy_mode: $recommendation.candidate_policy_mode,
    candidate_task_family: $recommendation.candidate_task_family,
    candidate_selected_subagent_id: $recommendation.candidate_selected_subagent_id,
    candidate_compiler_profile_id: $recommendation.candidate_compiler_profile_id,
    candidate_graphrag_query_mode: $recommendation.candidate_graphrag_query_mode,
    candidate_temporal_truth_view: $recommendation.candidate_temporal_truth_view,
    candidate_context_task_profile: $recommendation.candidate_context_task_profile,
    observed_task_family: $trajectory.task_family,
    observed_selected_subagent_id: $trajectory.selected_subagent_id,
    observed_compiler_profile_id: observed_compiler,
    observed_graphrag_query_mode: observed_graphrag,
    observed_temporal_truth_view: observed_truth,
    observed_context_task_profile: observed_task_profile,
    mismatch_dimensions: mismatch_dimensions,
    mismatch_count: (mismatch_dimensions | length),
    retest_applied: ((mismatch_dimensions | length) == 0),
    trajectory_quality: $trajectory.trajectory_quality,
    context_sufficiency: $context.context_sufficiency,
    review_quality_label: $trajectory.review_quality_label,
    editorial_acceptance_fit: $trajectory.editorial_acceptance_fit,
    same_beagle_owned_identity: (
      $trajectory.workstream_id == $context.workstream_id and
      $context.workstream_id == $recommendation.workstream_id and
      $recommendation.workstream_id == $gate.workstream_id and
      $trajectory.workspace_id == $context.workspace_id and
      $context.workspace_id == $recommendation.workspace_id and
      $recommendation.workspace_id == $gate.workspace_id and
      $trajectory.session_id == $context.session_id and
      $context.session_id == $recommendation.session_id and
      $recommendation.session_id == $gate.session_id
    ),
    note: "B24.19 rechecks whether the tuned manuscript shadow candidate from B24.18 is actually active on the observed lane before any promotion staging."
  }' > "${OUT}/manuscript-shadow-retest.json"

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg stage "implementation-and-analysis-canary-live-manuscript-tuned-shadow-retest" \
  --slurpfile retest "${OUT}/manuscript-shadow-retest.json" \
  --slurpfile recommendation "${OUT}/manuscript-tuning-recommendation.json" \
  --slurpfile evidence "${OUT}/manuscript-promotion-evidence.json" \
  --slurpfile gate "${OUT}/manuscript-promotion-gate.json" \
  '
  ($retest[0]) as $retest |
  ($recommendation[0]) as $recommendation |
  ($evidence[0]) as $evidence |
  ($gate[0]) as $gate |
  def tuned_quality_ready:
    (
      $retest.retest_applied == true and
      $retest.trajectory_quality == "manuscript-ready" and
      $retest.context_sufficiency == "adequate" and
      $retest.review_quality_label == "operator-ready" and
      $retest.editorial_acceptance_fit == "good-fit"
    );
  def promotion_criteria_met:
    (
      $gate.promotion_evidence_sufficient == true and
      tuned_quality_ready
    );
  {
    gate_recheck_version: "beagle-manuscript-quality-gate-recheck-v1",
    manuscript_quality_gate_recheck_id: ($retest.manuscript_shadow_retest_id + "-quality-gate-recheck"),
    manuscript_shadow_retest_id: $retest.manuscript_shadow_retest_id,
    manuscript_tuning_recommendation_id: $recommendation.manuscript_tuning_recommendation_id,
    manuscript_promotion_evidence_id: $evidence.manuscript_promotion_evidence_id,
    manuscript_promotion_gate_id: $gate.manuscript_promotion_gate_id,
    workstream_id: $gate.workstream_id,
    workspace_id: $gate.workspace_id,
    session_id: $gate.session_id,
    generated_at: $generated_at,
    rollout_stage: $stage,
    base_promotion_gate_decision: $gate.promotion_gate_decision,
    promotion_evidence_sufficient: $gate.promotion_evidence_sufficient,
    retest_applied: $retest.retest_applied,
    tuned_quality_ready: tuned_quality_ready,
    promotion_criteria_met: promotion_criteria_met,
    promotion_gate_decision: (if promotion_criteria_met then "stage-manuscript-canary" else "keep-shadow" end),
    promotion_readiness_label: (if promotion_criteria_met then "stage-manuscript-canary" else "keep-shadow" end),
    manuscript_must_remain_shadow: (promotion_criteria_met | not),
    implementation_canary_retained: $gate.implementation_canary_retained,
    analysis_canary_retained: $gate.analysis_canary_retained,
    same_beagle_owned_identity: (
      $retest.same_beagle_owned_identity and
      $gate.same_beagle_owned_identity and
      $evidence.same_beagle_owned_identity
    ),
    rationale: (
      if promotion_criteria_met then
        "The tuned manuscript lane is applied and quality now meets bounded promotion standards with sufficient evidence."
      elif $retest.retest_applied == false then
        "The tuned manuscript candidate has not yet been fully applied on the observed lane, so keep-shadow remains the safe decision."
      else
        "The tuned manuscript candidate is applied, but quality posture is still below the bounded promotion threshold."
      end
    ),
    next_action: (
      if promotion_criteria_met then
        "Stage manuscript canary under guarded rollout and keep rollback triggers active."
      elif $retest.retest_applied == false then
        "Apply the tuned manuscript lane (task/subagent/compiler/GraphRAG/truth-view profile) and rerun bounded shadow retest."
      else
        "Keep manuscript on shadow and continue trajectory/context quality tuning before rechecking promotion."
      end
    ),
    note: "B24.19 enriches manuscript promotion interpretation with explicit tuned-shadow-retest evidence instead of relying on coverage metrics alone."
  }' > "${OUT}/manuscript-quality-gate-recheck.json"

jq -n \
  --argjson source_summary_ok "$(jq '.doc_present == 1 and .go_no_go_present == 1 and .known_limits_present == 1 and .manuscript_shadow_retest_contract_present == 1 and .manuscript_quality_gate_recheck_contract_present == 1 and .autonomy_calibration_source_present == 1 and .plan_execution_source_present == 1 and .http_darwin_source_present == 1 and .lib_source_present == 1 and .prior_b2418_artifacts_present == 1 and .prior_b2417_artifacts_present == 1' "${OUT}/source-summary.json")" \
  --argjson same_identity "$(jq '.same_beagle_owned_identity' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --argjson retest_applied "$(jq '.retest_applied' "${OUT}/manuscript-shadow-retest.json")" \
  --argjson tuned_quality_ready "$(jq '.tuned_quality_ready' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --argjson promotion_evidence_sufficient "$(jq '.promotion_evidence_sufficient' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --argjson promotion_criteria_met "$(jq '.promotion_criteria_met' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --arg promotion_gate_decision "$(jq -r '.promotion_gate_decision' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --arg base_promotion_gate_decision "$(jq -r '.base_promotion_gate_decision' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --arg trajectory_quality "$(jq -r '.trajectory_quality' "${OUT}/manuscript-shadow-retest.json")" \
  --arg context_sufficiency "$(jq -r '.context_sufficiency' "${OUT}/manuscript-shadow-retest.json")" \
  --arg review_quality_label "$(jq -r '.review_quality_label' "${OUT}/manuscript-shadow-retest.json")" \
  --arg editorial_acceptance_fit "$(jq -r '.editorial_acceptance_fit' "${OUT}/manuscript-shadow-retest.json")" \
  --arg highest_impact_fix "$(jq -r '.highest_impact_fix' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_policy_mode "$(jq -r '.candidate_policy_mode' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_task_family "$(jq -r '.candidate_task_family' "${OUT}/manuscript-tuning-recommendation.json")" \
  --arg candidate_selected_subagent_id "$(jq -r '.candidate_selected_subagent_id' "${OUT}/manuscript-tuning-recommendation.json")" \
  --argjson mismatch_count "$(jq '.mismatch_count' "${OUT}/manuscript-shadow-retest.json")" \
  --argjson recommended_change_count "$(jq '.recommended_changes | length' "${OUT}/manuscript-tuning-recommendation.json")" \
  --argjson context_calibration_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-quality-uplifted"' "${OUT}/context-after-manuscript-tuned-shadow-retest.json")" \
  --argjson context_rollout_visible "$(jq '.packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"' "${OUT}/context-after-manuscript-tuned-shadow-retest.json")" \
  --argjson execution_summary_calibration_visible "$(jq '.autonomy_policy_calibration_status == "manuscript-quality-uplifted"' "${OUT}/execution-state-after-manuscript-tuned-shadow-retest.json")" \
  --argjson execution_summary_rollout_visible "$(jq '.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"' "${OUT}/execution-state-after-manuscript-tuned-shadow-retest.json")" \
  --argjson result_links_quality_visible "$(jq 'any(.links[]; .link_kind == "manuscript-shadow-history") and any(.links[]; .link_kind == "manuscript-soak-metrics") and any(.links[]; .link_kind == "manuscript-alignment-labels") and any(.links[]; .link_kind == "manuscript-promotion-evidence") and any(.links[]; .link_kind == "manuscript-promotion-gate") and any(.links[]; .link_kind == "manuscript-trajectory-quality") and any(.links[]; .link_kind == "manuscript-context-adequacy") and any(.links[]; .link_kind == "manuscript-tuning-recommendation")' "${OUT}/execution-result-links-after-manuscript-tuned-shadow-retest.json")" \
  --argjson implementation_canary_retained "$(jq '.implementation_canary_retained' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --argjson analysis_canary_retained "$(jq '.analysis_canary_retained' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --argjson manuscript_must_remain_shadow "$(jq '.manuscript_must_remain_shadow' "${OUT}/manuscript-quality-gate-recheck.json")" \
  --argjson restart_recovered_session "$(jq '.current_state == "succeeded" and .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and .autonomy_policy_calibration_status == "manuscript-quality-uplifted"' "${OUT}/execution-state-after-manuscript-tuned-shadow-retest.json")" \
  '{
    phase: "B24.19",
    base_promotion_gate_decision: $base_promotion_gate_decision,
    promotion_gate_decision: $promotion_gate_decision,
    promotion_evidence_sufficient: $promotion_evidence_sufficient,
    retest_applied: $retest_applied,
    tuned_quality_ready: $tuned_quality_ready,
    promotion_criteria_met: $promotion_criteria_met,
    trajectory_quality: $trajectory_quality,
    context_sufficiency: $context_sufficiency,
    review_quality_label: $review_quality_label,
    editorial_acceptance_fit: $editorial_acceptance_fit,
    candidate_policy_mode: $candidate_policy_mode,
    candidate_task_family: $candidate_task_family,
    candidate_selected_subagent_id: $candidate_selected_subagent_id,
    highest_impact_fix: $highest_impact_fix,
    mismatch_count: $mismatch_count,
    recommended_change_count: $recommended_change_count,
    manuscript_must_remain_shadow: $manuscript_must_remain_shadow,
    implementation_canary_retained: $implementation_canary_retained,
    analysis_canary_retained: $analysis_canary_retained,
    source_summary_ok: $source_summary_ok,
    context_calibration_visible: $context_calibration_visible,
    context_rollout_visible: $context_rollout_visible,
    execution_summary_calibration_visible: $execution_summary_calibration_visible,
    execution_summary_rollout_visible: $execution_summary_rollout_visible,
    result_links_quality_visible: $result_links_quality_visible,
    same_beagle_owned_identity: $same_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
