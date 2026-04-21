#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-tuned-shadow-retest}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/manuscript-shadow-retest.json" \
  "${OUT}/manuscript-quality-gate-recheck.json" \
  "${OUT}/manuscript-promotion-gate.json" \
  "${OUT}/manuscript-promotion-evidence.json" \
  "${OUT}/manuscript-tuning-recommendation.json" \
  "${OUT}/manuscript-context-adequacy.json" \
  "${OUT}/manuscript-trajectory-quality.json" \
  "${OUT}/context-after-manuscript-tuned-shadow-retest.json" \
  "${OUT}/execution-state-after-manuscript-tuned-shadow-retest.json" \
  "${OUT}/execution-receipt-after-manuscript-tuned-shadow-retest.json" \
  "${OUT}/execution-result-links-after-manuscript-tuned-shadow-retest.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  require_file "${path}"
done

jq -e '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_program == "beagle-physio-symbolic-exocortex" and
  .expected_workspace == "beagle-cluster-pilot" and
  .expected_session == "ws-cluster-workspace-habitat" and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .manuscript_shadow_retest_contract_present == 1 and
  .manuscript_quality_gate_recheck_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .http_darwin_source_present == 1 and
  .lib_source_present == 1 and
  .prior_b2418_artifacts_present == 1 and
  .prior_b2417_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .retest_version == "beagle-manuscript-shadow-retest-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-tuned-shadow-retest" and
  .candidate_policy_mode == "shadow-retest" and
  .candidate_task_family == "manuscript" and
  .candidate_selected_subagent_id == "manuscript" and
  .candidate_compiler_profile_id == "b235-budget-manuscript" and
  .candidate_graphrag_query_mode == "global" and
  .candidate_temporal_truth_view == "both" and
  .candidate_context_task_profile == "manuscript" and
  (.mismatch_count >= 0) and
  ((.mismatch_dimensions | length) == .mismatch_count) and
  (.trajectory_quality == "manuscript-ready" or .trajectory_quality == "shadow-tuning-required" or .trajectory_quality == "needs-replan") and
  (.context_sufficiency == "adequate" or .context_sufficiency == "adequate-but-misaligned" or .context_sufficiency == "insufficient") and
  (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
  (.editorial_acceptance_fit == "good-fit" or .editorial_acceptance_fit == "partial-fit" or .editorial_acceptance_fit == "poor-fit") and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-shadow-retest.json" >/dev/null

jq -e '
  .gate_recheck_version == "beagle-manuscript-quality-gate-recheck-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-tuned-shadow-retest" and
  (.base_promotion_gate_decision == "keep-shadow" or .base_promotion_gate_decision == "stage-manuscript-canary") and
  (.promotion_gate_decision == "keep-shadow" or .promotion_gate_decision == "stage-manuscript-canary") and
  (.promotion_readiness_label == "keep-shadow" or .promotion_readiness_label == "stage-manuscript-canary") and
  (.promotion_criteria_met == (.promotion_evidence_sufficient and .tuned_quality_ready)) and
  (.manuscript_must_remain_shadow == (.promotion_criteria_met | not)) and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .same_beagle_owned_identity == true and
  (.rationale | length > 0) and
  (.next_action | length > 0)
' "${OUT}/manuscript-quality-gate-recheck.json" >/dev/null

jq -e '
  .gate_version == "beagle-manuscript-promotion-gate-recheck-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-alignment-signal" and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-promotion-gate.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-quality-uplifted" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/context-after-manuscript-tuned-shadow-retest.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "manuscript-quality-uplifted" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-manuscript-tuned-shadow-retest.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "manuscript-quality-uplifted" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/execution-receipt-after-manuscript-tuned-shadow-retest.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "manuscript-shadow-history") and
  any(.links[]; .link_kind == "manuscript-soak-metrics") and
  any(.links[]; .link_kind == "manuscript-alignment-labels") and
  any(.links[]; .link_kind == "manuscript-promotion-evidence") and
  any(.links[]; .link_kind == "manuscript-promotion-gate") and
  any(.links[]; .link_kind == "manuscript-trajectory-quality") and
  any(.links[]; .link_kind == "manuscript-context-adequacy") and
  any(.links[]; .link_kind == "manuscript-tuning-recommendation")
' "${OUT}/execution-result-links-after-manuscript-tuned-shadow-retest.json" >/dev/null

jq -e '
  .phase == "B24.19" and
  (.base_promotion_gate_decision == "keep-shadow" or .base_promotion_gate_decision == "stage-manuscript-canary") and
  (.promotion_gate_decision == "keep-shadow" or .promotion_gate_decision == "stage-manuscript-canary") and
  .source_summary_ok == true and
  .promotion_criteria_met == (.promotion_evidence_sufficient and .tuned_quality_ready) and
  .manuscript_must_remain_shadow == (.promotion_criteria_met | not) and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .context_calibration_visible == true and
  .context_rollout_visible == true and
  .execution_summary_calibration_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_quality_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true and
  .recommended_change_count > 0 and
  .mismatch_count >= 0 and
  (.highest_impact_fix | length > 0)
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] manuscript tuned shadow retest smoke artifacts validated"
