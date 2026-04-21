#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/memory-promotion-graphrag-modes}"

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
  "${OUT}/promotion-policy.json" \
  "${OUT}/retention-policy.json" \
  "${OUT}/graphrag-query-mode.json" \
  "${OUT}/promoted-memory.json" \
  "${OUT}/context-packet-with-promoted-memory.json" \
  "${OUT}/program-context-packet-with-promoted-memory.json" \
  "${OUT}/promoted-memory-after-restart.json" \
  "${OUT}/context-packet-with-promoted-memory-after-restart.json" \
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
  .promotion_source_present == 1 and
  .retention_source_present == 1 and
  .graphrag_mode_source_present == 1 and
  .engine_source_present == 1 and
  .memory_lib_source_present == 1 and
  .core_context_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .http_memory_source_present == 1 and
  .http_darwin_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .promotion_contract_present == 1 and
  .retention_contract_present == 1 and
  .graphrag_mode_contract_present == 1 and
  .prior_graphrag_artifacts_present == 1 and
  .prior_feedback_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .policy_version == "beagle-memory-promotion-policy-v1" and
  .policy_id == "b232-memory-promotion-policy" and
  (.rules | length) == 2 and
  any(.rules[]; .source_memory_type == "episodic" and .target_memory_type == "semantic") and
  any(.rules[]; .source_memory_type == "episodic" and .target_memory_type == "procedural")
' "${OUT}/promotion-policy.json" >/dev/null

jq -e '
  .policy_version == "beagle-memory-retention-policy-v1" and
  .policy_id == "b232-memory-retention-policy" and
  (.rules | length) == 3 and
  any(.rules[]; .memory_type == "episodic" and .retention_action == "expire-or-compact") and
  any(.rules[]; .memory_type == "semantic" and .retention_action == "retain-active-campaign-window") and
  any(.rules[]; .memory_type == "procedural" and .retention_action == "retain-until-superseded")
' "${OUT}/retention-policy.json" >/dev/null

jq -e '
  .mode_version == "beagle-graphrag-query-mode-v1" and
  .policy_id == "b232-graphrag-query-mode-policy" and
  .query_mode == "drift" and
  (.classifier_source | length) > 0 and
  (.classifier_reason | length) > 0 and
  (.effective_top_k >= 4) and
  (.effective_max_hops >= 2)
' "${OUT}/graphrag-query-mode.json" >/dev/null

jq -e '
  .promotion_version == "beagle-promoted-memory-v1" and
  .policy_id == "b232-memory-promotion-policy" and
  .source_memory_type == "episodic" and
  (.target_memory_type == "semantic" or .target_memory_type == "procedural") and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .session_id == "ws-cluster-workspace-habitat" and
  (.supporting_refs | length) >= 1 and
  (.retention_action | length) > 0
' "${OUT}/promoted-memory.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.promotion_policy_id == "b232-memory-promotion-policy" and
  .packet.retrieval_context.retention_policy_id == "b232-memory-retention-policy" and
  ((.packet.retrieval_context.graphrag_query_mode == "local") or (.packet.retrieval_context.graphrag_query_mode == "global") or (.packet.retrieval_context.graphrag_query_mode == "drift")) and
  (.packet.retrieval_context.promoted_memory_count // 0) >= 1 and
  ((.packet.retrieval_context.promoted_target_memory_types // []) | length) >= 1
' "${OUT}/context-packet-with-promoted-memory.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.promotion_policy_id == "b232-memory-promotion-policy" and
  .packet.retrieval_context.retention_policy_id == "b232-memory-retention-policy" and
  ((.packet.retrieval_context.graphrag_query_mode == "local") or (.packet.retrieval_context.graphrag_query_mode == "global") or (.packet.retrieval_context.graphrag_query_mode == "drift"))
' "${OUT}/program-context-packet-with-promoted-memory.json" >/dev/null

jq -e --slurpfile before "${OUT}/promoted-memory.json" '
  .promotion_version == "beagle-promoted-memory-v1" and
  .source_memory_id == $before[0].source_memory_id and
  .target_memory_type == $before[0].target_memory_type
' "${OUT}/promoted-memory-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.promotion_policy_id == "b232-memory-promotion-policy" and
  ((.packet.retrieval_context.graphrag_query_mode // "") | length) > 0
' "${OUT}/context-packet-with-promoted-memory-after-restart.json" >/dev/null

jq -e '
  .phase == "B23.2" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .promotion_policy_id == "b232-memory-promotion-policy" and
  .retention_policy_id == "b232-memory-retention-policy" and
  .drift_query_mode == "drift" and
  .context_packet_contains_policy == true and
  .context_packet_contains_mode == true and
  .context_packet_contains_promotion == true and
  .program_context_contains_policy == true and
  .promoted_memory_in_scope == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-reranker" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] memory promotion / graphrag mode smoke artifacts validated\n'
