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
  physio-ingest-request.json \
  physio-ingest-response.json \
  physio-latest.json \
  memory-ingest-response.json \
  memory-query-response.json \
  smoke.json \
  final-cluster-health.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

SESSION_ID="$(jq -r '.session_id' "${OUT}/source-summary.json")"

jq -e '.status == "ok" and .snapshot != null' "${OUT}/physio-ingest-response.json" >/dev/null
jq -e --arg session_id "${SESSION_ID}" '.status == "ok" and .snapshot.session_id == $session_id and .snapshot.source == "observer-smoke"' "${OUT}/physio-latest.json" >/dev/null
jq -e '.status == "ok" and .physio_attached == true' "${OUT}/memory-ingest-response.json" >/dev/null
jq -e --arg session_id "${SESSION_ID}" '(.results | length) >= 1 and .recent_physio != null and .results[0].conversation_id == $session_id and .results[0].physio_snapshot != null' "${OUT}/memory-query-response.json" >/dev/null
jq -e --arg session_id "${SESSION_ID}" '.status == "ok" and .session_id == $session_id and .memory_physio_present == true and .recent_physio_present == true' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] observer contract smoke validation passed"
