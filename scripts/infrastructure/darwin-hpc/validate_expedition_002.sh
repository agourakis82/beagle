#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/expedition-002-live-execution}"
EXPERIMENT_ID="${EXPERIMENT_ID:-beagle_exp_002_hrv_aware_vs_blind}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq
require rg

required_files=(
  "${OUT}/physio-ingest-response.json"
  "${OUT}/physio-latest.json"
  "${OUT}/experiment-tags.jsonl"
  "${OUT}/run-ids.txt"
  "${OUT}/run-matrix.json"
  "${OUT}/analysis-summary.json"
  "${OUT}/analysis-summary.csv"
  "${OUT}/analysis-terminal.txt"
  "${OUT}/results-summary.json"
  "${OUT}/smoke.json"
  "${OUT}/final-cluster-health.txt"
)

for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || {
    echo "[FAIL] missing artifact: ${file}" >&2
    exit 1
  }
done

jq -e '.status == "ok"' "${OUT}/physio-ingest-response.json" >/dev/null
jq -e '.status == "ok" and .snapshot != null' "${OUT}/physio-latest.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/smoke.json" >/dev/null

jq -e --arg experiment_id "${EXPERIMENT_ID}" '
  .experiment_id == $experiment_id
  and (.conditions.hrv_aware.n_runs // 0) >= 1
  and (.conditions.hrv_blind.n_runs // 0) >= 1
' "${OUT}/analysis-summary.json" >/dev/null

jq -e '
  length >= 2
  and ((map(select(.condition == "hrv_aware")) | length) >= 1)
  and ((map(select(.condition == "hrv_blind")) | length) >= 1)
' "${OUT}/run-matrix.json" >/dev/null

jq -e --arg experiment_id "${EXPERIMENT_ID}" '
  (map(select(.condition == "hrv_aware")) | length) >= 1
  and all(map(select(.condition == "hrv_aware"))[]; .experiment.experiment_id == $experiment_id and .experiment_flags.hrv_aware == true and .pipeline_physio.used_in_pipeline == true and .pipeline_physio.snapshot_available == true)
  and (map(select(.condition == "hrv_blind")) | length) >= 1
  and all(map(select(.condition == "hrv_blind"))[]; .experiment.experiment_id == $experiment_id and .experiment_flags.hrv_aware == false and .pipeline_physio.used_in_pipeline == false and .pipeline_physio.snapshot_available == true)
' "${OUT}/run-matrix.json" >/dev/null

rg -q '^experiment_id,run_id,condition,triad_enabled,hrv_aware,serendipity_enabled,space_aware,rating_0_10,accepted,' "${OUT}/analysis-summary.csv"

if ! grep -Eq 'deployment.apps/beagle-core[[:space:]]+1/1[[:space:]]+1[[:space:]]+1' "${OUT}/final-cluster-health.txt"; then
  echo "[FAIL] beagle-core deployment not healthy in final cluster snapshot" >&2
  exit 1
fi

if ! grep -Eq 'beagle-core-.*[[:space:]]+1/1[[:space:]]+Running' "${OUT}/final-cluster-health.txt"; then
  echo "[FAIL] beagle-core pod not running in final cluster snapshot" >&2
  exit 1
fi

if ! grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"; then
  echo "[FAIL] Slurm controller not healthy" >&2
  exit 1
fi

echo "[OK] Expedition 002 validator passed"
