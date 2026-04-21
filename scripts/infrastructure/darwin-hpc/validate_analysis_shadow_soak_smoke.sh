#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/analysis-shadow-soak}"

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
  "${OUT}/context-after-analysis-soak.json" \
  "${OUT}/execution-state-after-analysis-soak.json" \
  "${OUT}/execution-receipt-after-analysis-soak.json" \
  "${OUT}/execution-result-links-after-analysis-soak.json" \
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
  .analysis_shadow_soak_contract_present == 1 and
  .analysis_soak_metric_contract_present == 1 and
  .analysis_promotion_gate_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b2410_artifacts_present == 1 and
  .prior_b249_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .soak_version == "beagle-analysis-shadow-soak-v1" and
  .rollout_stage == "implementation-canary-live-analysis-shadow-soak" and
  .shadow_sample_count >= 1 and
  .rolling_window_size >= .shadow_sample_count and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  (.history | length) == .shadow_sample_count and
  all(.history[]; .observation_id != null and .sample_id != null)
' "${OUT}/analysis-shadow-history.json" >/dev/null

jq -e '
  .metrics_version == "beagle-analysis-soak-metrics-v1" and
  .rollout_stage == "implementation-canary-live-analysis-shadow-soak" and
  .shadow_sample_count >= 1 and
  .false_auto_continue_rate_basis_points == 0 and
  .false_review_required_rate_basis_points == 0 and
  .regression_count == 0 and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .promotion_gate_decision_preview == "keep-shadow"
' "${OUT}/analysis-soak-metrics.json" >/dev/null

jq -e '
  .gate_version == "beagle-analysis-promotion-gate-v1" and
  .rollout_stage == "implementation-canary-live-analysis-shadow-soak" and
  .minimum_shadow_sample_count == 4 and
  .shadow_sample_count >= 1 and
  .promotion_gate_decision == "keep-shadow" and
  .promotion_criteria_met == false and
  .implementation_canary_retained == true and
  .manuscript_control_retained == true and
  .hold_or_rollback_required == true and
  .same_beagle_owned_identity == true and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  (.rationale | length) > 0
' "${OUT}/analysis-promotion-gate.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "analysis-shadow-soaked" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-canary-live"
' "${OUT}/context-after-analysis-soak.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "analysis-shadow-soaked" and
  .autonomy_policy_rollout_status == "implementation-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-analysis-soak.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "analysis-shadow-soaked" and
  .autonomy_policy_rollout_status == "implementation-canary-live"
' "${OUT}/execution-receipt-after-analysis-soak.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-control") and
  any(.links[]; .link_kind == "autonomy-policy-canary") and
  any(.links[]; .link_kind == "analysis-shadow-history") and
  any(.links[]; .link_kind == "analysis-soak-metrics") and
  any(.links[]; .link_kind == "analysis-promotion-gate")
' "${OUT}/execution-result-links-after-analysis-soak.json" >/dev/null

jq -e '
  .phase == "B24.11" and
  .promotion_gate_decision == "keep-shadow" and
  .shadow_sample_count >= 1 and
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
  .result_links_soak_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] analysis shadow soak smoke artifacts validated"
