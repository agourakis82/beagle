#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/execution-reflection}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/execution-plan.json" \
  "${OUT}/execution-approval.json" \
  "${OUT}/execution-state-after-reflection.json" \
  "${OUT}/execution-reflection.json" \
  "${OUT}/trajectory-eval.json" \
  "${OUT}/replan-suggestion.json" \
  "${OUT}/execution-receipt-after-reflection.json" \
  "${OUT}/context-after-reflection.json" \
  "${OUT}/program-context-after-reflection.json" \
  "${OUT}/tool-claude-code-after-reflection.json" \
  "${OUT}/workspace-subagent-handoff-after-reflection.json" \
  "${OUT}/execution-state-reread.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  require_file "${path}"
done

jq -e '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_program == "beagle-physio-symbolic-exocortex" and
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_workspace == "beagle-cluster-pilot" and
  .expected_session == "ws-cluster-workspace-habitat" and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .reflection_contract_present == 1 and
  .trajectory_contract_present == 1 and
  .replan_contract_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_state_source_present == 1 and
  .execution_reflection_source_present == 1 and
  .trajectory_eval_source_present == 1 and
  .replan_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .subagent_handoff_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_execution_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .plan_version == "beagle-execution-plan-v1" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .task_family == "analysis" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both"
' "${OUT}/execution-plan.json" >/dev/null

jq -e '
  .approval_version == "beagle-plan-approval-v1" and
  .approval_state == "approved" and
  .operator_visibility_confirmed == true and
  .operator_execution_state == "operator-visible-bounded"
' "${OUT}/execution-approval.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .current_state == "succeeded" and
  .selected_subagent_id == "experiments" and
  .latest_reflection_id == input.reflection_id and
  .latest_trajectory_eval_id == input.trajectory_eval_id and
  .latest_replan_suggestion_id == input.suggestion_id and
  .latest_quality_score >= 85 and
  .latest_trajectory_quality == "good" and
  .replan_required == false and
  .operator_followup_action == "review-and-approve-follow-on-plan"
' "${OUT}/execution-state-after-reflection.json" "${OUT}/execution-reflection.json" "${OUT}/trajectory-eval.json" "${OUT}/replan-suggestion.json" >/dev/null

jq -e '
  .reflection_version == "beagle-execution-reflection-v1" and
  .selected_subagent_id == "experiments" and
  .expected_subagent_id == "experiments" and
  .subagent_selection_ok == true and
  .compiled_context_sufficient == true and
  .acceptance_criteria_passed == true and
  .evaluation_mode == "deterministic-bounded-reflection" and
  .overall_quality_score >= 85 and
  .operator_followup_action == "review-and-approve-next-plan"
' "${OUT}/execution-reflection.json" >/dev/null

jq -e '
  .trajectory_eval_version == "beagle-trajectory-eval-v1" and
  .evaluation_mode == "deterministic-trajectory-match" and
  .lifecycle_match == true and
  (.observed_states | length) >= 4 and
  any(.observed_states[]; . == "planned") and
  any(.observed_states[]; . == "approved") and
  any(.observed_states[]; . == "running") and
  any(.observed_states[]; . == "succeeded") and
  .acceptance_criteria_met_count == .acceptance_criteria_total and
  .compiled_context_sufficient == true and
  .trajectory_quality == "good" and
  .trajectory_score >= 85
' "${OUT}/trajectory-eval.json" >/dev/null

jq -e '
  .suggestion_version == "beagle-replan-suggestion-v1" and
  .replan_required == false and
  .request_operator_review == true and
  .request_operator_approval_again == true and
  .requested_operator_action == "review-and-approve-follow-on-plan" and
  .suggested_subagent_id == "experiments" and
  .suggested_retrieval_query_type == "general" and
  .suggested_compiler_profile_id == "b235-budget-analysis" and
  .suggested_graphrag_query_mode == "global" and
  .suggested_temporal_truth_view == "both" and
  any(.suggested_changes[]; contains("Request operator approval again"))
' "${OUT}/replan-suggestion.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .final_state == "succeeded" and
  .reflection_id == input.reflection_id and
  .trajectory_eval_id == input.trajectory_eval_id and
  .replan_suggestion_id == input.suggestion_id and
  .quality_score >= 85 and
  .trajectory_quality == "good" and
  .replan_required == false and
  .operator_followup_action == "review-and-approve-follow-on-plan"
' "${OUT}/execution-receipt-after-reflection.json" "${OUT}/execution-reflection.json" "${OUT}/trajectory-eval.json" "${OUT}/replan-suggestion.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.current_state == "succeeded" and
  .packet.retrieval_context.execution.reflection_available == true and
  (.packet.retrieval_context.execution.latest_reflection_id | length) > 0 and
  .packet.retrieval_context.execution.latest_quality_score >= 85 and
  .packet.retrieval_context.execution.latest_trajectory_quality == "good" and
  .packet.retrieval_context.execution.replan_required == false and
  .packet.retrieval_context.execution.operator_followup_action == "review-and-approve-follow-on-plan"
' "${OUT}/context-after-reflection.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.execution.reflection_available == true and
  .packet.retrieval_context.execution.latest_quality_score >= 85
' "${OUT}/program-context-after-reflection.json" >/dev/null

jq -e '
  .tool.tool_id == "claude-code" and
  .tool.execution.current_state == "succeeded" and
  .tool.execution.reflection_available == true and
  .tool.execution.latest_quality_score >= 85 and
  .tool.execution.operator_followup_action == "review-and-approve-follow-on-plan"
' "${OUT}/tool-claude-code-after-reflection.json" >/dev/null

jq -e '
  .handoff.target_subagent_id == "experiments" and
  .propagation.execution_state_present == true and
  .propagation.execution_reflection_present == true and
  .propagation.execution_quality_score >= 85 and
  .propagation.execution_replan_required == false and
  .propagation.execution_operator_followup_action == "review-and-approve-follow-on-plan"
' "${OUT}/workspace-subagent-handoff-after-reflection.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .current_state == "succeeded" and
  (.latest_reflection_id | length) > 0 and
  (.latest_trajectory_eval_id | length) > 0 and
  (.latest_replan_suggestion_id | length) > 0 and
  .latest_quality_score >= 85 and
  .latest_trajectory_quality == "good"
' "${OUT}/execution-state-reread.json" >/dev/null

jq -e '
  .phase == "B24.3" and
  .current_state == "succeeded" and
  .selected_subagent_id == "experiments" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .trajectory_quality == "good" and
  .trajectory_score >= 85 and
  .overall_quality_score >= 85 and
  .replan_required == false and
  .requested_operator_action == "review-and-approve-follow-on-plan" and
  .operator_followup_action == "review-and-approve-next-plan" and
  .reflection_present == true and
  .handoff_reflection_present == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] execution reflection smoke artifacts validated"
