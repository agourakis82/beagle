#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/sovereign-retrieval-track}"

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
  "${OUT}/sovereign-backend.json" \
  "${OUT}/sovereign-retrieval-query.json" \
  "${OUT}/sovereign-retrieval-result.json" \
  "${OUT}/filtered-sovereign-retrieval-result.json" \
  "${OUT}/sovereign-vs-canonical-comparison.json" \
  "${OUT}/sovereign-retrieval-result-after-restart.json" \
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
  .expected_sovereign_dense == "bge-m3" and
  .expected_sparse == "local-lexical" and
  .engine_source_present == 1 and
  .retrieval_source_present == 1 and
  .memory_lib_source_present == 1 and
  .http_memory_source_present == 1 and
  .kustomization_present == 1 and
  .configmap_present == 1 and
  .sovereign_deployment_present == 1 and
  .sovereign_service_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .contract_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .backend_id == "bge-m3" and
  .provider == "bge" and
  .model == "BAAI/bge-m3" and
  .runtime_state == "sovereign-active" and
  .store_direction == "canonical-payload-self-hosted-sovereign-track" and
  (.endpoint_ref | contains("beagle-sovereign-embeddings"))
' "${OUT}/sovereign-backend.json" >/dev/null

jq -e '
  .query_text | contains("multilingue")
' "${OUT}/sovereign-retrieval-query.json" >/dev/null

jq -e '
  .sovereign_dense_backend == "bge-m3" and
  .general_dense_backend == "voyage-4-large" and
  .sparse_backend == "local-lexical" and
  .retrieval_mode == "sovereign-dense+sparse-hybrid" and
  .backend_profile.backend_id == "bge-m3" and
  .backend_profile.model == "BAAI/bge-m3" and
  .backend_profile.runtime_state == "sovereign-active" and
  (.hits | length) >= 1 and
  (.dense_hit_count >= 1) and
  (.sparse_hit_count >= 1) and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat") and
  all(.hits[]; .point.payload.source == "codex") and
  all(.hits[]; (.point.payload.tags | index("b226-sovereign-retrieval")) != null) and
  .comparison != null
' "${OUT}/sovereign-retrieval-result.json" >/dev/null

jq -e '
  .general_dense_backend == "voyage-4-large" and
  .sovereign_dense_backend == "bge-m3" and
  (.general_top_memory_ids | length) >= 1 and
  (.sovereign_top_memory_ids | length) >= 1
' "${OUT}/sovereign-vs-canonical-comparison.json" >/dev/null

jq -e '
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.repo_path == "beagle/scripts/infrastructure/darwin-hpc/run_dense_backend_promotion_smoke.sh") and
  all(.hits[]; .point.payload.file_type == "shell")
' "${OUT}/filtered-sovereign-retrieval-result.json" >/dev/null

jq -e '
  .sovereign_dense_backend == "bge-m3" and
  .general_dense_backend == "voyage-4-large" and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/sovereign-retrieval-result-after-restart.json" >/dev/null

jq -e '
  .phase == "B22.6" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .general_dense_backend == "voyage-4-large" and
  .sovereign_dense_backend == "bge-m3" and
  .sparse_backend == "local-lexical" and
  .sovereign_runtime_state == "sovereign-active" and
  .retrieval_mode == "sovereign-dense+sparse-hybrid" and
  .retrieval_hit_count >= 1 and
  .filtered_hit_count >= 1 and
  .dense_hit_count >= 1 and
  .sparse_hit_count >= 1 and
  .comparison_present == true and
  .filtered_repo_match_count >= 1 and
  .filtered_file_type_match_count >= 1 and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] sovereign retrieval smoke artifacts validated\n'
