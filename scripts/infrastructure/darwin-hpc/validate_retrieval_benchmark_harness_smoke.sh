#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/retrieval-benchmark-harness}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq
require grep

for file in \
  source-summary.json \
  benchmark-summary.json \
  backend-matrix.json \
  retrieval-baseline.json \
  filtered-retrieval-baseline.json \
  reranking-profile.json \
  recommendation.json \
  smoke.json \
  final-cluster-health.txt; do
  [[ -f "${OUT}/${file}" ]] || {
    echo "[FAIL] missing artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

jq -e '
  .memory_engine_present == 1 and
  .memory_retrieval_present == 1 and
  .memory_http_present == 1 and
  .benchmark_contract_present == 1 and
  .backend_matrix_contract_present == 1 and
  .reranking_contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .matrix_version == "beagle-embedding-backend-matrix-v1" and
  .current_dense_backend == "local-fallback-dense" and
  .current_sparse_backend == "local-lexical" and
  any(.backends[]; .backend_id == "openai-text-embedding-3-large") and
  any(.backends[]; .backend_id == "voyage-code-3") and
  any(.backends[]; .backend_id == "bge-m3-self-hosted")
' "${OUT}/backend-matrix.json" >/dev/null

jq -e '
  .profile_version == "beagle-reranking-profile-v1" and
  .current_state == "hook-ready-not-canonical" and
  (.candidates | length) >= 2
' "${OUT}/reranking-profile.json" >/dev/null

jq -e '
  .result_version == "beagle-retrieval-result-v1" and
  .retrieval_mode == "dense+sparse-hybrid" and
  (.hits | length) >= 3 and
  any(.hits[]; .point.payload.memory_id != null and ((.point.payload.tags | index("retrieval-benchmark")) != null))
' "${OUT}/retrieval-baseline.json" >/dev/null

jq -e '
  .result_version == "beagle-retrieval-result-v1" and
  .applied_filters.workstream_id == "beagle-darwin-hpc-governance" and
  .applied_filters.campaign_id == "expedition-002-hrv-aware" and
  .applied_filters.session_id == "ws-cluster-workspace-habitat" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance" and .point.payload.source == "codex")
' "${OUT}/filtered-retrieval-baseline.json" >/dev/null

jq -e '
  .benchmark_version == "beagle-retrieval-benchmark-v1" and
  .dense_backend == "local-fallback-dense" and
  .sparse_backend == "local-lexical" and
  .summary.case_count >= 4 and
  .summary.context_packet_usable_case_count >= 1 and
  .recommendation.keep_qdrant == true and
  .recommendation.dense_backend_recommendation == "promote-stronger-dense-backend" and
  (.recommendation.bounded_upgrade_path | length) >= 3 and
  any(.cases[]; .case_kind == "code" and ((.top_hit_tags | index("code")) != null)) and
  any(.cases[]; .case_kind == "multilingual") and
  any(.cases[]; .case_kind == "filtered-prose" and .payload_filter_correctness == 1)
' "${OUT}/benchmark-summary.json" >/dev/null

jq -e '
  .keep_qdrant == true and
  .dense_backend_recommendation == "promote-stronger-dense-backend" and
  .reranking_recommendation != null and
  (.bounded_upgrade_path | length) >= 3
' "${OUT}/recommendation.json" >/dev/null

jq -e '
  .phase == "B22.2" and
  .backend_count >= 4 and
  .benchmark_case_count >= 4 and
  .baseline_hit_count >= 3 and
  .filtered_hit_count >= 1 and
  .keep_qdrant == true and
  .dense_backend_recommendation == "promote-stronger-dense-backend" and
  .recommendation_state == "bounded-upgrade-path-present" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] retrieval benchmark harness smoke artifacts validated"
