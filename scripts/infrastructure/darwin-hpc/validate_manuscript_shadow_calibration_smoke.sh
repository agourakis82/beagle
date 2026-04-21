#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-shadow-calibration}"

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
  "${OUT}/autonomy-policy-manuscript-candidate.json" \
  "${OUT}/manuscript-shadow-comparison.json" \
  "${OUT}/manuscript-rollout-metrics.json" \
  "${OUT}/manuscript-rollout-decision.json" \
  "${OUT}/context-after-manuscript-shadow.json" \
  "${OUT}/execution-state-after-manuscript-shadow.json" \
  "${OUT}/execution-receipt-after-manuscript-shadow.json" \
  "${OUT}/execution-result-links-after-manuscript-shadow.json" \
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
  .manuscript_shadow_contract_present == 1 and
  .manuscript_metric_contract_present == 1 and
  .manuscript_decision_contract_present == 1 and
  .autonomy_policy_source_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b2413_artifacts_present == 1 and
  .prior_b2410_artifacts_present == 1
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
  .policy_role == "manuscript-shadow-candidate" and
  .rollout_stage == "manuscript-shadow" and
  .guarded_enablement_live == false and
  .control_policy_id != null and
  .source_threshold_id != null and
  .policy_family_scope == ["manuscript"]
' "${OUT}/autonomy-policy-manuscript-candidate.json" >/dev/null

jq -e '
  .calibration_version == "beagle-manuscript-shadow-calibration-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-shadow" and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .compared_sample_count >= 1 and
  .regression_count == 0 and
  .recommendation_for_manuscript == "keep-shadow"
' "${OUT}/manuscript-shadow-comparison.json" >/dev/null

jq -e '
  .metrics_version == "beagle-manuscript-rollout-metrics-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-shadow" and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .regression_count == 0 and
  .recommendation_for_manuscript == "keep-shadow" and
  any(.family_metrics[]; .task_family == "implementation" and .live_policy_role == "implementation-canary-live" and .canary_retained == true and .shadow_evaluated == false) and
  any(.family_metrics[]; .task_family == "analysis" and .live_policy_role == "analysis-canary-live" and .canary_retained == true and .shadow_evaluated == false) and
  any(.family_metrics[]; .task_family == "manuscript" and .live_policy_role == "control-live" and .shadow_policy_role == "manuscript-shadow-candidate" and .control_retained == true and .shadow_evaluated == true and .recommendation_for_manuscript == "keep-shadow")
' "${OUT}/manuscript-rollout-metrics.json" >/dev/null

jq -e '
  .decision_version == "beagle-manuscript-rollout-decision-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-shadow" and
  .decision_output == "keep-shadow" and
  .manuscript_shadow_active == true and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .regression_detected == false and
  .rollback_required == false and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-rollout-decision.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-shadow-evaluated" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/context-after-manuscript-shadow.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "manuscript-shadow-evaluated" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-manuscript-shadow.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "manuscript-shadow-evaluated" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/execution-receipt-after-manuscript-shadow.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-manuscript-control") and
  any(.links[]; .link_kind == "autonomy-policy-manuscript-candidate") and
  any(.links[]; .link_kind == "manuscript-shadow-comparison") and
  any(.links[]; .link_kind == "manuscript-rollout-metrics") and
  any(.links[]; .link_kind == "manuscript-rollout-decision")
' "${OUT}/execution-result-links-after-manuscript-shadow.json" >/dev/null

jq -e '
  .phase == "B24.14" and
  .decision_output == "keep-shadow" and
  .recommendation_for_manuscript == "keep-shadow" and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .control_policy_visible == true and
  .manuscript_candidate_visible == true and
  .context_calibration_visible == true and
  .context_rollout_visible == true and
  .execution_summary_calibration_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_manuscript_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] manuscript shadow calibration smoke artifacts validated"
