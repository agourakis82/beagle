#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/analysis-shadow-calibration}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/autonomy-policy-control.json" \
  "${OUT}/autonomy-policy-analysis-candidate.json" \
  "${OUT}/analysis-shadow-comparison.json" \
  "${OUT}/analysis-rollout-metrics.json" \
  "${OUT}/analysis-rollout-decision.json" \
  "${OUT}/context-after-analysis-shadow.json" \
  "${OUT}/execution-state-after-analysis-shadow.json" \
  "${OUT}/execution-receipt-after-analysis-shadow.json" \
  "${OUT}/execution-result-links-after-analysis-shadow.json" \
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
  .analysis_shadow_contract_present == 1 and
  .analysis_metric_contract_present == 1 and
  .analysis_decision_contract_present == 1 and
  .autonomy_policy_source_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b249_artifacts_present == 1 and
  .prior_b248_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_role == "control-live" and
  .rollout_stage == "implementation-canary-live" and
  .guarded_enablement_live == false and
  any(.policy_family_scope[]; . == "analysis") and
  any(.policy_family_scope[]; . == "manuscript")
' "${OUT}/autonomy-policy-control.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_role == "analysis-shadow-candidate" and
  .rollout_stage == "analysis-shadow" and
  .guarded_enablement_live == false and
  .control_policy_id != null and
  .source_threshold_id != null and
  .policy_family_scope == ["analysis"] and
  any(.auto_continue_task_families[]; . == "analysis")
' "${OUT}/autonomy-policy-analysis-candidate.json" >/dev/null

jq -e '
  .calibration_version == "beagle-analysis-shadow-calibration-v1" and
  .rollout_stage == "implementation-canary-live-analysis-shadow" and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .compared_sample_count >= 1 and
  .regression_count == 0 and
  .recommendation_for_analysis == "keep-shadow"
' "${OUT}/analysis-shadow-comparison.json" >/dev/null

jq -e '
  .metrics_version == "beagle-analysis-rollout-metrics-v1" and
  .rollout_stage == "implementation-canary-live-analysis-shadow" and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .regression_count == 0 and
  .recommendation_for_analysis == "keep-shadow" and
  any(.family_metrics[]; .task_family == "implementation" and .live_policy_role == "implementation-canary-live" and .canary_retained == true and .shadow_evaluated == false) and
  any(.family_metrics[]; .task_family == "analysis" and .live_policy_role == "control-live" and .shadow_policy_role == "analysis-shadow-candidate" and .control_retained == true and .shadow_evaluated == true and .recommendation_for_analysis == "keep-shadow") and
  any(.family_metrics[]; .task_family == "manuscript" and .live_policy_role == "control-live" and .control_retained == true and .shadow_evaluated == false)
' "${OUT}/analysis-rollout-metrics.json" >/dev/null

jq -e '
  .decision_version == "beagle-analysis-rollout-decision-v1" and
  .rollout_stage == "implementation-canary-live-analysis-shadow" and
  .decision_output == "keep-shadow" and
  .analysis_shadow_active == true and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .regression_detected == false and
  .rollback_required == false and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  .same_beagle_owned_identity == true
' "${OUT}/analysis-rollout-decision.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "analysis-shadow-evaluated" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-canary-live"
' "${OUT}/context-after-analysis-shadow.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "analysis-shadow-evaluated" and
  .autonomy_policy_rollout_status == "implementation-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-analysis-shadow.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "analysis-shadow-evaluated" and
  .autonomy_policy_rollout_status == "implementation-canary-live"
' "${OUT}/execution-receipt-after-analysis-shadow.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-control") and
  any(.links[]; .link_kind == "autonomy-policy-analysis-candidate") and
  any(.links[]; .link_kind == "analysis-shadow-comparison") and
  any(.links[]; .link_kind == "analysis-rollout-metrics") and
  any(.links[]; .link_kind == "analysis-rollout-decision")
' "${OUT}/execution-result-links-after-analysis-shadow.json" >/dev/null

jq -e '
  .phase == "B24.10" and
  .decision_output == "keep-shadow" and
  .recommendation_for_analysis == "keep-shadow" and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .control_policy_visible == true and
  .analysis_candidate_visible == true and
  .context_calibration_visible == true and
  .context_rollout_visible == true and
  .execution_summary_calibration_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_analysis_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] analysis shadow calibration smoke artifacts validated"
