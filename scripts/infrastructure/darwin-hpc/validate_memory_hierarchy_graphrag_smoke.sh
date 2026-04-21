#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/memory-hierarchy-graphrag}"

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
  "${OUT}/memory-hierarchy.json" \
  "${OUT}/graphrag-query.json" \
  "${OUT}/graphrag-result.json" \
  "${OUT}/graphrag-result-after-restart.json" \
  "${OUT}/context-packet-with-graphrag.json" \
  "${OUT}/context-packet-with-graphrag-after-restart.json" \
  "${OUT}/program-context-packet-with-graphrag.json" \
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
  .expected_general_dense == "voyage-4-large" and
  .expected_sparse == "local-lexical" and
  .engine_source_present == 1 and
  .retrieval_source_present == 1 and
  .memory_lib_source_present == 1 and
  .core_context_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .http_memory_source_present == 1 and
  .http_darwin_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .hierarchy_contract_present == 1 and
  .node_contract_present == 1 and
  .edge_contract_present == 1 and
  .query_contract_present == 1 and
  .prior_feedback_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .hierarchy_version == "beagle-memory-hierarchy-v1" and
  .policy_id == "b231-memory-hierarchy-policy" and
  .collection_name == "beagle_memory_local" and
  (.buckets | length) == 3 and
  any(.buckets[]; .memory_type == "episodic" and .count >= 1) and
  any(.buckets[]; .memory_type == "semantic" and .count >= 1) and
  any(.buckets[]; .memory_type == "procedural" and .count >= 1)
' "${OUT}/memory-hierarchy.json" >/dev/null

jq -e '
  .query_version == "beagle-graphrag-query-v1" and
  .query_type_hint == "general" and
  .root_entity_type == "workstream" and
  .root_entity_id == "beagle-darwin-hpc-governance" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .include_memory_hierarchy == true and
  .filters.workstream_id == "beagle-darwin-hpc-governance" and
  .filters.campaign_id == "expedition-002-hrv-aware" and
  .filters.session_id == "ws-cluster-workspace-habitat" and
  (.filters.tags | length) == 1
' "${OUT}/graphrag-query.json" >/dev/null

jq -e '
  .result_version == "beagle-graphrag-result-v1" and
  .query_type == "general" and
  .collection_name == "beagle_memory_local" and
  .routing_decision.selected_route == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .root_entity_type == "workstream" and
  .root_entity_id == "beagle-darwin-hpc-governance" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .campaign_id == "expedition-002-hrv-aware" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .session_id == "ws-cluster-workspace-habitat" and
  (.support_memory_ids | length) >= 3 and
  .node_count >= 8 and
  .edge_count >= 7 and
  (.memory_hierarchy.buckets | length) == 3 and
  any(.nodes[]; .node_type == "Program") and
  any(.nodes[]; .node_type == "Campaign") and
  any(.nodes[]; .node_type == "Workstream") and
  any(.nodes[]; .node_type == "Session") and
  any(.nodes[]; .node_type == "Experiment") and
  any(.nodes[]; .node_type == "Result") and
  any(.nodes[]; .node_type == "Claim") and
  any(.nodes[]; .node_type == "Manuscript") and
  any(.edges[]; .edge_type == "contains") and
  any(.edges[]; .edge_type == "uses") and
  any(.edges[]; .edge_type == "belongs_to") and
  any(.edges[]; .edge_type == "runs") and
  any(.edges[]; .edge_type == "yields") and
  any(.edges[]; .edge_type == "supports") and
  any(.edges[]; .edge_type == "appears_in")
' "${OUT}/graphrag-result.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  (.packet.retrieval_context.graphrag_node_count // 0) > 0 and
  (.packet.retrieval_context.graphrag_edge_count // 0) > 0 and
  (.packet.retrieval_context.memory_hierarchy_counts | length) >= 1
' "${OUT}/context-packet-with-graphrag.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  (.packet.retrieval_context.graphrag_node_count // 0) > 0 and
  (.packet.retrieval_context.graphrag_edge_count // 0) > 0 and
  (.packet.retrieval_context.memory_hierarchy_counts | length) >= 1
' "${OUT}/program-context-packet-with-graphrag.json" >/dev/null

jq -e '
  .session_id == "ws-cluster-workspace-habitat" and
  (.node_count // 0) > 0 and
  (.edge_count // 0) > 0
' "${OUT}/graphrag-result-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  (.packet.retrieval_context.graphrag_node_count // 0) > 0
' "${OUT}/context-packet-with-graphrag-after-restart.json" >/dev/null

jq -e '
  .phase == "B23.1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .routing_selected_route == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .node_count >= 8 and
  .edge_count >= 7 and
  .hierarchy_bucket_count == 3 and
  .episodic_count >= 1 and
  .semantic_count >= 1 and
  .procedural_count >= 1 and
  .payload_filters_preserved == true and
  .context_packet_contains_graphrag == true and
  .program_context_contains_graphrag == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-reranker" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] memory hierarchy GraphRAG smoke artifacts validated\n'
