#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-alignment-signal}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/manuscript-alignment-labels.json" \
  "${OUT}/manuscript-promotion-evidence.json" \
  "${OUT}/manuscript-promotion-gate.json" \
  "${OUT}/context-after-manuscript-alignment-signal.json" \
  "${OUT}/execution-state-after-manuscript-alignment-signal.json" \
  "${OUT}/execution-receipt-after-manuscript-alignment-signal.json" \
  "${OUT}/execution-result-links-after-manuscript-alignment-signal.json" \
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
  .manuscript_alignment_signal_contract_present == 1 and
  .manuscript_promotion_evidence_contract_present == 1 and
  .autonomy_calibration_source_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_reflection_source_present == 1 and
  .review_decision_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b2416_artifacts_present == 1 and
  .prior_b2415_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .labels_version == "beagle-manuscript-alignment-signal-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-alignment-signal" and
  .shadow_sample_count >= 4 and
  .operator_alignment_labeled_count > 0 and
  .execution_outcome_alignment_labeled_count > 0 and
  .same_beagle_owned_identity == true and
  (.labels | length) == .shadow_sample_count and
  ([.labels[] | select(.sample_source | endswith("+b2417-alignment-signal"))] | length) > 0 and
  all(.labels[];
    .observation_id != null and
    .sample_id != null and
    .operator_alignment_label != null and
    .execution_outcome_alignment_label != null and
    .review_quality_label != null and
    .promotion_readiness_label != null and
    (.operator_alignment_label == "aligned" or .operator_alignment_label == "misaligned" or .operator_alignment_label == "insufficient-evidence") and
    (.execution_outcome_alignment_label == "aligned" or .execution_outcome_alignment_label == "misaligned" or .execution_outcome_alignment_label == "insufficient-evidence") and
    (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
    (.promotion_readiness_label == "supports-stage-manuscript-canary" or .promotion_readiness_label == "keep-shadow" or .promotion_readiness_label == "rollback-shadow")
  )
' "${OUT}/manuscript-alignment-labels.json" >/dev/null

jq -e '
  .evidence_version == "beagle-manuscript-promotion-evidence-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-alignment-signal" and
  .shadow_sample_count >= 4 and
  .operator_alignment_labeled_count > 0 and
  .execution_outcome_alignment_labeled_count > 0 and
  .operator_alignment_label_coverage_basis_points > 0 and
  .execution_outcome_alignment_label_coverage_basis_points > 0 and
  .operator_alignment_basis_points > 0 and
  .execution_outcome_alignment_basis_points > 0 and
  (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
  (.promotion_readiness_label == "supports-stage-manuscript-canary" or .promotion_readiness_label == "keep-shadow" or .promotion_readiness_label == "rollback-shadow") and
  (.promotion_ready_count + .promotion_hold_count + .promotion_block_count) == .shadow_sample_count and
  .same_beagle_owned_identity == true
' "${OUT}/manuscript-promotion-evidence.json" >/dev/null

jq -e '
  .gate_version == "beagle-manuscript-promotion-gate-recheck-v1" and
  .rollout_stage == "implementation-and-analysis-canary-live-manuscript-alignment-signal" and
  .minimum_shadow_sample_count == 4 and
  .shadow_sample_count >= .minimum_shadow_sample_count and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .manuscript_alignment_labels_id != null and
  .manuscript_promotion_evidence_id != null and
  .operator_alignment_labeled_count > 0 and
  .execution_outcome_alignment_labeled_count > 0 and
  .operator_alignment_label_coverage_basis_points > 0 and
  .execution_outcome_alignment_label_coverage_basis_points > 0 and
  (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
  (.promotion_readiness_label == "supports-stage-manuscript-canary" or .promotion_readiness_label == "keep-shadow" or .promotion_readiness_label == "rollback-shadow") and
  .same_beagle_owned_identity == true and
  (.rollback_trigger | length) > 0 and
  (.rollback_action | length) > 0 and
  (.rationale | length) > 0 and
  (if .promotion_criteria_met
   then .promotion_gate_decision == "stage-manuscript-canary" and .promotion_evidence_sufficient == true and .hold_or_rollback_required == false
   else (.promotion_gate_decision == "keep-shadow" or .promotion_gate_decision == "rollback-shadow") and .hold_or_rollback_required == true
   end)
' "${OUT}/manuscript-promotion-gate.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.autonomy_policy_calibration_status == "manuscript-alignment-signal-acquired" and
  .packet.retrieval_context.execution.autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/context-after-manuscript-alignment-signal.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .autonomy_policy_calibration_status == "manuscript-alignment-signal-acquired" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live" and
  .current_state == "succeeded"
' "${OUT}/execution-state-after-manuscript-alignment-signal.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .autonomy_policy_calibration_status == "manuscript-alignment-signal-acquired" and
  .autonomy_policy_rollout_status == "implementation-and-analysis-canary-live"
' "${OUT}/execution-receipt-after-manuscript-alignment-signal.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy-manuscript-control") and
  any(.links[]; .link_kind == "autonomy-policy-manuscript-candidate") and
  any(.links[]; .link_kind == "manuscript-shadow-comparison") and
  any(.links[]; .link_kind == "manuscript-rollout-metrics") and
  any(.links[]; .link_kind == "manuscript-rollout-decision") and
  any(.links[]; .link_kind == "manuscript-shadow-history") and
  any(.links[]; .link_kind == "manuscript-soak-metrics") and
  any(.links[]; .link_kind == "manuscript-alignment-labels") and
  any(.links[]; .link_kind == "manuscript-promotion-evidence") and
  any(.links[]; .link_kind == "manuscript-promotion-gate")
' "${OUT}/execution-result-links-after-manuscript-alignment-signal.json" >/dev/null

jq -e '
  .phase == "B24.17" and
  (.promotion_gate_decision == "keep-shadow" or .promotion_gate_decision == "stage-manuscript-canary" or .promotion_gate_decision == "rollback-shadow") and
  .shadow_sample_count >= 4 and
  .additional_shadow_samples_accumulated > 0 and
  .operator_alignment_labeled_count > 0 and
  .execution_outcome_alignment_labeled_count > 0 and
  .operator_alignment_label_coverage_basis_points > 0 and
  .execution_outcome_alignment_label_coverage_basis_points > 0 and
  (.review_quality_label == "operator-ready" or .review_quality_label == "needs-edit" or .review_quality_label == "replan-required") and
  (.promotion_readiness_label == "supports-stage-manuscript-canary" or .promotion_readiness_label == "keep-shadow" or .promotion_readiness_label == "rollback-shadow") and
  .implementation_canary_retained == true and
  .analysis_canary_retained == true and
  .gate_consumes_alignment_labels == true and
  .explicit_alignment_labels_present == true and
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

echo "[OK] manuscript alignment signal smoke artifacts validated"
