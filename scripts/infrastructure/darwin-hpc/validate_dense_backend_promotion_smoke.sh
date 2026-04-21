#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/dense-backend-promotion}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require jq
require rg

for file in \
  "${OUT}/source-summary.json" \
  "${OUT}/dense-backend-contract.json" \
  "${OUT}/dense-backend-contract-after-restart.json" \
  "${OUT}/retrieval-collection.json" \
  "${OUT}/backend-matrix.json" \
  "${OUT}/retrieval-result.json" \
  "${OUT}/filtered-retrieval-result.json" \
  "${OUT}/context-packet-with-retrieval.json" \
  "${OUT}/context-packet-with-promoted-dense.json" \
  "${OUT}/promotion-summary.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  [[ -f "${file}" ]] || {
    echo "[FAIL] missing artifact: ${file}" >&2
    exit 1
  }
done

jq -e '
  .memory_engine_present == 1 and
  .memory_retrieval_present == 1 and
  .memory_http_present == 1 and
  .darwin_http_present == 1 and
  .contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .promoted_dense_backend == "voyage-4-large" and
  .promoted_provider == "voyage" and
  .promoted_model == "voyage-4-large" and
  .code_candidate_backend == "voyage-code-3" and
  .sovereign_candidate_backend == "bge-m3" and
  (.runtime_state == "promoted-active" or .runtime_state == "auth-blocked-fallback" or .runtime_state == "endpoint-missing-fallback")
' "${OUT}/dense-backend-contract.json" >/dev/null

jq -e '
  .sparse_backend == "local-lexical" and
  (.dense_backend == "voyage-4-large" or .dense_backend == "local-fallback-dense")
' "${OUT}/retrieval-collection.json" >/dev/null

jq -e '
  .current_sparse_backend == "local-lexical" and
  any(.backends[]; .backend_id == "voyage-4-large") and
  any(.backends[]; .backend_id == "voyage-code-3") and
  any(.backends[]; .backend_id == "bge-m3")
' "${OUT}/backend-matrix.json" >/dev/null

jq -e '
  (.hits | length) >= 1 and
  (.dense_hit_count >= 1) and
  (.sparse_hit_count >= 1)
' "${OUT}/retrieval-result.json" >/dev/null

jq -e '
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance" and .point.payload.source == "codex")
' "${OUT}/filtered-retrieval-result.json" >/dev/null

jq -e '
  .promoted_dense_backend == "voyage-4-large" and
  (.active_dense_backend == "voyage-4-large" or .active_dense_backend == "local-fallback-dense") and
  .sparse_backend == "local-lexical"
' "${OUT}/promotion-summary.json" >/dev/null

jq -e '
  .promoted_dense_backend == "voyage-4-large" and
  (.active_dense_backend == "voyage-4-large" or .active_dense_backend == "local-fallback-dense") and
  (.runtime_state == "promoted-active" or .runtime_state == "auth-blocked-fallback" or .runtime_state == "endpoint-missing-fallback") and
  .retrieval_hit_count >= 1 and
  .filtered_hit_count >= 1 and
  .filtered_workstream_match_count >= 1 and
  .context_packet_memory_hit_count >= 1 and
  .context_packet_contains_filtered_memory == true and
  .restart_recovered_session == true and
  .bounded_top_k == 3
' "${OUT}/smoke.json" >/dev/null

rg -q "beagle-core" "${OUT}/final-cluster-health.txt"
rg -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
rg -q "UP" "${OUT}/final-cluster-health.txt"
