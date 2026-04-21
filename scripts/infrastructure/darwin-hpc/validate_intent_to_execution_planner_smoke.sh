#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/intent-to-execution-planner}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/planner-policy.json" \
  "${OUT}/intent-plan.json" \
  "${OUT}/execution-plan-implementation.json" \
  "${OUT}/execution-plan-analysis.json" \
  "${OUT}/execution-plan-manuscript.json" \
  "${OUT}/context-packet-with-planner.json" \
  "${OUT}/program-context-packet-with-planner.json" \
  "${OUT}/tool-codex.json" \
  "${OUT}/workspace-subagent-route-manuscript.json" \
  "${OUT}/execution-plan-analysis-after-restart.json" \
  "${OUT}/context-packet-with-planner-after-restart.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  require_file "${path}"
done

jq -e '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_program == "beagle-physio-symbolic-exocortex" and
  .expected_workspace == "beagle-cluster-pilot" and
  .expected_session == "ws-cluster-workspace-habitat" and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .intent_contract_present == 1 and
  .execution_contract_present == 1 and
  .acceptance_contract_present == 1 and
  .intent_planner_source_present == 1 and
  .execution_plan_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .workstream_cockpit_source_present == 1 and
  .subagent_routing_source_present == 1 and
  .http_darwin_source_present == 1 and
  .prior_compiler_artifacts_present == 1 and
  .prior_eval_artifacts_present == 1 and
  .prior_temporal_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .policy_version == "beagle-intent-planner-policy-v1" and
  .policy_id == "b241-intent-planner-policy" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  (.profiles | length) >= 4 and
  any(.supported_task_families[]; . == "implementation") and
  any(.supported_task_families[]; . == "analysis") and
  any(.supported_task_families[]; . == "manuscript") and
  any(.profiles[]; .task_family == "implementation" and .recommended_subagent_id == "core" and .retrieval_query_type == "code" and .compiler_profile_id == "b235-budget-implementation" and .graphrag_query_mode == "local") and
  any(.profiles[]; .task_family == "analysis" and .recommended_subagent_id == "experiments" and .retrieval_query_type == "general" and .compiler_profile_id == "b235-budget-analysis" and .graphrag_query_mode == "global") and
  any(.profiles[]; .task_family == "manuscript" and .recommended_subagent_id == "manuscript" and .retrieval_query_type == "general" and .compiler_profile_id == "b235-budget-manuscript" and .graphrag_query_mode == "global")
' "${OUT}/planner-policy.json" >/dev/null

jq -e '
  .intent_version == "beagle-intent-plan-v1" and
  .task_family == "implementation" and
  .tool_id == "codex" and
  .work_mode == "implementation" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .operator_execution_state == "operator-visible-bounded"
' "${OUT}/intent-plan.json" >/dev/null

jq -e '
  .plan_version == "beagle-execution-plan-v1" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .task_family == "implementation" and
  .selected_subagent_id == "core" and
  .retrieval_query_type == "code" and
  .dense_backend == "voyage-code-3" and
  .sparse_backend == "local-lexical" and
  .compiler_profile_id == "b235-budget-implementation" and
  .graphrag_query_mode == "local" and
  .temporal_truth_view == "current" and
  .recipe_target.recipe_kind == "repo_native_dev_loop" and
  (.expected_outputs | length) >= 3 and
  (.success_criteria | length) >= 2 and
  (.stop_conditions | length) >= 2
' "${OUT}/execution-plan-implementation.json" >/dev/null

jq -e '
  .plan_version == "beagle-execution-plan-v1" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .task_family == "analysis" and
  .selected_subagent_id == "experiments" and
  .retrieval_query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .recipe_target.recipe_kind == "operator_cpu_loop" and
  (.experiment_target.experiment_id | length) > 0 and
  (.expected_outputs | length) >= 3 and
  (.success_criteria | length) >= 2 and
  (.stop_conditions | length) >= 3
' "${OUT}/execution-plan-analysis.json" >/dev/null

jq -e '
  .plan_version == "beagle-execution-plan-v1" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .task_family == "manuscript" and
  .selected_subagent_id == "manuscript" and
  .retrieval_query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .compiler_profile_id == "b235-budget-manuscript" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .recipe_target.recipe_kind == "repo_native_dev_loop" and
  (.expected_outputs | length) >= 3 and
  (.success_criteria | length) >= 2 and
  any(.stop_conditions[]; contains("claim-linked-human-eval-pending"))
' "${OUT}/execution-plan-manuscript.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.retrieval_context.planner.planner_policy_id == "b241-intent-planner-policy" and
  .packet.retrieval_context.planner.intent_planner_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/intent-plan" and
  (.packet.retrieval_context.planner.supported_task_families | length) >= 4
' "${OUT}/context-packet-with-planner.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.planner.planner_policy_id == "b241-intent-planner-policy" and
  (.packet.retrieval_context.planner.supported_task_families | length) >= 4
' "${OUT}/program-context-packet-with-planner.json" >/dev/null

jq -e '
  .tool.tool_id == "codex" and
  .tool.compiled_context_present == true and
  .tool.compiled_context_task_profile == "implementation" and
  .tool.compiled_context_budget_profile_id == "b235-budget-implementation" and
  .tool.planner.planner_policy_id == "b241-intent-planner-policy" and
  .tool.planner.task_family_hint == "implementation"
' "${OUT}/tool-codex.json" >/dev/null

jq -e '
  .status == "ok" and
  .route.selection.requested_work_mode == "manuscript" and
  .route.selection.selected_subagent_id == "manuscript" and
  .route.planner.planner_policy_id == "b241-intent-planner-policy" and
  .route.planner.task_family_hint == "manuscript"
' "${OUT}/workspace-subagent-route-manuscript.json" >/dev/null

jq -e '
  .plan_version == "beagle-execution-plan-v1" and
  .task_family == "analysis" and
  .selected_subagent_id == "experiments" and
  .compiler_profile_id == "b235-budget-analysis" and
  .graphrag_query_mode == "global"
' "${OUT}/execution-plan-analysis-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.retrieval_context.planner.planner_policy_id == "b241-intent-planner-policy"
' "${OUT}/context-packet-with-planner-after-restart.json" >/dev/null

jq -e '
  .phase == "B24.1" and
  .planner_policy_id == "b241-intent-planner-policy" and
  .planner_policy_profile_count >= 4 and
  .implementation_selected_subagent_id == "core" and
  .implementation_retrieval_query_type == "code" and
  .implementation_compiler_profile_id == "b235-budget-implementation" and
  .implementation_graphrag_query_mode == "local" and
  .analysis_selected_subagent_id == "experiments" and
  .analysis_retrieval_query_type == "general" and
  .analysis_compiler_profile_id == "b235-budget-analysis" and
  .analysis_graphrag_query_mode == "global" and
  .analysis_recipe_kind == "operator_cpu_loop" and
  .manuscript_selected_subagent_id == "manuscript" and
  .manuscript_retrieval_query_type == "general" and
  .manuscript_compiler_profile_id == "b235-budget-manuscript" and
  .manuscript_graphrag_query_mode == "global" and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] intent-to-execution planner smoke artifacts validated"
