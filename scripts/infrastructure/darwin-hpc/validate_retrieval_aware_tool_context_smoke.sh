#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/retrieval-aware-tool-context}"

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
  "${OUT}/retrieval-query.json" \
  "${OUT}/retrieval-result.json" \
  "${OUT}/workstream-context-packet.json" \
  "${OUT}/program-context-packet.json" \
  "${OUT}/campaign-context-packet.json" \
  "${OUT}/workspace-launch-resume.json" \
  "${OUT}/tool-claude-code.json" \
  "${OUT}/workspace-subagent-route.json" \
  "${OUT}/workspace-subagent-handoff-post.json" \
  "${OUT}/workspace-subagent-handoff.json" \
  "${OUT}/workstream-context-packet-after-restart.json" \
  "${OUT}/program-context-packet-after-restart.json" \
  "${OUT}/workspace-launch-resume-after-restart.json" \
  "${OUT}/tool-claude-code-after-restart.json" \
  "${OUT}/workspace-subagent-route-after-restart.json" \
  "${OUT}/workspace-subagent-handoff-after-restart.json" \
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
  .expected_dense_backend == "voyage-4-large" and
  .expected_sparse_backend == "local-lexical" and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .cockpit_source_present == 1 and
  .routing_source_present == 1 and
  .handoff_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .query_text | contains("manuscript claims evidence jats editorial")
' "${OUT}/retrieval-query.json" >/dev/null

jq -e '
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .top_k == 3 and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.program_id == "beagle-physio-symbolic-exocortex") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat") and
  all(.hits[]; .point.payload.source == "claude-code") and
  all(.hits[]; .point.payload.role == "assistant") and
  all(.hits[]; .point.payload.domain == "darwin-hpc") and
  all(.hits[]; (.point.payload.tags | index("b224")) != null)
' "${OUT}/retrieval-result.json" >/dev/null

jq -e '
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.dense_backend == "voyage-4-large" and
  .packet.retrieval_context.sparse_backend == "local-lexical" and
  .packet.retrieval_context.hit_count >= 1 and
  .packet.retrieval_context.suggested_subagent_id == "manuscript" and
  .packet.retrieval_context.suggested_work_mode == "manuscript" and
  (.packet.retrieval_context.top_memory_ids | length) >= 1
' "${OUT}/workstream-context-packet.json" >/dev/null

jq -e '
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.campaign_id == "expedition-002-hrv-aware" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.suggested_subagent_id == "manuscript"
' "${OUT}/program-context-packet.json" >/dev/null

jq -e '
  .packet.campaign_id == "expedition-002-hrv-aware" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.suggested_subagent_id == "manuscript"
' "${OUT}/campaign-context-packet.json" >/dev/null

jq -e '
  .context_packet.workstream_id == "beagle-darwin-hpc-governance" and
  .context_packet.retrieval_context != null and
  .context_packet.retrieval_context.suggested_subagent_id == "manuscript"
' "${OUT}/workspace-launch-resume.json" >/dev/null

jq -e '
  .tool.tool_id == "claude-code" and
  .tool.retrieval_context_present == true and
  .tool.retrieval_recommended_subagent_id == "manuscript" and
  .tool.recommended_subagent_id == "manuscript" and
  .tool.retrieval_recommended_work_mode == "manuscript" and
  .tool.recommended_work_mode == "manuscript"
' "${OUT}/tool-claude-code.json" >/dev/null

jq -e '
  .route.selection.selection_source == "retrieval-context" and
  .route.selection.selected_subagent_id == "manuscript" and
  .route.selection.selected_role_tag == "manuscript-authoring"
' "${OUT}/workspace-subagent-route.json" >/dev/null

jq -e '
  .handoff.source_subagent_id == "experiments" and
  .handoff.target_subagent_id == "manuscript" and
  .propagation.retrieval_context_present == true and
  .propagation.retrieval_suggested_subagent_id == "manuscript" and
  .propagation.retrieval_suggested_work_mode == "manuscript" and
  (.propagation.retrieval_memory_ids | length) >= 1
' "${OUT}/workspace-subagent-handoff-post.json" >/dev/null

jq -e '
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.suggested_subagent_id == "manuscript"
' "${OUT}/workstream-context-packet-after-restart.json" >/dev/null

jq -e '
  .packet.retrieval_context != null and
  .packet.retrieval_context.suggested_subagent_id == "manuscript"
' "${OUT}/program-context-packet-after-restart.json" >/dev/null

jq -e '
  .context_packet.retrieval_context != null and
  .context_packet.retrieval_context.suggested_subagent_id == "manuscript"
' "${OUT}/workspace-launch-resume-after-restart.json" >/dev/null

jq -e '
  .tool.retrieval_context_present == true and
  .tool.recommended_subagent_id == "manuscript"
' "${OUT}/tool-claude-code-after-restart.json" >/dev/null

jq -e '
  .route.selection.selection_source == "retrieval-context" and
  .route.selection.selected_subagent_id == "manuscript"
' "${OUT}/workspace-subagent-route-after-restart.json" >/dev/null

jq -e '
  .propagation.retrieval_context_present == true and
  .propagation.retrieval_suggested_subagent_id == "manuscript"
' "${OUT}/workspace-subagent-handoff-after-restart.json" >/dev/null

jq -e '
  .phase == "B22.4" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .retrieval_hit_count >= 1 and
  .workstream_retrieval_present == true and
  .program_retrieval_present == true and
  .launch_resume_retrieval_present == true and
  .tool_retrieval_context_present == true and
  .tool_recommended_subagent == "manuscript" and
  .route_selection_source == "retrieval-context" and
  .route_selected_subagent == "manuscript" and
  .handoff_retrieval_context_present == true and
  .handoff_retrieval_suggested_subagent == "manuscript" and
  .context_packet_contains_top_memory == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] retrieval-aware tool context smoke artifacts validated\n'
