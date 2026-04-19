#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/reranking-pilot}"
EXPECTED_GENERAL_RERANKER="${EXPECTED_GENERAL_RERANKER:-voyage-rerank-2.5}"
EXPECTED_SOVEREIGN_RERANKER="${EXPECTED_SOVEREIGN_RERANKER:-Alibaba-NLP/gte-reranker-modernbert-base}"

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
  "${OUT}/reranking-profile.json" \
  "${OUT}/prerank-result.json" \
  "${OUT}/postrank-result.json" \
  "${OUT}/sovereign-prerank-result.json" \
  "${OUT}/sovereign-postrank-result.json" \
  "${OUT}/latency-comparison.json" \
  "${OUT}/reranking-recommendation.json" \
  "${OUT}/context-packet-with-reranked-retrieval.json" \
  "${OUT}/program-context-packet-with-reranked-retrieval.json" \
  "${OUT}/postrank-result-after-restart.json" \
  "${OUT}/context-packet-with-reranked-retrieval-after-restart.json" \
  "${OUT}/program-context-packet-with-reranked-retrieval-after-restart.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing artifact: ${path}" >&2
    exit 1
  }
done

jq -e \
  --arg expected_general_reranker "${EXPECTED_GENERAL_RERANKER}" \
  --arg expected_sovereign_reranker "${EXPECTED_SOVEREIGN_RERANKER}" '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_program == "beagle-physio-symbolic-exocortex" and
  .expected_workspace == "beagle-cluster-pilot" and
  .expected_session == "ws-cluster-workspace-habitat" and
  .expected_general_dense == "voyage-4-large" and
  .expected_sovereign_dense == "bge-m3" and
  .expected_sparse == "local-lexical" and
  .expected_general_reranker == $expected_general_reranker and
  .expected_sovereign_reranker == $expected_sovereign_reranker and
  .engine_source_present == 1 and
  .retrieval_source_present == 1 and
  .memory_lib_source_present == 1 and
  .core_context_source_present == 1 and
  .workstream_context_source_present == 1 and
  .program_context_source_present == 1 and
  .http_memory_source_present == 1 and
  .http_darwin_source_present == 1 and
  .k8s_configmap_present == 1 and
  .k8s_kustomization_present == 1 and
  .sovereign_reranker_deployment_present == 1 and
  .sovereign_reranker_service_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .reranking_profile_contract_present == 1 and
  .reranked_result_contract_present == 1 and
  .prior_router_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg expected_general_reranker "${EXPECTED_GENERAL_RERANKER}" \
  --arg expected_sovereign_reranker "${EXPECTED_SOVEREIGN_RERANKER}" '
  .profile_id == "b228-bounded-reranking-pilot" and
  .current_state == "pilot-live-bounded" and
  .current_mode == "top-k-reranking-pilot" and
  .bounded_top_k == 5 and
  .general_candidate_id == $expected_general_reranker and
  .sovereign_candidate_id == $expected_sovereign_reranker and
  any(.candidates[]; .candidate_id == $expected_general_reranker and .runtime_state == "pilot-active" and .route_scope == "general") and
  any(.candidates[]; .candidate_id == $expected_sovereign_reranker and .runtime_state == "pilot-active" and .route_scope == "sovereign")
' "${OUT}/reranking-profile.json" >/dev/null

jq -e '
  .query_type == "general" and
  .routing_decision.selected_dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat") and
  all(.hits[]; .point.payload.source == "codex") and
  all(.hits[]; (.point.payload.tags | index("b228-reranking-pilot")) != null) and
  all(.hits[]; (.point.payload.tags | index("general")) != null)
' "${OUT}/prerank-result.json" >/dev/null

jq -e '
  .query_type == "general" and
  .dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .reranker_backend == "voyage-rerank-2.5" and
  .reranker_runtime_state == "pilot-active" and
  .reranking_applied == true and
  .profile_id == "b228-bounded-reranking-pilot" and
  (.postrank_retrieval_mode | endswith("+rerank")) and
  (.hits | length) >= 1 and
  .candidate_count >= .postrank_hit_count and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/postrank-result.json" >/dev/null

jq -e '
  .query_type == "sovereign" and
  .routing_decision.selected_dense_backend == "bge-m3" and
  .sparse_backend == "local-lexical" and
  (.hits | length) >= 1 and
  all(.hits[]; (.point.payload.tags | index("sovereign")) != null)
' "${OUT}/sovereign-prerank-result.json" >/dev/null

jq -e \
  --arg expected_sovereign_reranker "${EXPECTED_SOVEREIGN_RERANKER}" '
  .query_type == "sovereign" and
  .dense_backend == "bge-m3" and
  .sparse_backend == "local-lexical" and
  .reranker_backend == $expected_sovereign_reranker and
  .reranker_runtime_state == "pilot-active" and
  .reranking_applied == true and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; (.point.payload.tags | index("sovereign")) != null)
' "${OUT}/sovereign-postrank-result.json" >/dev/null

jq -e '
  .general.prerank_latency_ms >= 0 and
  .general.rerank_latency_ms >= 0 and
  .general.total_latency_ms >= .general.prerank_latency_ms and
  .general.total_latency_ms >= .general.rerank_latency_ms and
  .general.latency_delta_ms == .general.rerank_latency_ms and
  .sovereign.prerank_latency_ms >= 0 and
  .sovereign.rerank_latency_ms >= 0 and
  .sovereign.total_latency_ms >= .sovereign.prerank_latency_ms and
  .sovereign.total_latency_ms >= .sovereign.rerank_latency_ms and
  .sovereign.latency_delta_ms == .sovereign.rerank_latency_ms
' "${OUT}/latency-comparison.json" >/dev/null

jq -e \
  --arg expected_general_reranker "${EXPECTED_GENERAL_RERANKER}" \
  --arg expected_sovereign_reranker "${EXPECTED_SOVEREIGN_RERANKER}" '
  .general.query_type == "general" and
  .general.reranker_backend == $expected_general_reranker and
  .general.reranking_applied == true and
  .sovereign.query_type == "sovereign" and
  .sovereign.reranker_backend == $expected_sovereign_reranker and
  .sovereign.reranking_applied == true
' "${OUT}/reranking-recommendation.json" >/dev/null

jq -e '
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.query_type == "general" and
  .packet.retrieval_context.dense_backend == "voyage-4-large" and
  .packet.retrieval_context.sparse_backend == "local-lexical" and
  .packet.retrieval_context.reranking_applied == true and
  .packet.retrieval_context.reranking_profile_id == "b228-bounded-reranking-pilot" and
  .packet.retrieval_context.reranker_backend == "voyage-rerank-2.5" and
  .packet.retrieval_context.reranker_runtime_state == "pilot-active"
' "${OUT}/context-packet-with-reranked-retrieval.json" >/dev/null

jq -e '
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.campaign_id == "expedition-002-hrv-aware" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.query_type == "general" and
  .packet.retrieval_context.dense_backend == "voyage-4-large" and
  .packet.retrieval_context.reranking_applied == true and
  .packet.retrieval_context.reranker_backend == "voyage-rerank-2.5"
' "${OUT}/program-context-packet-with-reranked-retrieval.json" >/dev/null

jq -e '
  .query_type == "general" and
  .reranker_backend == "voyage-rerank-2.5" and
  .reranking_applied == true and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/postrank-result-after-restart.json" >/dev/null

jq -e '
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context.reranking_applied == true and
  .packet.retrieval_context.reranker_backend == "voyage-rerank-2.5"
' "${OUT}/context-packet-with-reranked-retrieval-after-restart.json" >/dev/null

jq -e '
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.retrieval_context.reranking_applied == true and
  .packet.retrieval_context.reranker_backend == "voyage-rerank-2.5"
' "${OUT}/program-context-packet-with-reranked-retrieval-after-restart.json" >/dev/null

jq -e \
  --arg expected_general_reranker "${EXPECTED_GENERAL_RERANKER}" \
  --arg expected_sovereign_reranker "${EXPECTED_SOVEREIGN_RERANKER}" '
  .phase == "B22.8" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .general_dense_backend == "voyage-4-large" and
  .sovereign_dense_backend == "bge-m3" and
  .sparse_backend == "local-lexical" and
  .general_reranker_backend == $expected_general_reranker and
  .sovereign_reranker_backend == $expected_sovereign_reranker and
  .general_reranking_applied == true and
  .sovereign_reranking_applied == true and
  .general_prerank_hit_count >= 1 and
  .general_postrank_hit_count >= 1 and
  .sovereign_prerank_hit_count >= 1 and
  .sovereign_postrank_hit_count >= 1 and
  .payload_filters_preserved == true and
  .workstream_context_reranking_applied == true and
  .workstream_context_reranker_backend == "voyage-rerank-2.5" and
  .program_context_reranking_applied == true and
  .program_context_reranker_backend == "voyage-rerank-2.5" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-reranker" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] reranking pilot smoke artifacts validated\n'
