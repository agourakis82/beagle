#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/analysis-canary-activation}"

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
  "${OUT}/autonomy-policy-implementation-canary.json" \
  "${OUT}/autonomy-policy-analysis-canary.json" \
  "${OUT}/analysis-canary-metrics.json" \
  "${OUT}/analysis-canary-rollback-decision.json" \
  "${OUT}/continuation-state-after-analysis-canary.json" \
  "${OUT}/context-after-analysis-canary.json" \
  "${OUT}/execution-state-after-analysis-canary.json" \
  "${OUT}/execution-receipt-after-analysis-canary.json" \
  "${OUT}/execution-result-links-after-analysis-canary.json" \
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
  .analysis_canary_activation_contract_present == 1 and
  .analysis_canary_metric_contract_present == 1 and
  .analysis_canary_rollback_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .approval_gate_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b2412_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_role == "control-live" and
  .rollout_stage == "implementation-and-analysis-canary-live" and
  .guarded_enablement_live == false and
  .policy_family_scope == ["manuscript"] and
  (.auto_continue_task_families | length) == 0
' "${OUT}/autonomy-policy-control.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_role == "implementation-canary-live" and
  .rollout_stage == "implementation-and-analysis-canary-live" and
  .guarded_enablement_live == true and
  .control_policy_id != null and
  .source_threshold_id != null and
  .policy_family_scope == ["implementation"] and
  .auto_continue_task_families == ["implementation"]
' "${OUT}/autonomy-policy-implementation-canary.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_role == "analysis-canary-live" and
  .rollout_stage == "implementation-and-analysis-canary-live" and
  .guarded_enablement_live == true and
  .control_policy_id != null and
  .source_threshold_id != null and
  .policy_family_scope == ["analysis"] and
  .auto_continue_task_families == ["analysis"] and
  any(.auto_continue_subagent_ids[]; . == "experiments") and
  any(.auto_continue_allowed_review_actions[]; . == "edited")
' "${OUT}/autonomy-policy-analysis-canary.json" >/dev/null

jq -e '
  .metrics_version == "beagle-analysis-canary-metrics-v1" and
  .canary_stage == "implementation-and-analysis-canary-live" and
  .analysis_sample_count >= 4 and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .rollback_triggered == false and
  .implementation_canary_retained == true and
  .analysis_canary_live == true and
  .manuscript_control_retained == true and
  any(.family_metrics[]; .task_family == "implementation" and .live_policy_role == "implementation-canary-live" and .canary_enabled == true) and
  any(.family_metrics[]; .task_family == "analysis" and .live_policy_role == "analysis-canary-live" and .canary_enabled == true and .rollback_triggered == false) and
  any(.family_metrics[]; .task_family == "manuscript" and .live_policy_role == "control-live" and .control_retained == true)
' "${OUT}/analysis-canary-metrics.json" >/dev/null

jq -e '
  .decision_version == "beagle-analysis-canary-rollback-v1" and
  .canary_stage == "implementation-and-analysis-canary-live" and
  .implementation_canary_retained == true and
  .analysis_canary_live == true and
  .manuscript_control_retained == true and
  .regression_detected == false and
  .rollback_required == false and
  .rollback_triggered == false and
  (.rollback_reason | length) > 0 and
  (.rollback_action | length) > 0 and
  .same_beagle_owned_identity == true
' "${OUT}/analysis-canary-rollback-decision.json" >/dev/null

jq -e '
  .state_version == "beagle-continuation-state-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  (.source_execution_id | length) > 0 and
  (.follow_on_plan_id | length) > 0
' "${OUT}/continuation-state-after-analysis-canary.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/context-after-analysis-canary.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-analysis-canary.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/execution-receipt-after-analysis-canary.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-analysis-control") and
  any(.links[]; .link_kind == "autonomy-policy-implementation-canary") and
  any(.links[]; .link_kind == "autonomy-policy-analysis-canary") and
  any(.links[]; .link_kind == "analysis-canary-metrics") and
  any(.links[]; .link_kind == "analysis-canary-rollback-decision")
' "${OUT}/execution-result-links-after-analysis-canary.json" >/dev/null

jq -e '
  .phase == "B24.13" and
  .canary_stage == "implementation-and-analysis-canary-live" and
  .analysis_sample_count >= 4 and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .rollback_triggered == false and
  .implementation_canary_retained == true and
  .analysis_canary_live == true and
  .manuscript_control_retained == true and
  .control_policy_visible == true and
  .implementation_canary_visible == true and
  .analysis_canary_visible == true and
  .context_rollout_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_canary_visible == true and
  .continuation_identity_preserved == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] analysis canary activation smoke artifacts validated"
