#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/temporal-memory-contradiction}"

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
  "${OUT}/temporal-memory.json" \
  "${OUT}/contradiction-report.json" \
  "${OUT}/temporal-query.json" \
  "${OUT}/temporal-query-result.json" \
  "${OUT}/context-packet-with-temporal-memory.json" \
  "${OUT}/program-context-packet-with-temporal-memory.json" \
  "${OUT}/context-packet-with-temporal-memory-after-restart.json" \
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
  .temporal_source_present == 1 and
  .engine_source_present == 1 and
  .memory_lib_source_present == 1 and
  .core_context_source_present == 1 and
  .http_memory_source_present == 1 and
  .http_darwin_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .temporal_schema_present == 1 and
  .contradiction_schema_present == 1 and
  .temporal_query_schema_present == 1 and
  .prior_graphrag_artifacts_present == 1 and
  .prior_promotion_artifacts_present == 1 and
  .prior_compiler_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .schema_version == "beagle-temporal-memory-v1" and
  .policy_id == "b234-temporal-memory-policy" and
  ((.validity_markers // []) | index("valid_until")) != null and
  ((.bounded_entity_types // []) | index("Claim")) != null
' "${OUT}/temporal-memory.json" >/dev/null

jq -e '
  .query_text == "beagle-darwin-hpc-governance qa state across time" and
  .truth_view == "both" and
  .filters.workstream_id == "beagle-darwin-hpc-governance" and
  .filters.campaign_id == "expedition-002-hrv-aware" and
  ((.subject_refs // []) | index("claim:expedition-002-qa-state")) != null and
  .include_contradictions == true
' "${OUT}/temporal-query.json" >/dev/null

jq -e '
  .result_version == "beagle-temporal-query-result-v1" and
  .schema_version == "beagle-temporal-memory-v1" and
  .truth_view == "both" and
  .query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .track_count >= 1 and
  .current_truth_count >= 1 and
  .historical_truth_count >= 1 and
  .contradiction_count >= 1 and
  ((.top_current_memory_ids // []) | length) >= 1 and
  ((.top_historical_memory_ids // []) | length) >= 1 and
  ((.tracks // []) | length) >= 1 and
  (.tracks[0].current_memory_id | length) > 0 and
  ((.tracks[0].historical_memory_ids // []) | length) >= 1 and
  ((.subject_refs // []) | index("claim:expedition-002-qa-state")) != null
' "${OUT}/temporal-query-result.json" >/dev/null

jq -e '
  .contradiction_version == "beagle-memory-contradiction-v1" and
  .truth_view == "both" and
  .contradiction_count >= 1 and
  ((.contradictions // []) | length) >= 1 and
  .contradictions[0].contradiction_kind == "explicit-state-flip"
' "${OUT}/contradiction-report.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.temporal_truth_view == "both" and
  .packet.retrieval_context.temporal_track_count >= 1 and
  .packet.retrieval_context.temporal_contradiction_count >= 1 and
  ((.packet.retrieval_context.temporal_current_memory_ids // []) | length) >= 1 and
  ((.packet.retrieval_context.temporal_historical_memory_ids // []) | length) >= 1 and
  ((.packet.retrieval_context.temporal_contradiction_ids // []) | length) >= 1
' "${OUT}/context-packet-with-temporal-memory.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.temporal_truth_view == "both" and
  .packet.retrieval_context.temporal_track_count >= 1 and
  .packet.retrieval_context.temporal_contradiction_count >= 1
' "${OUT}/program-context-packet-with-temporal-memory.json" >/dev/null

jq -e '
  .status == "ok" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.temporal_truth_view == "both" and
  .packet.retrieval_context.temporal_contradiction_count >= 1
' "${OUT}/context-packet-with-temporal-memory-after-restart.json" >/dev/null

jq -e '
  .phase == "B23.4" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .truth_view == "both" and
  .current_truth_count >= 1 and
  .historical_truth_count >= 1 and
  .contradiction_count >= 1 and
  .context_packet_contains_temporal_memory == true and
  .program_context_contains_temporal_memory == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-reranker" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] temporal memory contradiction smoke artifacts validated\n'
