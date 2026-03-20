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
  beagle-health.json \
  control.json \
  profiles.json \
  results.json \
  bridge-health.json \
  bridge-providers.json \
  bridge-execute-human.json \
  submit.json \
  job-status.json \
  job-artifact-manifest.json \
  published-result.json \
  published-result-manifest.json \
  results-by-run-label.json \
  final-cluster-health.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

jq -e '.status == "ok"' "${OUT}/beagle-health.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/control.json" >/dev/null
jq -e '.profiles | map(.id) | index("cpu-short-v1") != null' "${OUT}/profiles.json" >/dev/null
jq -e '.result_source == "object-plane" and (.total >= 1)' "${OUT}/results.json" >/dev/null
jq -e '.status == "ok" and .ledger_enabled == true' "${OUT}/bridge-health.json" >/dev/null
jq -e 'map(.provider) | index("deepseek") != null' "${OUT}/bridge-providers.json" >/dev/null
jq -e '.status == "deferred"' "${OUT}/bridge-execute-human.json" >/dev/null

JOB_ID="$(jq -r '.job_id' "${OUT}/submit.json")"
[[ -n "${JOB_ID}" && "${JOB_ID}" != "null" ]] || {
  echo "[FAIL] submit.json missing job_id" >&2
  exit 1
}

jq -e --argjson job_id "${JOB_ID}" '.job_id == $job_id and .state == "COMPLETED"' "${OUT}/job-status.json" >/dev/null
jq -e --argjson job_id "${JOB_ID}" '.job_id == $job_id' "${OUT}/job-artifact-manifest.json" >/dev/null
PUBLISHED_JOB_ID="$(jq -r '.job_id' "${OUT}/published-result.json")"
[[ -n "${PUBLISHED_JOB_ID}" && "${PUBLISHED_JOB_ID}" != "null" ]] || {
  echo "[FAIL] published-result.json missing job_id" >&2
  exit 1
}

jq -e --argjson job_id "${PUBLISHED_JOB_ID}" '.job_id == $job_id' "${OUT}/published-result.json" >/dev/null
jq -e --argjson job_id "${PUBLISHED_JOB_ID}" '.job_id == $job_id and (.object_bucket == "darwin-hpc-artifacts")' "${OUT}/published-result-manifest.json" >/dev/null
jq -e --argjson job_id "${PUBLISHED_JOB_ID}" '.results | map(.job_id) | index($job_id) != null' "${OUT}/results-by-run-label.json" >/dev/null

echo "[OK] internal control surface smoke validation passed"
