#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:?OUT is required}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq

for file in \
  source-summary.json \
  build.log \
  image-load.log \
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health.json \
  observer-physio-response.json \
  ingest-response.json \
  query-response.json \
  physio-attachment.json \
  mcp-npm-ci.log \
  mcp-build.log \
  mcp-tool-results.json \
  mcp-ingest-response.json \
  mcp-query-response.json \
  smoke.json \
  final-cluster-health.txt \
  conversation-id.txt \
  memory-id.txt \
  expected-source.txt \
  expected-domain.txt \
  expected-tag.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

CONVERSATION_ID="$(cat "${OUT}/conversation-id.txt")"
MEMORY_ID="$(cat "${OUT}/memory-id.txt")"
EXPECTED_SOURCE="$(cat "${OUT}/expected-source.txt")"
EXPECTED_DOMAIN="$(cat "${OUT}/expected-domain.txt")"
EXPECTED_TAG="$(cat "${OUT}/expected-tag.txt")"

jq -e \
  --arg expected_source "${EXPECTED_SOURCE}" \
  --arg expected_domain "${EXPECTED_DOMAIN}" \
  --arg expected_tag "${EXPECTED_TAG}" '
  .expected_source == $expected_source
  and .expected_domain == $expected_domain
  and .expected_tag == $expected_tag
  and (.http_source_present == true or .http_source_present == 1)
  and (.engine_source_present == true or .engine_source_present == 1)
  and (.mcp_source_present == true or .mcp_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.ingest_contract_present == true or .ingest_contract_present == 1)
  and (.query_contract_present == true or .query_contract_present == 1)
  and (.response_contract_present == true or .response_contract_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e '.status == "ok"' "${OUT}/observer-physio-response.json" >/dev/null

jq -e \
  --arg conversation_id "${CONVERSATION_ID}" '
  .status == "ok"
  and .conversation_id == $conversation_id
  and .memory_id != null
  and .searchable == true
  and .physio_attached == true
  and .experiment_flags_attached == true
' "${OUT}/ingest-response.json" >/dev/null

jq -e \
  --arg conversation_id "${CONVERSATION_ID}" \
  --arg memory_id "${MEMORY_ID}" \
  --arg expected_source "${EXPECTED_SOURCE}" \
  --arg expected_domain "${EXPECTED_DOMAIN}" \
  --arg expected_tag "${EXPECTED_TAG}" '
  (.results | length) >= 1
  and .recent_physio != null
  and .results[0].conversation_id == $conversation_id
  and .results[0].memory_id == $memory_id
  and .results[0].source == $expected_source
  and .results[0].domain == $expected_domain
  and (.results[0].tags | index($expected_tag) != null)
  and .results[0].physio_snapshot != null
' "${OUT}/query-response.json" >/dev/null

jq -e '.source == "observer_context"' "${OUT}/physio-attachment.json" >/dev/null

jq -e \
  '.status == "ok"
  and .memory_id != null
  and .searchable == true
  and .physio_attached == true
' "${OUT}/mcp-ingest-response.json" >/dev/null

jq -e \
  --arg conversation_id "${CONVERSATION_ID}" '
  (.results | length) >= 1
  and .summary != null
  and (.results | map(.conversation_id) | index($conversation_id) != null)
' "${OUT}/mcp-query-response.json" >/dev/null

jq -e \
  --arg conversation_id "${CONVERSATION_ID}" \
  --arg memory_id "${MEMORY_ID}" \
  --arg expected_source "${EXPECTED_SOURCE}" \
  --arg expected_domain "${EXPECTED_DOMAIN}" \
  --arg expected_tag "${EXPECTED_TAG}" '
  .status == "ok"
  and .conversation_id == $conversation_id
  and .memory_id == $memory_id
  and .expected_source == $expected_source
  and .expected_domain == $expected_domain
  and .expected_tag == $expected_tag
  and .http_query_result_count >= 1
  and .http_physio_present == true
  and .mcp_query_result_count >= 1
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] memory ingest spine smoke validation passed"
