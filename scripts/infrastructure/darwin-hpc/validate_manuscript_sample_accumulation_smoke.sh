#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-sample-accumulation}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/manuscript-shadow-history.json" \
  "${OUT}/manuscript-soak-metrics.json" \
  "${OUT}/manuscript-promotion-gate.json" \
  "${OUT}/context-after-manuscript-sample-accumulation.json" \
  "${OUT}/execution-state-after-manuscript-sample-accumulation.json" \
  "${OUT}/execution-receipt-after-manuscript-sample-accumulation.json" \
  "${OUT}/execution-result-links-after-manuscript-sample-accumulation.json" \
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
  .manuscript_sample_accumulation_contract_present == 1 and
  .manuscript_promotion_gate_recheck_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b2414_artifacts_present == 1 and
  .prior_b2413_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .accumulation_version == "beagle-manuscript-sample-accumulation-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-sample-accumulation" and
  .prior_shadow_sample_count >= 1 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count == (.prior_shadow_sample_count + .additional_shadow_sample_count) and
  .shadow_sample_count >= 4 and
  .rolling_window_size >= .shadow_sample_count and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  (.history | length) == .shadow_sample_count and
  all(.history[]; .observation_id != null and .sample_id != null and .sample_source != null)
' "${OUT}/manuscript-shadow-history.json" >/dev/null

jq -e '
  .metrics_version == "beagle-manuscript-soak-metrics-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-sample-accumulation" and
  .prior_shadow_sample_count >= 1 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count >= 4 and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  (.promotion_gate_decision_preview == "keep-shadow" or .promotion_gate_decision_preview == "stage-manuscript-canary")
' "${OUT}/manuscript-soak-metrics.json" >/dev/null

jq -e '
  .gate_version == "beagle-manuscript-promotion-gate-recheck-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-sample-accumulation" and
  .minimum_shadow_sample_count == 4 and
  .prior_shadow_sample_count >= 1 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count >= .minimum_shadow_sample_count and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .same_beagle_owned_identity == true and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  (.rationale | length) > 0 and
  (if .promotion_criteria_met
   then .promotion_gate_decision == "stage-manuscript-canary" and .hold_or_rollback_required == false
   else .promotion_gate_decision == "keep-shadow" and .hold_or_rollback_required == true
   end)
' "${OUT}/manuscript-promotion-gate.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-shadow-rechecked" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/context-after-manuscript-sample-accumulation.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "manuscript-shadow-rechecked" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-manuscript-sample-accumulation.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "manuscript-shadow-rechecked" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/execution-receipt-after-manuscript-sample-accumulation.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-manuscript-control") and
  any(.links[]; .link_kind == "autonomy-policy-manuscript-candidate") and
  any(.links[]; .link_kind == "manuscript-shadow-comparison") and
  any(.links[]; .link_kind == "manuscript-rollout-metrics") and
  any(.links[]; .link_kind == "manuscript-rollout-decision") and
  any(.links[]; .link_kind == "manuscript-shadow-history") and
  any(.links[]; .link_kind == "manuscript-soak-metrics") and
  any(.links[]; .link_kind == "manuscript-promotion-gate")
' "${OUT}/execution-result-links-after-manuscript-sample-accumulation.json" >/dev/null

jq -e '
  .phase == "B24.15" and
  .prior_shadow_sample_count >= 1 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count >= .minimum_shadow_sample_count and
  .crossed_minimum_threshold == true and
  (.promotion_gate_decision == "keep-shadow" or .promotion_gate_decision == "stage-manuscript-canary") and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .promotion_gate_preview_matches == true and
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

echo "[OK] manuscript sample accumulation smoke artifacts validated"
