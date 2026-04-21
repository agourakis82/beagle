#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/expedition-002-human-eval}"
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
  "${OUT}/source-summary.json"
  "${OUT}/beagle-health.json"
  "${OUT}/run-ids.txt"
  "${OUT}/feedback-events.raw.jsonl"
  "${OUT}/human-eval-packet.json"
  "${OUT}/human-eval-key.json"
  "${OUT}/human-eval-template.json"
  "${OUT}/human-eval-source-summary.json"
  "${OUT}/analysis-summary.json"
  "${OUT}/analysis-summary.csv"
  "${OUT}/analysis-terminal.txt"
  "${OUT}/smoke.json"
  "${OUT}/final-cluster-health.txt"
)

for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || {
    echo "[FAIL] missing artifact: ${file}" >&2
    exit 1
  }
done

jq -e '.items | length >= 2' "${OUT}/human-eval-packet.json" >/dev/null
jq -e '
  .blinded == true
  and all(.items[]; has("blinded_item_id") and has("prompt") and has("draft_markdown") and (has("run_id") | not) and (has("condition") | not))
' "${OUT}/human-eval-packet.json" >/dev/null

jq -e '
  .entries as $entries
  | ($entries | length) >= 2
  and all($entries[]; has("blinded_item_id") and has("run_id") and has("condition"))
' "${OUT}/human-eval-key.json" >/dev/null

PACKET_ID="$(jq -r '.packet_id' "${OUT}/human-eval-packet.json")"
PACKET_PROTOCOL="$(jq -r '.protocol_version' "${OUT}/human-eval-packet.json")"
PACKET_ITEMS="$(jq '.items | length' "${OUT}/human-eval-packet.json")"
TEMPLATE_PACKET_ID="$(jq -r '.packet_id' "${OUT}/human-eval-template.json")"
TEMPLATE_PROTOCOL="$(jq -r '.protocol_version' "${OUT}/human-eval-template.json")"
TEMPLATE_ITEMS="$(jq '.ratings | length' "${OUT}/human-eval-template.json")"

[[ "${PACKET_ID}" == "${TEMPLATE_PACKET_ID}" ]] || {
  echo "[FAIL] template packet_id does not match packet" >&2
  exit 1
}
[[ "${PACKET_PROTOCOL}" == "${TEMPLATE_PROTOCOL}" ]] || {
  echo "[FAIL] template protocol_version does not match packet" >&2
  exit 1
}
[[ "${PACKET_ITEMS}" == "${TEMPLATE_ITEMS}" ]] || {
  echo "[FAIL] template ratings count does not match packet items" >&2
  exit 1
}

jq -e --arg experiment_id "${EXPERIMENT_ID}" '
  .experiment_id == $experiment_id
  and (.conditions.hrv_aware.n_runs // 0) >= 1
  and (.conditions.hrv_blind.n_runs // 0) >= 1
' "${OUT}/analysis-summary.json" >/dev/null

STATUS="$(jq -r '.status' "${OUT}/smoke.json")"
case "${STATUS}" in
  ready_for_human_eval)
    jq -e '.ratings_applied == 0 and .items >= 2' "${OUT}/smoke.json" >/dev/null
    jq -e '
      (.conditions.hrv_aware.n_with_feedback // 0) == 0
      and (.conditions.hrv_blind.n_with_feedback // 0) == 0
    ' "${OUT}/analysis-summary.json" >/dev/null
    ;;
  ok)
    [[ -f "${OUT}/appended-human-feedback.json" ]] || {
      echo "[FAIL] smoke status ok requires appended-human-feedback.json" >&2
      exit 1
    }
    jq -e '.ratings_applied >= 1' "${OUT}/smoke.json" >/dev/null
    jq -e '
      ((.conditions.hrv_aware.n_with_feedback // 0) >= 1)
      or ((.conditions.hrv_blind.n_with_feedback // 0) >= 1)
    ' "${OUT}/analysis-summary.json" >/dev/null
    ;;
  *)
    echo "[FAIL] unexpected smoke status: ${STATUS}" >&2
    exit 1
    ;;
esac

if ! grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"; then
  echo "[FAIL] beagle-core deployment missing from final cluster snapshot" >&2
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

echo "[OK] Expedition 002 human-eval validator passed (${STATUS})"
