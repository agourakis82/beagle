#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/autonomy-policy-calibration}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/follow-on-plan-source.json" \
  "${OUT}/autonomy-policy-source.json" \
  "${OUT}/risk-evaluation-source.json" \
  "${OUT}/approval-gating-decision-source.json" \
  "${OUT}/calibration-dataset.json" \
  "${OUT}/policy-eval-report.json" \
  "${OUT}/escalation-thresholds.json" \
  "${OUT}/shadow-policy-comparison.json" \
  "${OUT}/updated-policy-recommendation.json" \
  "${OUT}/continuation-dispatch.json" \
  "${OUT}/continuation-receipt.json" \
  "${OUT}/continuation-state.json" \
  "${OUT}/context-after-calibration.json" \
  "${OUT}/execution-state-after-calibration.json" \
  "${OUT}/execution-receipt-after-calibration.json" \
  "${OUT}/execution-result-links-after-calibration.json" \
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
  .dataset_contract_present == 1 and
  .eval_report_contract_present == 1 and
  .threshold_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_state_source_present == 1 and
  .execution_reflection_source_present == 1 and
  .trajectory_eval_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b243_artifacts_present == 1 and
  .prior_b245_artifacts_present == 1 and
  .prior_b246_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .follow_on_plan_version == "beagle-follow-on-plan-v1" and
  .follow_on_state == "dispatched" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat"
' "${OUT}/follow-on-plan-source.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_scope == "follow-on-plan-gating"
' "${OUT}/autonomy-policy-source.json" >/dev/null

jq -e '
  .risk_evaluation_version == "beagle-risk-evaluation-v1" and
  .recommended_decision_class == "auto-continue" and
  .risk_level == "low"
' "${OUT}/risk-evaluation-source.json" >/dev/null

jq -e '
  .decision_version == "beagle-approval-gating-decision-v1" and
  .decision_class == "auto-continue" and
  .continuation_dispatch_permitted == true
' "${OUT}/approval-gating-decision-source.json" >/dev/null

jq -e '
  .dataset_version == "beagle-autonomy-calibration-dataset-v1" and
  .sample_count >= 4 and
  .replay_sample_count >= 1 and
  .shadow_sample_count >= 3 and
  any(.task_families_evaluated[]; . == "analysis") and
  any(.task_families_evaluated[]; . == "implementation") and
  any(.task_families_evaluated[]; . == "manuscript") and
  any(.decision_classes_evaluated[]; . == "auto-continue") and
  any(.decision_classes_evaluated[]; . == "review-required") and
  any(.decision_classes_evaluated[]; . == "blocked") and
  any(.samples[]; .expected_decision_class == "auto-continue") and
  any(.samples[]; .expected_decision_class == "review-required") and
  any(.samples[]; .expected_decision_class == "blocked")
' "${OUT}/calibration-dataset.json" >/dev/null

jq -e '
  .report_version == "beagle-autonomy-policy-eval-report-v1" and
  .stage_state == "shadow-only" and
  .policy_posture == "too-conservative" and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points > 0 and
  .false_blocked_rate_basis_points == 0 and
  any(.task_family_summaries[]; .task_family == "implementation" and .calibration_posture == "too-conservative")
' "${OUT}/policy-eval-report.json" >/dev/null

jq -e '
  .thresholds_version == "beagle-escalation-thresholds-v1" and
  .stage_state == "shadow-only" and
  (.thresholds | length) >= 3 and
  any(.thresholds[]; .task_family == "analysis" and .stage_state == "active-current") and
  any(.thresholds[]; .task_family == "implementation" and .stage_state == "shadow-only" and .auto_continue_enabled == true and .recommended_action == "stage-shadow-auto-continue") and
  any(.thresholds[]; .task_family == "manuscript" and .auto_continue_enabled == false)
' "${OUT}/escalation-thresholds.json" >/dev/null

jq -e '
  .comparison_version == "beagle-shadow-policy-comparison-v1" and
  .stage_state == "shadow-only" and
  .improved_alignment_count >= 1 and
  .regression_count == 0 and
  any(.samples[]; .task_family == "implementation" and .improved_alignment == true and .shadow_policy_decision_class == "auto-continue")
' "${OUT}/shadow-policy-comparison.json" >/dev/null

jq -e '
  .recommendation_version == "beagle-updated-policy-recommendation-v1" and
  .stage_state == "shadow-only" and
  .policy_posture == "too-conservative" and
  .recommended_action == "stage-shadow-threshold-update" and
  .safe_to_apply_live == false and
  any(.task_family_updates[]; .task_family == "implementation" and .recommended_action == "stage-shadow-auto-continue")
' "${OUT}/updated-policy-recommendation.json" >/dev/null

jq -e '
  .dispatch_version == "beagle-continuation-dispatch-v1" and
  .dispatch_state == "dispatched"
' "${OUT}/continuation-dispatch.json" >/dev/null

jq -e '
  .receipt_version == "beagle-continuation-receipt-v1" and
  .review_action == "approved" and
  .next_execution_receipt.final_state == "succeeded"
' "${OUT}/continuation-receipt.json" >/dev/null

jq -e '
  .state_version == "beagle-continuation-state-v1" and
  .current_state == "succeeded" and
  .next_execution_state.current_state == "succeeded"
' "${OUT}/continuation-state.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "shadow-evaluated" and
  (.packet.retrieval_context.execution.latest_autonomy_policy_eval_report_id | length) > 0
' "${OUT}/context-after-calibration.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "shadow-evaluated" and
  (.latest_autonomy_policy_eval_report_id | length) > 0 and
  (.latest_updated_policy_recommendation_id | length) > 0
' "${OUT}/execution-state-after-calibration.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "shadow-evaluated" and
  (.latest_autonomy_policy_eval_report_id | length) > 0
' "${OUT}/execution-receipt-after-calibration.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-calibration-dataset") and
  any(.links[]; .link_kind == "autonomy-policy-eval-report") and
  any(.links[]; .link_kind == "escalation-thresholds") and
  any(.links[]; .link_kind == "shadow-policy-comparison") and
  any(.links[]; .link_kind == "updated-policy-recommendation")
' "${OUT}/execution-result-links-after-calibration.json" >/dev/null

jq -e '
  .phase == "B24.7" and
  .policy_posture == "too-conservative" and
  .recommended_action == "stage-shadow-threshold-update" and
  .calibration_stage_state == "shadow-only" and
  .calibration_sample_count >= 4 and
  .replay_sample_count >= 1 and
  .shadow_sample_count >= 3 and
  .improved_alignment_count >= 1 and
  .regression_count == 0 and
  .safe_to_apply_live == false and
  .context_calibration_visible == true and
  .execution_summary_calibration_visible == true and
  .result_links_calibration_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] autonomy policy calibration smoke artifacts validated"
