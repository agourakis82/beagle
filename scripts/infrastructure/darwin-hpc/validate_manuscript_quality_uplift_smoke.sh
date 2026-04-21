#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-quality-uplift}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/manuscript-trajectory-quality.json" \
  "${OUT}/manuscript-context-adequacy.json" \
  "${OUT}/manuscript-tuning-recommendation.json" \
  "${OUT}/manuscript-promotion-gate.json" \
  "${OUT}/context-after-manuscript-quality-uplift.json" \
  "${OUT}/execution-state-after-manuscript-quality-uplift.json" \
  "${OUT}/execution-receipt-after-manuscript-quality-uplift.json" \
  "${OUT}/execution-result-links-after-manuscript-quality-uplift.json" \
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
  .manuscript_trajectory_quality_contract_present == 1 and
  .manuscript_context_adequacy_contract_present == 1 and
  .manuscript_tuning_recommendation_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .trajectory_eval_source_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_reflection_source_present == 1 and
  .http_darwin_source_present == 1 and
  .lib_source_present == 1 and
  .prior_b2417_artifacts_present == 1 and
  .prior_b2416_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .trajectory_quality_version == "beagle-manuscript-trajectory-quality-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-quality-uplift" and
  .task_family != null and
  .selected_subagent_id != null and
  .source_trajectory_eval_id != null and
  .source_execution_reflection_id != null and
  .review_quality_label != null and
  .editorial_acceptance_fit != null and
  (.trajectory_quality == "manuscript-ready" or .trajectory_quality == "shadow-tuning-required" or .trajectory_quality == "needs-replan") and
  (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
  (.editorial_acceptance_fit == "good-fit" or .editorial_acceptance_fit == "partial-fit" or .editorial_acceptance_fit == "poor-fit") and
  .same_beagle_owned_identity == true and
  (.quality_uplift_required == true or .trajectory_quality == "manuscript-ready")
' "${OUT}/manuscript-trajectory-quality.json" >/dev/null

jq -e '
  .context_adequacy_version == "beagle-manuscript-context-adequacy-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-quality-uplift" and
  .manuscript_trajectory_quality_id != null and
  .manuscript_promotion_gate_id != null and
  (.context_sufficiency == "adequate" or .context_sufficiency == "adequate-but-misaligned" or .context_sufficiency == "insufficient") and
  (.retrieval_lane_fit == "good-fit" or .retrieval_lane_fit == "partial-fit" or .retrieval_lane_fit == "poor-fit") and
  (.graphrag_mode_fit == "good-fit" or .graphrag_mode_fit == "partial-fit" or .graphrag_mode_fit == "poor-fit") and
  (.truth_view_fit == "good-fit" or .truth_view_fit == "partial-fit" or .truth_view_fit == "poor-fit") and
  (.compiler_profile_fit == "good-fit" or .compiler_profile_fit == "partial-fit" or .compiler_profile_fit == "poor-fit") and
  (.task_profile_fit == "good-fit" or .task_profile_fit == "partial-fit" or .task_profile_fit == "poor-fit") and
  (.subagent_fit == "good-fit" or .subagent_fit == "partial-fit" or .subagent_fit == "poor-fit") and
  (.handoff_quality == "good-fit" or .handoff_quality == "partial-fit" or .handoff_quality == "poor-fit") and
  (.editorial_acceptance_fit == "good-fit" or .editorial_acceptance_fit == "partial-fit" or .editorial_acceptance_fit == "poor-fit") and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-context-adequacy.json" >/dev/null

jq -e '
  .recommendation_version == "beagle-manuscript-tuning-recommendation-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-quality-uplift" and
  .current_promotion_gate_decision == "keep-shadow" and
  .manuscript_must_remain_shadow == true and
  .candidate_policy_mode == "shadow-retest" and
  .candidate_task_family == "manuscript" and
  .candidate_selected_subagent_id == "manuscript" and
  .candidate_work_mode == "manuscript" and
  .candidate_retrieval_query_type == "general" and
  .candidate_compiler_profile_id == "b235-budget-manuscript" and
  .candidate_graphrag_query_mode == "global" and
  .candidate_temporal_truth_view == "both" and
  .candidate_context_task_profile == "manuscript" and
  .candidate_context_budget_profile_id == "b235-budget-manuscript" and
  .candidate_handoff_package == "workspace-manuscript-handoff" and
  .candidate_assembly_package == "workspace-manuscript-assembly" and
  .editorial_acceptance_target == "operator-ready" and
  .next_validation_mode == "shadow-retest" and
  .promotion_readiness_label == "tune-in-shadow" and
  (.recommended_changes | length) > 0 and
  (.highest_impact_fix | length) > 0 and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-tuning-recommendation.json" >/dev/null

jq -e '
  .gate_version == "beagle-manuscript-promotion-gate-recheck-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-alignment-signal" and
  .promotion_gate_decision == "keep-shadow" and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-promotion-gate.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-quality-uplifted" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/context-after-manuscript-quality-uplift.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "manuscript-quality-uplifted" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-manuscript-quality-uplift.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "manuscript-quality-uplifted" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/execution-receipt-after-manuscript-quality-uplift.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "manuscript-shadow-history") and
  any(.links[]; .link_kind == "manuscript-soak-metrics") and
  any(.links[]; .link_kind == "manuscript-alignment-labels") and
  any(.links[]; .link_kind == "manuscript-promotion-evidence") and
  any(.links[]; .link_kind == "manuscript-promotion-gate") and
  any(.links[]; .link_kind == "manuscript-trajectory-quality") and
  any(.links[]; .link_kind == "manuscript-context-adequacy") and
  any(.links[]; .link_kind == "manuscript-tuning-recommendation")
' "${OUT}/execution-result-links-after-manuscript-quality-uplift.json" >/dev/null

jq -e '
  .phase == "B24.18" and
  .promotion_gate_decision == "keep-shadow" and
  (.trajectory_quality == "shadow-tuning-required" or .trajectory_quality == "needs-replan" or .trajectory_quality == "manuscript-ready") and
  (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
  (.context_sufficiency == "adequate" or .context_sufficiency == "adequate-but-misaligned" or .context_sufficiency == "insufficient") and
  (.retrieval_lane_fit == "good-fit" or .retrieval_lane_fit == "partial-fit" or .retrieval_lane_fit == "poor-fit") and
  (.graphrag_mode_fit == "good-fit" or .graphrag_mode_fit == "partial-fit" or .graphrag_mode_fit == "poor-fit") and
  (.truth_view_fit == "good-fit" or .truth_view_fit == "partial-fit" or .truth_view_fit == "poor-fit") and
  (.compiler_profile_fit == "good-fit" or .compiler_profile_fit == "partial-fit" or .compiler_profile_fit == "poor-fit") and
  (.task_profile_fit == "good-fit" or .task_profile_fit == "partial-fit" or .task_profile_fit == "poor-fit") and
  (.subagent_fit == "good-fit" or .subagent_fit == "partial-fit" or .subagent_fit == "poor-fit") and
  (.handoff_quality == "good-fit" or .handoff_quality == "partial-fit" or .handoff_quality == "poor-fit") and
  (.editorial_acceptance_fit == "good-fit" or .editorial_acceptance_fit == "partial-fit" or .editorial_acceptance_fit == "poor-fit") and
  .quality_uplift_required == true and
  .compiled_context_sufficient == true and
  .candidate_policy_mode == "shadow-retest" and
  .candidate_task_family == "manuscript" and
  .candidate_selected_subagent_id == "manuscript" and
  .candidate_retrieval_query_type == "general" and
  .candidate_compiler_profile_id == "b235-budget-manuscript" and
  .candidate_graphrag_query_mode == "global" and
  .candidate_temporal_truth_view == "both" and
  .candidate_context_task_profile == "manuscript" and
  .candidate_context_budget_profile_id == "b235-budget-manuscript" and
  .candidate_handoff_package == "workspace-manuscript-handoff" and
  .candidate_assembly_package == "workspace-manuscript-assembly" and
  .editorial_acceptance_target == "operator-ready" and
  .recommended_change_count > 0 and
  (.highest_impact_fix | length) > 0 and
  .manuscript_must_remain_shadow == true and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .gate_still_shadow == true and
  .context_calibration_visible == true and
  .context_rollout_visible == true and
  .execution_summary_calibration_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_quality_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] manuscript quality uplift smoke artifacts validated"
