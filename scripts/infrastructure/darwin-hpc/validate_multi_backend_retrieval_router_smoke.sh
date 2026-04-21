#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/multi-backend-retrieval-router}"

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
  "${OUT}/query-type.json" \
  "${OUT}/routing-decision.json" \
  "${OUT}/routed-retrieval-result.json" \
  "${OUT}/filtered-routed-retrieval-result.json" \
  "${OUT}/sovereign-routed-retrieval-result.json" \
  "${OUT}/context-packet-with-routed-retrieval.json" \
  "${OUT}/program-context-packet-with-routed-retrieval.json" \
  "${OUT}/routed-retrieval-result-after-restart.json" \
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
  .expected_code_dense == "voyage-code-3" and
  .expected_sovereign_dense == "bge-m3" and
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
  .router_contract_present == 1 and
  .query_type_contract_present == 1 and
  .routing_decision_contract_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .selected_query_type == "sovereign" and
  .classifier_source != null and
  (.classifier_reason | length) > 0
' "${OUT}/query-type.json" >/dev/null

jq -e '
  .query_type == "code" and
  .selected_route == "code" and
  .selected_dense_backend == "voyage-code-3" and
  .sparse_backend == "local-lexical" and
  .payload_filters_present == true and
  .routing_source == "payload-filter"
' "${OUT}/routing-decision.json" >/dev/null

jq -e '
  .query_type == "general" and
  .routing_decision.selected_dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat") and
  all(.hits[]; .point.payload.source == "codex") and
  all(.hits[]; (.point.payload.tags | index("b227-multi-backend-router")) != null) and
  all(.hits[]; (.point.payload.tags | index("general")) != null)
' "${OUT}/routed-retrieval-result.json" >/dev/null

jq -e '
  .query_type == "code" and
  .routing_decision.selected_dense_backend == "voyage-code-3" and
  .sparse_backend == "local-lexical" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.repo_path == "beagle/crates/beagle-darwin/src/workspace_attach.rs") and
  all(.hits[]; .point.payload.file_type == "rust") and
  all(.hits[]; (.point.payload.tags | index("code")) != null) and
  .comparison_general_dense_backend == "voyage-4-large"
' "${OUT}/filtered-routed-retrieval-result.json" >/dev/null

jq -e '
  .query_type == "sovereign" and
  .routing_decision.selected_dense_backend == "bge-m3" and
  .sparse_backend == "local-lexical" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; (.point.payload.tags | index("sovereign")) != null)
' "${OUT}/sovereign-routed-retrieval-result.json" >/dev/null

jq -e '
  .packet.workstream_id == "beagle-darwin-hpc-governance" and
  .packet.workspace_id == "beagle-cluster-pilot" and
  .packet.session_id == "ws-cluster-workspace-habitat" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.query_type == "general" and
  .packet.retrieval_context.dense_backend == "voyage-4-large" and
  .packet.retrieval_context.sparse_backend == "local-lexical" and
  (.packet.retrieval_context.routing_source | length) > 0 and
  (.packet.retrieval_context.routing_reason | length) > 0 and
  (.packet.retrieval_context.top_memory_ids | length) >= 1
' "${OUT}/context-packet-with-routed-retrieval.json" >/dev/null

jq -e '
  .packet.program_id == "beagle-physio-symbolic-exocortex" and
  .packet.campaign_id == "expedition-002-hrv-aware" and
  .packet.retrieval_context != null and
  .packet.retrieval_context.query_type == "general" and
  .packet.retrieval_context.dense_backend == "voyage-4-large" and
  .packet.retrieval_context.sparse_backend == "local-lexical"
' "${OUT}/program-context-packet-with-routed-retrieval.json" >/dev/null

jq -e '
  .query_type == "general" and
  .routing_decision.selected_dense_backend == "voyage-4-large" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/routed-retrieval-result-after-restart.json" >/dev/null

jq -e '
  .phase == "B22.7" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .general_backend == "voyage-4-large" and
  .code_backend == "voyage-code-3" and
  .sovereign_backend == "bge-m3" and
  .sparse_backend == "local-lexical" and
  .general_query_type == "general" and
  .code_query_type == "code" and
  .sovereign_query_type == "sovereign" and
  .general_selected_backend == "voyage-4-large" and
  .code_selected_backend == "voyage-code-3" and
  .sovereign_selected_backend == "bge-m3" and
  .retrieval_query_type_works == true and
  .routing_decision_works == true and
  .general_hit_count >= 1 and
  .code_hit_count >= 1 and
  .sovereign_hit_count >= 1 and
  .filtered_hit_count >= 1 and
  .filtered_repo_match_count >= 1 and
  .filtered_file_type_match_count >= 1 and
  .workstream_context_present == true and
  .workstream_query_type == "general" and
  .program_context_present == true and
  .program_query_type == "general" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] multi-backend retrieval router smoke artifacts validated\n'
