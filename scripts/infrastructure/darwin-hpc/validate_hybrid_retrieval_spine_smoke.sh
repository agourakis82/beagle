#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/hybrid-retrieval-spine}"

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
  "${OUT}/retrieval-collection.json" \
  "${OUT}/retrieval-query.json" \
  "${OUT}/retrieval-result.json" \
  "${OUT}/filtered-retrieval-result.json" \
  "${OUT}/context-packet-with-retrieval.json" \
  "${OUT}/filtered-retrieval-result-after-restart.json" \
  "${OUT}/context-packet-with-retrieval-after-restart.json" \
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
  .expected_source == "codex" and
  .expected_role == "assistant" and
  .expected_domain == "beagle-engine" and
  .memory_engine_present == 1 and
  .memory_http_present == 1 and
  .darwin_http_present == 1 and
  .collection_contract_present == 1 and
  .point_contract_present == 1 and
  .query_contract_present == 1 and
  .result_contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .collection_version == "beagle-retrieval-collection-v1" and
  .collection_kind == "hybrid-memory-retrieval-collection" and
  .supports_payload_filters == true and
  .supports_hybrid_query == true and
  any(.payload_fields[]; .name == "workstream_id" and .filterable == true) and
  any(.payload_fields[]; .name == "campaign_id") and
  any(.payload_fields[]; .name == "session_id" and .filterable == true) and
  any(.payload_fields[]; .name == "result_refs") and
  any(.payload_fields[]; .name == "claim_refs") and
  any(.filter_fields[]; . == "workstream_id") and
  any(.filter_fields[]; . == "campaign_id") and
  any(.filter_fields[]; . == "session_id")
' "${OUT}/retrieval-collection.json" >/dev/null

jq -e '
  .query_text == "B22.1 hybrid retrieval spine agourakis82/beagle main" and
  .top_k == 5 and
  .dense_enabled == true and
  .sparse_enabled == true and
  .dense_weight == 0.65 and
  .sparse_weight == 0.35 and
  .filters.domain == "beagle-engine" and
  (.filters.tags | index("hybrid-retrieval")) != null and
  (.filters.tags | index("b221")) != null
' "${OUT}/retrieval-query.json" >/dev/null

jq -e '
  .result_version == "beagle-retrieval-result-v1" and
  .retrieval_mode == "dense+sparse-hybrid" and
  .top_k == 5 and
  (.hits | length) >= 1 and
  (.hits | length) <= 5 and
  any(.hits[]; .point.payload.memory_id != null and ((.point.payload.tags | index("hybrid-retrieval")) != null)) and
  any(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  any(.hits[]; .point.payload.workstream_id == "decoy-workstream")
' "${OUT}/retrieval-result.json" >/dev/null

jq -e '
  .result_version == "beagle-retrieval-result-v1" and
  .applied_filters.workstream_id == "beagle-darwin-hpc-governance" and
  .applied_filters.campaign_id == "expedition-002-hrv-aware" and
  .applied_filters.session_id == "ws-cluster-workspace-habitat" and
  .applied_filters.source == "codex" and
  .applied_filters.role == "assistant" and
  .applied_filters.domain == "beagle-engine" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.program_id == "beagle-physio-symbolic-exocortex") and
  all(.hits[]; .point.payload.workspace_id == "beagle-cluster-pilot") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat") and
  all(.hits[]; .point.payload.source == "codex") and
  all(.hits[]; .point.payload.role == "assistant") and
  all(.hits[]; .point.payload.domain == "beagle-engine") and
  all(.hits[]; (.point.payload.tags | index("hybrid-retrieval")) != null) and
  all(.hits[]; (.point.payload.tags | index("b221")) != null) and
  all(.hits[]; (.point.payload.result_refs | length) >= 1) and
  all(.hits[]; (.point.payload.claim_refs | length) >= 1) and
  all(.hits[]; .point.payload.timestamp != null)
' "${OUT}/filtered-retrieval-result.json" >/dev/null

jq -e --slurpfile filtered "${OUT}/filtered-retrieval-result.json" '
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  (.packet.memory_hits | length) >= 1 and
  any(.packet.memory_hits[]; .memory_id == $filtered[0].hits[0].point.payload.memory_id)
' "${OUT}/context-packet-with-retrieval.json" >/dev/null

jq -e --slurpfile filtered "${OUT}/filtered-retrieval-result.json" '
  (.hits | map(.point.payload.memory_id)) == ($filtered[0].hits | map(.point.payload.memory_id))
' "${OUT}/filtered-retrieval-result-after-restart.json" >/dev/null

jq -e '
  .packet.session_id == "ws-cluster-workspace-habitat"
' "${OUT}/context-packet-with-retrieval-after-restart.json" >/dev/null

jq -e '
  .phase == "B22.1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .retrieval_hit_count >= 2 and
  .filtered_hit_count >= 1 and
  .filtered_workstream_match_count == .filtered_hit_count and
  .context_packet_memory_hit_count >= 1 and
  .context_packet_contains_filtered_memory == true and
  .restart_recovered_session == true and
  .payload_filter_state == "workstream+campaign+session+source+role+domain+tags" and
  .bounded_top_k == 3
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] hybrid retrieval spine smoke artifacts validated\n'
