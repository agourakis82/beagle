#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/plan-execution-orchestrator}"

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
  "${OUT}/execution-state.json" \
  "${OUT}/execution-receipt.json" \
  "${OUT}/execution-result-links.json" \
  "${OUT}/context-after-execution.json" \
  "${OUT}/program-context-after-execution.json" \
  "${OUT}/tool-claude-code-after-execution.json" \
  "${OUT}/workspace-subagent-route-after-execution.json" \
  "${OUT}/workspace-subagent-handoff-after-execution.json" \
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
  .state_contract_present == 1 and
  .receipt_contract_present == 1 and
  .approval_contract_present == 1 and
  .plan_execution_source_present == 1 and
  .execution_state_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .workstream_cockpit_source_present == 1 and
  .subagent_routing_source_present == 1 and
  .subagent_handoff_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_planner_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .plan_version == "beagle-execution-plan-v1" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .task_family == "analysis" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .recipe_target.recipe_kind == "operator_cpu_loop" and
  .experiment_target.experiment_id == "beagle_exp_002_hrv_aware_vs_blind"
' "${OUT}/execution-plan.json" >/dev/null

jq -e '
  .approval_version == "beagle-plan-approval-v1" and
  .approval_state == "approved" and
  .approved_by == "beagle-operator" and
  .operator_visibility_confirmed == true and
  .operator_execution_state == "operator-visible-bounded"
' "${OUT}/execution-approval.json" >/dev/null

jq -e '
  .state_version == "beagle-plan-execution-state-v1" and
  .current_state == "succeeded" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .recipe_kind == "operator_cpu_loop" and
  .experiment_id == "beagle_exp_002_hrv_aware_vs_blind" and
  (.state_transitions | length) >= 4 and
  any(.state_transitions[]; .state == "approved") and
  any(.state_transitions[]; .state == "running") and
  any(.state_transitions[]; .state == "succeeded")
' "${OUT}/execution-state.json" >/dev/null

jq -e '
  .receipt_version == "beagle-plan-execution-receipt-v1" and
  .final_state == "succeeded" and
  .selected_subagent_id == "experiments" and
  .result_link_count >= 7 and
  .handoff_updated == true and
  .handoff_ref == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff" and
  .operator_execution_state == "operator-visible-bounded"
' "${OUT}/execution-receipt.json" >/dev/null

jq -e '
  .links_version == "beagle-plan-execution-result-links-v1" and
  (.links | length) >= 7 and
  any(.links[]; .link_kind == "context-packet") and
  any(.links[]; .link_kind == "tool-launch") and
  any(.links[]; .link_kind == "workspace-subagent-route") and
  any(.links[]; .link_kind == "workspace-subagent-handoff") and
  any(.links[]; .link_kind == "experiment-spec") and
  any(.links[]; .link_kind == "experiment-results")
' "${OUT}/execution-result-links.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.execution.current_state == "succeeded" and
  .packet.retrieval_context.execution.selected_subagent_id == "experiments"
' "${OUT}/context-after-execution.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.execution.current_state == "succeeded"
' "${OUT}/program-context-after-execution.json" >/dev/null

jq -e '
  .tool.tool_id == "claude-code" and
  .tool.execution.current_state == "succeeded" and
  .tool.execution.selected_subagent_id == "experiments" and
  .tool.plan_execution_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/plan-execution"
' "${OUT}/tool-claude-code-after-execution.json" >/dev/null

jq -e '
  .route.selection.selected_subagent_id == "experiments" and
  .route.execution.current_state == "succeeded" and
  .route.execution.selected_subagent_id == "experiments"
' "${OUT}/workspace-subagent-route-after-execution.json" >/dev/null

jq -e '
  .handoff.target_subagent_id == "experiments" and
  .propagation.execution_state_present == true and
  .propagation.execution_plan_id == .context_packet.retrieval_context.execution.plan_id and
  .propagation.execution_current_state == "succeeded" and
  (.propagation.execution_receipt_id | length) > 0
' "${OUT}/workspace-subagent-handoff-after-execution.json" >/dev/null

jq -e '
  .execution_id == input.execution_id and
  .current_state == "succeeded" and
  .session_id == "ws-cluster-workspace-habitat"
' "${OUT}/execution-state-reread.json" "${OUT}/execution-state.json" >/dev/null

jq -e '
  .phase == "B24.2" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .current_state == "succeeded" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .recipe_kind == "operator_cpu_loop" and
  .experiment_id == "beagle_exp_002_hrv_aware_vs_blind" and
  .approval_state == "approved" and
  .receipt_final_state == "succeeded" and
  .result_link_count >= 7 and
  .handoff_updated == true and
  .planner_artifacts_present == 1 and
  .context_execution_present == true and
  .program_execution_present == true and
  .tool_execution_present == true and
  .route_execution_present == true and
  .handoff_execution_present == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] plan execution orchestrator smoke artifacts validated"
