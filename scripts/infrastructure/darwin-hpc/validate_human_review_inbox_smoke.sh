#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/human-review-inbox}"

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
  "${OUT}/review-inbox-item-reread.json" \
  "${OUT}/review-decision.json" \
  "${OUT}/review-decision-reread.json" \
  "${OUT}/follow-on-plan.json" \
  "${OUT}/execution-state-after-review.json" \
  "${OUT}/execution-receipt-after-review.json" \
  "${OUT}/execution-result-links-after-review.json" \
  "${OUT}/context-after-review.json" \
  "${OUT}/program-context-after-review.json" \
  "${OUT}/workspace-subagent-handoff-after-review.json" \
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
  .review_inbox_contract_present == 1 and
  .review_decision_contract_present == 1 and
  .follow_on_plan_contract_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_state_source_present == 1 and
  .review_inbox_source_present == 1 and
  .review_decision_source_present == 1 and
  .follow_on_plan_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .workstream_cockpit_source_present == 1 and
  .subagent_handoff_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_reflection_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .suggestion_version == "beagle-replan-suggestion-v1" and
  .request_operator_review == true and
  .request_operator_approval_again == true and
  .requested_operator_action == "review-and-approve-follow-on-plan"
' "${OUT}/replan-suggestion-source.json" >/dev/null

jq -e '
  .inbox_version == "beagle-review-inbox-item-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .requested_operator_action == "review-and-approve-follow-on-plan" and
  .inbox_state == "pending-review" and
  .replan_required == false and
  .review_decision_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/review-inbox/decision" and
  .follow_on_plan_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/follow-on-plan"
' "${OUT}/review-inbox-item.json" >/dev/null

jq -n -e \
  --slurpfile reread "${OUT}/review-inbox-item-reread.json" \
  --slurpfile canonical "${OUT}/review-inbox-item.json" \
  '($reread[0].inbox_item_id == $canonical[0].inbox_item_id) and
   ($reread[0].execution_id == $canonical[0].execution_id) and
   ($reread[0].replan_suggestion_id == $canonical[0].replan_suggestion_id)' >/dev/null

jq -e '
  .decision_version == "beagle-review-decision-v1" and
  .decision_action == "approved" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .operator_visibility_confirmed == true and
  .follow_on_plan_materialized == true and
  (.follow_on_plan_id | length) > 0
' "${OUT}/review-decision.json" >/dev/null

jq -n -e \
  --slurpfile reread "${OUT}/review-decision-reread.json" \
  --slurpfile canonical "${OUT}/review-decision.json" \
  '($reread[0].decision_id == $canonical[0].decision_id) and
   ($reread[0].follow_on_plan_id == $canonical[0].follow_on_plan_id)' >/dev/null

jq -e '
  .follow_on_plan_version == "beagle-follow-on-plan-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .review_action == "approved" and
  .follow_on_state == "queued-for-approval" and
  .execution_plan.task_family == "analysis" and
  .execution_plan.selected_subagent_id == "experiments" and
  .execution_plan.retrieval_query_type == "general" and
  .execution_plan.dense_backend == "voyage-4-large" and
  .execution_plan.compiler_profile_id == "b235-budget-analysis" and
  .execution_plan.graphrag_query_mode == "global" and
  .execution_plan.temporal_truth_view == "both"
' "${OUT}/follow-on-plan.json" >/dev/null

jq -n -e \
  --slurpfile state "${OUT}/execution-state-after-review.json" \
  --slurpfile inbox "${OUT}/review-inbox-item.json" \
  --slurpfile decision "${OUT}/review-decision.json" \
  --slurpfile follow_on "${OUT}/follow-on-plan.json" \
  '($state[0].state_version == "beagle-plan-execution-state-v1") and
   ($state[0].current_state == "succeeded") and
   ($state[0].review_requested == false) and
   ($state[0].review_inbox_state == "approved") and
   ($state[0].latest_review_inbox_item_id == $inbox[0].inbox_item_id) and
   ($state[0].latest_review_decision_id == $decision[0].decision_id) and
   ($state[0].latest_review_decision_action == "approved") and
   ($state[0].latest_follow_on_plan_id == $follow_on[0].follow_on_plan_id) and
   ($state[0].follow_on_plan_available == true) and
   ($state[0].operator_followup_action == "approve-follow-on-plan-before-start")' >/dev/null

jq -n -e \
  --slurpfile receipt "${OUT}/execution-receipt-after-review.json" \
  --slurpfile inbox "${OUT}/review-inbox-item.json" \
  --slurpfile decision "${OUT}/review-decision.json" \
  --slurpfile follow_on "${OUT}/follow-on-plan.json" \
  '($receipt[0].receipt_version == "beagle-plan-execution-receipt-v1") and
   ($receipt[0].final_state == "succeeded") and
   ($receipt[0].review_requested == false) and
   ($receipt[0].review_inbox_state == "approved") and
   ($receipt[0].review_inbox_item_id == $inbox[0].inbox_item_id) and
   ($receipt[0].review_decision_id == $decision[0].decision_id) and
   ($receipt[0].follow_on_plan_id == $follow_on[0].follow_on_plan_id) and
   ($receipt[0].follow_on_plan_available == true) and
   ($receipt[0].operator_followup_action == "approve-follow-on-plan-before-start")' >/dev/null

jq -e '
  (.links | length) >= 8 and
  any(.links[]; .link_kind == "review-inbox-item") and
  any(.links[]; .link_kind == "review-decision") and
  any(.links[]; .link_kind == "follow-on-plan")
' "${OUT}/execution-result-links-after-review.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.execution.current_state == "succeeded" and
  .packet.retrieval_context.execution.review_requested == false and
  .packet.retrieval_context.execution.review_inbox_state == "approved" and
  .packet.retrieval_context.execution.latest_review_decision_action == "approved" and
  .packet.retrieval_context.execution.follow_on_plan_available == true and
  .packet.retrieval_context.execution.operator_followup_action == "approve-follow-on-plan-before-start"
' "${OUT}/context-after-review.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.execution.follow_on_plan_available == true and
  .packet.retrieval_context.execution.latest_review_decision_action == "approved"
' "${OUT}/program-context-after-review.json" >/dev/null

jq -e '
  .handoff.target_subagent_id == "experiments" and
  .propagation.execution_state_present == true and
  .propagation.execution_review_requested == false and
  .propagation.execution_review_inbox_state == "approved" and
  .propagation.execution_review_decision_action == "approved" and
  .propagation.execution_follow_on_plan_available == true and
  (.propagation.execution_follow_on_plan_id | length) > 0
' "${OUT}/workspace-subagent-handoff-after-review.json" >/dev/null

jq -e '
  .phase == "B24.4" and
  .decision_action == "approved" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .follow_on_state == "queued-for-approval" and
  .operator_followup_action == "approve-follow-on-plan-before-start" and
  .review_requested == false and
  .follow_on_plan_available == true and
  .result_link_count >= 8 and
  .context_review_visible == true and
  .handoff_review_visible == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] human review inbox smoke artifacts validated"
