#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/retrieval-feedback-loop}"

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
  "${OUT}/retrieval-eval-report.json" \
  "${OUT}/feedback-input.json" \
  "${OUT}/feedback-prerank.json" \
  "${OUT}/feedback-postrank.json" \
  "${OUT}/retrieval-policy.json" \
  "${OUT}/feedback-postrank-after-restart.json" \
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
  .http_memory_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .feedback_contract_present == 1 and
  .eval_contract_present == 1 and
  .policy_contract_present == 1 and
  .prior_reranking_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .report_version == "beagle-retrieval-eval-report-v1" and
  .collection_name == "beagle_memory_local" and
  .sparse_backend == "local-lexical" and
  .reranking_profile_id == "b228-bounded-reranking-pilot" and
  (.cases | length) >= 3 and
  (.lanes | length) >= 3 and
  any(.lanes[]; .query_type == "general" and .dense_backend == "voyage-4-large" and .selected_route == "general") and
  any(.lanes[]; .query_type == "code" and .dense_backend == "voyage-code-3" and .selected_route == "code") and
  any(.lanes[]; .query_type == "sovereign" and .dense_backend == "bge-m3" and .selected_route == "sovereign") and
  all(.cases[]; .payload_filter_correctness >= 1.0) and
  all(.cases[]; .route_appropriate == true)
' "${OUT}/retrieval-eval-report.json" >/dev/null

jq -e '
  .feedback_version == "beagle-relevance-feedback-v1" and
  .feedback_round == 1 and
  .query_type_hint == "code" and
  (.judgments | length) == 2 and
  .judgments[0].signal == "negative" and
  .judgments[1].signal == "positive"
' "${OUT}/feedback-input.json" >/dev/null

jq -e '
  .query_type == "code" and
  .routing_decision.selected_route == "code" and
  .dense_backend == "voyage-code-3" and
  .sparse_backend == "local-lexical" and
  (.hits | length) >= 2 and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/feedback-prerank.json" >/dev/null

jq -e '
  .feedback_version == "beagle-relevance-feedback-v1" and
  .query_type == "code" and
  .routing_decision.selected_route == "code" and
  .dense_backend == "voyage-code-3" and
  .sparse_backend == "local-lexical" and
  .feedback_strategy == "top-k-score-adjustment" and
  .feedback_applied == true and
  (.hits | length) >= 2 and
  (.improvement_observed == true or .top_hit_changed == true) and
  all(.hits[]; .point.payload.workstream_id == "beagle-darwin-hpc-governance") and
  all(.hits[]; .point.payload.campaign_id == "expedition-002-hrv-aware") and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/feedback-postrank.json" >/dev/null

jq -e '
  .policy_version == "beagle-retrieval-policy-v1" and
  .policy_id == "b229-evidence-backed-retrieval-policy" and
  (.lanes | length) >= 3 and
  all(.lanes[]; (.evidence_basis | length) >= 4) and
  all(.lanes[]; .last_eval_at != null and .last_eval_at != "") and
  all(.lanes[]; .recommended_when != null and .recommended_when != "") and
  any(.lanes[]; .query_type == "general" and .dense_backend == "voyage-4-large") and
  any(.lanes[]; .query_type == "code" and .dense_backend == "voyage-code-3") and
  any(.lanes[]; .query_type == "sovereign" and .dense_backend == "bge-m3")
' "${OUT}/retrieval-policy.json" >/dev/null

jq -e '
  .feedback_applied == true and
  (.hits | length) >= 1 and
  all(.hits[]; .point.payload.session_id == "ws-cluster-workspace-habitat")
' "${OUT}/feedback-postrank-after-restart.json" >/dev/null

jq -e '
  .phase == "B22.9" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .campaign_id == "expedition-002-hrv-aware" and
  .program_id == "beagle-physio-symbolic-exocortex" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .eval_case_count >= 3 and
  .eval_lane_count >= 3 and
  .general_dense_backend == "voyage-4-large" and
  .code_dense_backend == "voyage-code-3" and
  .sovereign_dense_backend == "bge-m3" and
  .feedback_query_type == "code" and
  .feedback_route == "code" and
  .feedback_applied == true and
  (.improvement_observed == true or .top_hit_changed == true) and
  .payload_filters_preserved == true and
  .policy_lane_count >= 3 and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-embeddings" "${OUT}/final-cluster-health.txt"
grep -q "beagle-sovereign-reranker" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] retrieval feedback loop smoke artifacts validated\n'
