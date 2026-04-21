#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/review-to-dispatch-continuation}"

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
  "${OUT}/continuation-dispatch.json" \
  "${OUT}/continuation-receipt.json" \
  "${OUT}/continuation-state.json" \
  "${OUT}/context-after-continuation.json" \
  "${OUT}/program-context-after-continuation.json" \
  "${OUT}/workspace-subagent-handoff-after-continuation.json" \
  "${OUT}/execution-state-after-continuation.json" \
  "${OUT}/execution-receipt-after-continuation.json" \
  "${OUT}/execution-result-links-after-continuation.json" \
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
  .continuation_dispatch_contract_present == 1 and
  .continuation_receipt_contract_present == 1 and
  .continuation_state_contract_present == 1 and
  .plan_execution_source_present == 1 and
  .continuation_dispatch_source_present == 1 and
  .continuation_state_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .subagent_handoff_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_review_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .suggestion_version == "beagle-replan-suggestion-v1" and
  .requested_operator_action == "review-and-approve-follow-on-plan"
' "${OUT}/replan-suggestion-source.json" >/dev/null

jq -e '
  .inbox_version == "beagle-review-inbox-item-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .inbox_state == "approved"
' "${OUT}/review-inbox-item.json" >/dev/null

jq -e '
  .decision_version == "beagle-review-decision-v1" and
  .decision_action == "approved" and
  .follow_on_plan_materialized == true
' "${OUT}/review-decision.json" >/dev/null

jq -e '
  .follow_on_plan_version == "beagle-follow-on-plan-v1" and
  .review_action == "approved" and
  .follow_on_state == "dispatched" and
  .execution_plan.selected_subagent_id == "experiments" and
  .execution_plan.retrieval_query_type == "general" and
  .execution_plan.compiler_profile_id == "b235-budget-analysis" and
  .execution_plan.graphrag_query_mode == "global" and
  .execution_plan.temporal_truth_view == "both"
' "${OUT}/follow-on-plan.json" >/dev/null

jq -e '
  .dispatch_version == "beagle-continuation-dispatch-v1" and
  .review_action == "approved" and
  .dispatch_state == "dispatched" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .next_selected_subagent_id == "experiments" and
  .next_retrieval_query_type == "general" and
  .next_compiler_profile_id == "b235-budget-analysis" and
  .next_graphrag_query_mode == "global" and
  .next_temporal_truth_view == "both"
' "${OUT}/continuation-dispatch.json" >/dev/null

jq -e '
  .receipt_version == "beagle-continuation-receipt-v1" and
  .review_action == "approved" and
  (.chained_receipt_ids | length) == 2 and
  .handoff_updated == true and
  .next_execution_receipt.final_state == "succeeded" and
  .next_execution_receipt.selected_subagent_id == "experiments" and
  (.next_execution_result_links.links | length) >= 8
' "${OUT}/continuation-receipt.json" >/dev/null

jq -e '
  .state_version == "beagle-continuation-state-v1" and
  .review_action == "approved" and
  .continuation_depth == 1 and
  .current_state == "succeeded" and
  (.chained_receipt_ids | length) == 2 and
  .next_execution_state.current_state == "succeeded" and
  .next_execution_state.selected_subagent_id == "experiments" and
  .next_execution_state.retrieval_query_type == "general" and
  .next_execution_state.compiler_profile_id == "b235-budget-analysis" and
  .next_execution_state.graphrag_query_mode == "global" and
  .next_execution_state.temporal_truth_view == "both"
' "${OUT}/continuation-state.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.continuation_dispatched == true and
  .packet.retrieval_context.execution.continuation_current_state == "succeeded" and
  (.packet.retrieval_context.execution.latest_continuation_dispatch_id | length) > 0 and
  (.packet.retrieval_context.execution.latest_continuation_receipt_id | length) > 0 and
  .packet.retrieval_context.execution.operator_followup_action == "review-dispatched-continuation-results"
' "${OUT}/context-after-continuation.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.execution.continuation_dispatched == true and
  .packet.retrieval_context.execution.continuation_current_state == "succeeded"
' "${OUT}/program-context-after-continuation.json" >/dev/null

jq -e '
  .propagation.execution_state_present == true and
  .propagation.execution_follow_on_plan_available == true and
  .propagation.execution_continuation_dispatched == true and
  .propagation.execution_continuation_current_state == "succeeded" and
  (.propagation.execution_continuation_dispatch_id | length) > 0 and
  (.propagation.execution_continuation_receipt_id | length) > 0 and
  (.propagation.execution_continuation_next_execution_id | length) > 0
' "${OUT}/workspace-subagent-handoff-after-continuation.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .current_state == "succeeded" and
  .follow_on_plan_available == true and
  .continuation_dispatched == true and
  .continuation_current_state == "succeeded" and
  (.latest_continuation_dispatch_id | length) > 0 and
  (.latest_continuation_receipt_id | length) > 0 and
  (.continuation_next_execution_id | length) > 0 and
  .operator_followup_action == "review-dispatched-continuation-results"
' "${OUT}/execution-state-after-continuation.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .final_state == "succeeded" and
  .follow_on_plan_available == true and
  .continuation_dispatched == true and
  .continuation_current_state == "succeeded" and
  (.latest_continuation_dispatch_id | length) > 0 and
  (.latest_continuation_receipt_id | length) > 0 and
  .operator_followup_action == "review-dispatched-continuation-results"
' "${OUT}/execution-receipt-after-continuation.json" >/dev/null

jq -e '
  any(.links[]; .link_kind == "review-inbox-item") and
  any(.links[]; .link_kind == "review-decision") and
  any(.links[]; .link_kind == "follow-on-plan") and
  any(.links[]; .link_kind == "continuation-dispatch") and
  any(.links[]; .link_kind == "continuation-state") and
  any(.links[]; .link_kind == "continuation-receipt")
' "${OUT}/execution-result-links-after-continuation.json" >/dev/null

jq -e '
  .phase == "B24.5" and
  .review_action == "approved" and
  .dispatch_state == "dispatched" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .follow_on_state == "dispatched" and
  .continuation_current_state == "succeeded" and
  .next_execution_final_state == "succeeded" and
  .operator_followup_action == "review-dispatched-continuation-results" and
  .chained_receipt_count == 2 and
  .context_continuation_visible == true and
  .handoff_continuation_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] review-to-dispatch continuation smoke artifacts validated"
