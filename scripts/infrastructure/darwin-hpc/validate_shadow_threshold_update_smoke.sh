#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/shadow-threshold-update}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/autonomy-policy-current.json" \
  "${OUT}/autonomy-policy-candidate.json" \
  "${OUT}/shadow-policy-comparison.json" \
  "${OUT}/rollout-metrics.json" \
  "${OUT}/rollout-decision.json" \
  "${OUT}/context-after-rollout.json" \
  "${OUT}/execution-state-after-rollout.json" \
  "${OUT}/execution-receipt-after-rollout.json" \
  "${OUT}/execution-result-links-after-rollout.json" \
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
  .shadow_threshold_contract_present == 1 and
  .rollout_metric_contract_present == 1 and
  .rollout_decision_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_state_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b247_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .shadow_threshold_version == "beagle-autonomy-shadow-threshold-v1" and
  .policy_role == "current-control" and
  .stage_state == "control-live" and
  any(.family_thresholds[]; .task_family == "analysis" and .rollout_state == "active-current" and .auto_continue_enabled == true) and
  any(.family_thresholds[]; .task_family == "implementation" and .auto_continue_enabled == false) and
  any(.family_thresholds[]; .task_family == "manuscript" and .auto_continue_enabled == false)
' "${OUT}/autonomy-policy-current.json" >/dev/null

jq -e '
  .shadow_threshold_version == "beagle-autonomy-shadow-threshold-v1" and
  .policy_role == "candidate-shadow" and
  .stage_state == "shadow-candidate" and
  any(.family_thresholds[]; .task_family == "analysis" and .rollout_state == "hold-current-control") and
  any(.family_thresholds[]; .task_family == "implementation" and .rollout_state == "guarded-canary-staged" and .auto_continue_enabled == true and .guarded_enablement_eligible == true) and
  any(.family_thresholds[]; .task_family == "manuscript" and .rollout_state == "hold-shadow-only" and .auto_continue_enabled == false)
' "${OUT}/autonomy-policy-candidate.json" >/dev/null

jq -e '
  .comparison_version == "beagle-shadow-policy-comparison-v1" and
  .stage_state == "shadow-only" and
  .improved_alignment_count >= 1 and
  .regression_count == 0 and
  any(.samples[]; .task_family == "implementation" and .improved_alignment == true and .shadow_policy_decision_class == "auto-continue")
' "${OUT}/shadow-policy-comparison.json" >/dev/null

jq -e '
  .metrics_version == "beagle-policy-rollout-metrics-v1" and
  .rollout_stage == "shadow-compared" and
  .candidate_false_auto_continue_rate_basis_points == 0 and
  .candidate_false_review_required_rate_basis_points < .current_false_review_required_rate_basis_points and
  .improved_alignment_count >= 1 and
  .regression_count == 0 and
  any(.family_metrics[]; .task_family == "implementation" and .rollout_readiness == "guarded-canary-ready") and
  any(.family_metrics[]; .task_family == "analysis" and .rollout_readiness == "keep-current-control") and
  any(.family_metrics[]; .task_family == "manuscript" and .rollout_readiness == "hold-review-or-block")
' "${OUT}/rollout-metrics.json" >/dev/null

jq -e '
  .decision_version == "beagle-guarded-rollout-decision-v1" and
  .recommended_action == "stage-guarded-canary-for-implementation" and
  .current_policy_preserved_as_control == true and
  .candidate_policy_shadow_mode == true and
  .guarded_enablement_permitted == true and
  .guarded_enablement_live == false and
  .global_policy_update_permitted == false and
  any(.safe_task_families_to_move_first[]; . == "implementation") and
  any(.current_control_task_families[]; . == "analysis") and
  any(.staged_guarded_task_families[]; . == "implementation") and
  any(.blocked_or_hold_task_families[]; . == "manuscript") and
  .regression_detected == false and
  .rollback_required == false and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  .same_beagle_owned_identity == true
' "${OUT}/rollout-decision.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-canary-staged" and
  (.packet.retrieval_context.execution.latest_guarded_rollout_decision_id | length) > 0
' "${OUT}/context-after-rollout.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_rollout_status == "implementation-canary-staged" and
  (.latest_autonomy_policy_current_id | length) > 0 and
  (.latest_autonomy_policy_candidate_id | length) > 0 and
  (.latest_rollout_metrics_id | length) > 0 and
  (.latest_guarded_rollout_decision_id | length) > 0
' "${OUT}/execution-state-after-rollout.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_rollout_status == "implementation-canary-staged" and
  (.latest_guarded_rollout_decision_id | length) > 0
' "${OUT}/execution-receipt-after-rollout.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-current") and
  any(.links[]; .link_kind == "autonomy-policy-candidate") and
  any(.links[]; .link_kind == "rollout-metrics") and
  any(.links[]; .link_kind == "guarded-rollout-decision")
' "${OUT}/execution-result-links-after-rollout.json" >/dev/null

jq -e '
  .phase == "B24.8" and
  .rollout_stage == "shadow-plus-staged-implementation-canary" and
  .recommended_action == "stage-guarded-canary-for-implementation" and
  .guarded_enablement_permitted == true and
  .guarded_enablement_live == false and
  .global_policy_update_permitted == false and
  .candidate_false_auto_continue_rate_basis_points == 0 and
  .candidate_false_review_required_rate_basis_points < .current_false_review_required_rate_basis_points and
  .improved_alignment_count >= 1 and
  .regression_count == 0 and
  .implementation_guarded_ready == true and
  .analysis_held_current == true and
  .manuscript_held_back == true and
  .rollback_ready == true and
  .context_rollout_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_rollout_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] shadow threshold rollout smoke artifacts validated"
