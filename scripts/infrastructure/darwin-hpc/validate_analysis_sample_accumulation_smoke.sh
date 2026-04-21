#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/analysis-sample-accumulation}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/analysis-shadow-history.json" \
  "${OUT}/analysis-soak-metrics.json" \
  "${OUT}/analysis-promotion-gate.json" \
  "${OUT}/context-after-analysis-sample-accumulation.json" \
  "${OUT}/execution-state-after-analysis-sample-accumulation.json" \
  "${OUT}/execution-receipt-after-analysis-sample-accumulation.json" \
  "${OUT}/execution-result-links-after-analysis-sample-accumulation.json" \
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
  .analysis_sample_accumulation_contract_present == 1 and
  .analysis_soak_metric_contract_present == 1 and
  .analysis_promotion_gate_recheck_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b2411_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .soak_version == "beagle-analysis-sample-accumulation-v1" and
  .rollout_stage == "implementation-canary-live-analysis-sample-accumulation" and
  .prior_shadow_sample_count >= 2 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count == (.prior_shadow_sample_count + .additional_shadow_sample_count) and
  .rolling_window_size >= .shadow_sample_count and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  (.history | length) == .shadow_sample_count and
  all(.history[]; .observation_id != null and .sample_id != null)
' "${OUT}/analysis-shadow-history.json" >/dev/null

jq -e '
  .metrics_version == "beagle-analysis-soak-metrics-v1" and
  .rollout_stage == "implementation-canary-live-analysis-sample-accumulation" and
  .prior_shadow_sample_count >= 2 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count >= 4 and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .promotion_gate_decision_preview == "stage-analysis-canary"
' "${OUT}/analysis-soak-metrics.json" >/dev/null

jq -e '
  .gate_version == "beagle-analysis-promotion-gate-recheck-v1" and
  .rollout_stage == "implementation-canary-live-analysis-sample-accumulation" and
  .minimum_shadow_sample_count == 4 and
  .prior_shadow_sample_count >= 2 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count >= .minimum_shadow_sample_count and
  .promotion_gate_decision == "stage-analysis-canary" and
  .promotion_criteria_met == true and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .hold_or_rollback_required == false and
  .same_beagle_owned_identity == true and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  (.rationale | length) > 0
' "${OUT}/analysis-promotion-gate.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "analysis-shadow-rechecked" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-canary-live"
' "${OUT}/context-after-analysis-sample-accumulation.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "analysis-shadow-rechecked" and
  .autonomy_policy_rollout_status == "implementation-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-analysis-sample-accumulation.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "analysis-shadow-rechecked" and
  .autonomy_policy_rollout_status == "implementation-canary-live"
' "${OUT}/execution-receipt-after-analysis-sample-accumulation.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-control") and
  any(.links[]; .link_kind == "autonomy-policy-canary") and
  any(.links[]; .link_kind == "analysis-shadow-history") and
  any(.links[]; .link_kind == "analysis-sample-accumulation") and
  any(.links[]; .link_kind == "analysis-sample-accumulation-metrics") and
  any(.links[]; .link_kind == "analysis-promotion-gate-recheck")
' "${OUT}/execution-result-links-after-analysis-sample-accumulation.json" >/dev/null

jq -e '
  .phase == "B24.12" and
  .promotion_gate_decision == "stage-analysis-canary" and
  .prior_shadow_sample_count >= 2 and
  .additional_shadow_sample_count >= 1 and
  .shadow_sample_count >= .minimum_shadow_sample_count and
  .promotion_criteria_met == true and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .promotion_gate_preview_matches == true and
  .context_calibration_visible == true and
  .context_rollout_visible == true and
  .execution_summary_calibration_visible == true and
  .execution_summary_rollout_visible == true and
  .result_links_accumulation_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] analysis sample accumulation smoke artifacts validated"
