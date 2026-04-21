#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/query-adaptive-memory-compiler}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require jq
require grep

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/memory-compiler.json" \
  "${OUT}/budget-profile-implementation.json" \
  "${OUT}/budget-profile-analysis.json" \
  "${OUT}/budget-profile-manuscript.json" \
  "${OUT}/compiled-context-implementation.json" \
  "${OUT}/compiled-context-analysis.json" \
  "${OUT}/compiled-context-manuscript.json" \
  "${OUT}/context-packet-with-compiled-context.json" \
  "${OUT}/program-context-packet-with-compiled-context.json" \
  "${OUT}/tool-codex.json" \
  "${OUT}/workspace-subagent-handoff.json" \
  "${OUT}/compiled-context-analysis-after-restart.json" \
  "${OUT}/context-packet-with-compiled-context-after-restart.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing artifact: ${path}" >&2
    exit 1
  }
done

jq -e '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_program == "beagle-physio-symbolic-exocortex" and
  .expected_workspace == "beagle-cluster-pilot" and
  .expected_session == "ws-cluster-workspace-habitat" and
  .compiler_source_present == 1 and
  .budgeting_source_present == 1 and
  .engine_source_present == 1 and
  .memory_lib_source_present == 1 and
  .core_context_source_present == 1 and
  .darwin_compiled_context_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .workstream_cockpit_source_present == 1 and
  .handoff_source_present == 1 and
  .http_memory_source_present == 1 and
  .http_darwin_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .memory_compiler_contract_present == 1 and
  .budget_profile_contract_present == 1 and
  .compiled_context_contract_present == 1 and
  .prior_promotion_artifacts_present == 1 and
  .prior_feedback_artifacts_present == 1 and
  .prior_temporal_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .compiler_version == "beagle-memory-compiler-v1" and
  .compiler_id == "b235-query-adaptive-memory-compiler" and
  (.supported_task_profiles | length) >= 4 and
  (.supported_memory_tiers | length) >= 3 and
  (.supported_graphrag_modes | length) >= 3 and
  (.supported_temporal_truth_views | length) >= 3 and
  (.supported_source_kinds | length) >= 5 and
  any(.supported_task_profiles[]; . == "implementation") and
  any(.supported_task_profiles[]; . == "analysis") and
  any(.supported_task_profiles[]; . == "manuscript")
' "${OUT}/memory-compiler.json" >/dev/null

jq -e '
  .profile_version == "beagle-context-budget-profile-v1" and
  .profile_id == "b235-budget-implementation" and
  .task_profile == "implementation" and
  .retrieval_query_type == "code" and
  .graphrag_query_mode_hint == "local" and
  .temporal_truth_view == "current" and
  .include_temporal_contradictions == true and
  .default_tool_id == "codex" and
  (.allocations | length) == 5 and
  any(.allocations[]; .source_kind == "temporal")
' "${OUT}/budget-profile-implementation.json" >/dev/null

jq -e '
  .profile_version == "beagle-context-budget-profile-v1" and
  .profile_id == "b235-budget-analysis" and
  .task_profile == "analysis" and
  .retrieval_query_type == "general" and
  .graphrag_query_mode_hint == "global" and
  .temporal_truth_view == "both" and
  .include_temporal_contradictions == true and
  .default_tool_id == "claude-code" and
  (.allocations | length) == 5 and
  any(.allocations[]; .source_kind == "temporal")
' "${OUT}/budget-profile-analysis.json" >/dev/null

jq -e '
  .profile_version == "beagle-context-budget-profile-v1" and
  .profile_id == "b235-budget-manuscript" and
  .task_profile == "manuscript" and
  .retrieval_query_type == "general" and
  .graphrag_query_mode_hint == "global" and
  .temporal_truth_view == "both" and
  .include_temporal_contradictions == true and
  .default_tool_id == "claude-code" and
  (.allocations | length) == 5 and
  any(.allocations[]; .source_kind == "temporal")
' "${OUT}/budget-profile-manuscript.json" >/dev/null

jq -e '
  .packet_version == "beagle-compiled-context-packet-v1" and
  .compiler_id == "b235-query-adaptive-memory-compiler" and
  .task_profile == "implementation" and
  .retrieval_query_type == "code" and
  .graphrag_query_mode == "local" and
  .temporal_truth_view == "current" and
  (.temporal_current_memory_ids | length) >= 1 and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  ((.selected_memory_tiers // []) | length) >= 3 and
  ((.source_slices // []) | length) >= 3 and
  any(.source_slices[]; .source_kind == "temporal") and
  ((.top_memory_ids // []) | length) >= 1 and
  ((.compiled_context_text // "") | contains("temporal_truth_view"))
' "${OUT}/compiled-context-implementation.json" >/dev/null

jq -e '
  .packet_version == "beagle-compiled-context-packet-v1" and
  .task_profile == "analysis" and
  .retrieval_query_type == "general" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .temporal_contradiction_count >= 1 and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  ((.source_slices // []) | length) >= 3 and
  any(.source_slices[]; .source_kind == "temporal")
' "${OUT}/compiled-context-analysis.json" >/dev/null

jq -e '
  .packet_version == "beagle-compiled-context-packet-v1" and
  .task_profile == "manuscript" and
  .retrieval_query_type == "general" and
  .graphrag_query_mode == "global" and
  .temporal_truth_view == "both" and
  .temporal_contradiction_count >= 1 and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  ((.selected_memory_tiers // []) | length) >= 3 and
  ((.source_slices // []) | length) >= 3 and
  any(.source_slices[]; .source_kind == "temporal")
' "${OUT}/compiled-context-manuscript.json" >/dev/null

jq -e --slurpfile impl "${OUT}/compiled-context-implementation.json" --slurpfile analysis "${OUT}/compiled-context-analysis.json" --slurpfile manuscript "${OUT}/compiled-context-manuscript.json" '
  $impl[0].budget_profile.profile_id != $analysis[0].budget_profile.profile_id and
  $analysis[0].budget_profile.profile_id != $manuscript[0].budget_profile.profile_id and
  $impl[0].retrieval_query_type != $analysis[0].retrieval_query_type and
  $impl[0].graphrag_query_mode != $analysis[0].graphrag_query_mode and
  $impl[0].temporal_truth_view != $analysis[0].temporal_truth_view
' "${OUT}/compiled-context-manuscript.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.compiled_context_task_profile == "analysis" and
  (.packet.retrieval_context.compiled_context_budget_profile_id | length) > 0 and
  (.packet.retrieval_context.compiled_context_retrieval_query_type | length) > 0 and
  (.packet.retrieval_context.compiled_context_graphrag_query_mode | length) > 0 and
  ((.packet.retrieval_context.compiled_context_top_memory_ids // []) | length) >= 1
' "${OUT}/context-packet-with-compiled-context.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.compiled_context_task_profile == "analysis" and
  (.packet.retrieval_context.compiled_context_budget_profile_id | length) > 0 and
  ((.packet.retrieval_context.compiled_context_top_memory_ids // []) | length) >= 1
' "${OUT}/program-context-packet-with-compiled-context.json" >/dev/null

jq -e '
  .tool.tool_id == "codex" and
  .tool.compiled_context_present == true and
  .tool.compiled_context_task_profile == "implementation" and
  .tool.compiled_context_budget_profile_id == "b235-budget-implementation" and
  ((.tool.compiled_context_top_memory_ids // []) | length) >= 1 and
  ((.tool.compiled_context_preview // "") | contains("temporal_truth_view"))
' "${OUT}/tool-codex.json" >/dev/null

jq -e '
  .status == "ok" and
  .handoff.workstream_id == "beagle-darwin-hpc-governance" and
  .handoff.workspace_id == "beagle-cluster-pilot" and
  .handoff.session_id == "ws-cluster-workspace-habitat" and
  .propagation.compiled_context_present == true and
  (.propagation.compiled_context_task_profile | length) > 0 and
  (.propagation.compiled_context_budget_profile_id | length) > 0 and
  ((.propagation.compiled_context_top_memory_ids // []) | length) >= 1
' "${OUT}/workspace-subagent-handoff.json" >/dev/null

jq -e '
  .packet_version == "beagle-compiled-context-packet-v1" and
  .task_profile == "analysis" and
  .temporal_truth_view == "both" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat"
' "${OUT}/compiled-context-analysis-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.compiled_context_task_profile == "analysis"
' "${OUT}/context-packet-with-compiled-context-after-restart.json" >/dev/null

jq -e '
  .phase == "B23.5" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .implementation_budget_profile_id == "b235-budget-implementation" and
  .analysis_budget_profile_id == "b235-budget-analysis" and
  .manuscript_budget_profile_id == "b235-budget-manuscript" and
  .implementation_query_type == "code" and
  .analysis_query_type == "general" and
  .manuscript_query_type == "general" and
  .implementation_graphrag_mode == "local" and
  .analysis_graphrag_mode == "global" and
  .manuscript_graphrag_mode == "global" and
  .implementation_temporal_truth_view == "current" and
  .analysis_temporal_truth_view == "both" and
  .manuscript_temporal_truth_view == "both" and
  (.analysis_temporal_contradiction_count >= 1) and
  (.manuscript_temporal_contradiction_count >= 1) and
  .context_packet_contains_compiled_context == true and
  .program_context_contains_compiled_context == true and
  .tool_launch_contains_compiled_context == true and
  .handoff_contains_compiled_context == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-reranker" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] query-adaptive memory compiler smoke artifacts validated\n'
