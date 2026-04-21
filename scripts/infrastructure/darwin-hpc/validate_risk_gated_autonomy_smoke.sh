#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/risk-gated-autonomy}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/replan-suggestion-source.json" \
  "${OUT}/review-inbox-item.json" \
  "${OUT}/review-decision.json" \
  "${OUT}/follow-on-plan.json" \
  "${OUT}/autonomy-policy.json" \
  "${OUT}/risk-evaluation.json" \
  "${OUT}/approval-gating-decision.json" \
  "${OUT}/continuation-dispatch.json" \
  "${OUT}/continuation-receipt.json" \
  "${OUT}/continuation-state-after-gating.json" \
  "${OUT}/context-after-gating.json" \
  "${OUT}/program-context-after-gating.json" \
  "${OUT}/workspace-subagent-handoff-after-gating.json" \
  "${OUT}/execution-state-after-gating.json" \
  "${OUT}/execution-receipt-after-gating.json" \
  "${OUT}/execution-result-links-after-gating.json" \
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
  .autonomy_policy_contract_present == 1 and
  .risk_evaluation_contract_present == 1 and
  .approval_gating_decision_contract_present == 1 and
  .autonomy_policy_source_present == 1 and
  .risk_evaluation_source_present == 1 and
  .approval_gate_source_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_state_source_present == 1 and
  .workstream_context_source_present == 1 and
  .subagent_handoff_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_b243_artifacts_present == 1 and
  .prior_b245_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .suggestion_version == "beagle-replan-suggestion-v1"
' "${OUT}/replan-suggestion-source.json" >/dev/null

jq -e '
  .inbox_version == "beagle-review-inbox-item-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .approval_gating_decision_class == "auto-continue" and
  (.approval_gating_decision_id | length) > 0
' "${OUT}/review-inbox-item.json" >/dev/null

jq -e '
  .decision_version == "beagle-review-decision-v1" and
  .decision_action == "approved" and
  .follow_on_plan_materialized == true and
  .approval_gating_decision_class == "auto-continue" and
  .auto_continue_eligible == true and
  .dispatch_blocked == false
' "${OUT}/review-decision.json" >/dev/null

jq -e '
  .follow_on_plan_version == "beagle-follow-on-plan-v1" and
  .review_action == "approved" and
  .follow_on_state == "dispatched" and
  .approval_gating_decision_class == "auto-continue" and
  .execution_plan.selected_subagent_id == "experiments" and
  .execution_plan.retrieval_query_type == "general" and
  .execution_plan.compiler_profile_id == "b235-budget-analysis" and
  .execution_plan.graphrag_query_mode == "global" and
  .execution_plan.temporal_truth_view == "both"
' "${OUT}/follow-on-plan.json" >/dev/null

jq -e '
  .policy_version == "beagle-autonomy-policy-v1" and
  .policy_scope == "follow-on-plan-gating" and
  any(.allowed_decision_classes[]; . == "auto-continue") and
  any(.allowed_decision_classes[]; . == "review-required") and
  any(.allowed_decision_classes[]; . == "blocked")
' "${OUT}/autonomy-policy.json" >/dev/null

jq -e '
  .risk_evaluation_version == "beagle-risk-evaluation-v1" and
  .recommended_decision_class == "auto-continue" and
  .risk_level == "low" and
  .replan_required == false and
  .review_action == "approved"
' "${OUT}/risk-evaluation.json" >/dev/null

jq -e '
  .decision_version == "beagle-approval-gating-decision-v1" and
  .decision_class == "auto-continue" and
  .continuation_dispatch_permitted == true and
  .auto_continuation_enabled == true and
  .human_review_required == false and
  .blocked == false and
  .follow_on_state_after_gating == "auto-continue-ready"
' "${OUT}/approval-gating-decision.json" >/dev/null

jq -e '
  .dispatch_version == "beagle-continuation-dispatch-v1" and
  .dispatch_state == "dispatched" and
  .approval_gating_decision_class == "auto-continue" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat"
' "${OUT}/continuation-dispatch.json" >/dev/null

jq -e '
  .receipt_version == "beagle-continuation-receipt-v1" and
  .review_action == "approved" and
  (.chained_receipt_ids | length) == 2 and
  .next_execution_receipt.final_state == "succeeded"
' "${OUT}/continuation-receipt.json" >/dev/null

jq -e '
  .state_version == "beagle-continuation-state-v1" and
  .review_action == "approved" and
  .current_state == "succeeded" and
  .next_execution_state.current_state == "succeeded"
' "${OUT}/continuation-state-after-gating.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.approval_gating_decision_class == "auto-continue" and
  .packet.retrieval_context.execution.approval_gating_dispatch_ready == true and
  .packet.retrieval_context.execution.approval_gating_blocked == false and
  .packet.retrieval_context.execution.continuation_dispatched == true
' "${OUT}/context-after-gating.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.execution.approval_gating_decision_class == "auto-continue"
' "${OUT}/program-context-after-gating.json" >/dev/null

jq -e '
  .propagation.execution_approval_gating_decision_class == "auto-continue" and
  .propagation.execution_approval_gating_dispatch_ready == true and
  .propagation.execution_approval_gating_blocked == false and
  .propagation.execution_continuation_dispatched == true
' "${OUT}/workspace-subagent-handoff-after-gating.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .approval_gating_decision_class == "auto-continue" and
  .approval_gating_dispatch_ready == true and
  .approval_gating_blocked == false and
  .continuation_dispatched == true and
  .continuation_current_state == "succeeded"
' "${OUT}/execution-state-after-gating.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .approval_gating_decision_class == "auto-continue" and
  .approval_gating_dispatch_ready == true and
  .approval_gating_blocked == false and
  .continuation_dispatched == true
' "${OUT}/execution-receipt-after-gating.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "autonomy-policy") and
  any(.links[]; .link_kind == "risk-evaluation") and
  any(.links[]; .link_kind == "approval-gating-decision") and
  any(.links[]; .link_kind == "continuation-dispatch") and
  any(.links[]; .link_kind == "continuation-state") and
  any(.links[]; .link_kind == "continuation-receipt")
' "${OUT}/execution-result-links-after-gating.json" >/dev/null

jq -e '
  .phase == "B24.6" and
  .decision_class == "auto-continue" and
  .risk_level == "low" and
  .review_action == "approved" and
  .follow_on_state == "dispatched" and
  .dispatch_state == "dispatched" and
  .selected_subagent_id == "experiments" and
  .operator_followup_action == "review-dispatched-continuation-results" and
  .continuation_current_state == "succeeded" and
  .context_gate_visible == true and
  .handoff_gate_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] risk-gated autonomy smoke artifacts validated"
