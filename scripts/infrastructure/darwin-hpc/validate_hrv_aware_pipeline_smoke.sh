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
  pipeline-start-request.json \
  pipeline-start-response.json \
  pipeline-status.json \
  run-artifacts.json \
  observer-context.json \
  run-report.json \
  feedback-event.json \
  pipeline-physio.json \
  physio-event.json \
  final-rollout.log \
  smoke.json \
  final-cluster-health.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

EXPERIMENT_ID="$(jq -r '.experiment_id' "${OUT}/source-summary.json")"

jq -e '.status == "ok" and .snapshot != null' "${OUT}/physio-ingest-response.json" >/dev/null
jq -e '.status == "ok" and .snapshot.hrv_level != null and .snapshot.severity != null' "${OUT}/physio-latest.json" >/dev/null
jq -e '.run_id != null and .status == "created"' "${OUT}/pipeline-start-response.json" >/dev/null
jq -e '.status == "done"' "${OUT}/pipeline-status.json" >/dev/null
jq -e --arg experiment_id "${EXPERIMENT_ID}" '
  .pipeline_physio.snapshot_available == true and
  .pipeline_physio.used_in_pipeline == true and
  .pipeline_physio.snapshot != null and
  .experiment_flags.hrv_aware == true and
  .experiment_flags.observer_enabled == true and
  .physio_event.recording_mode == "bounded" and
  (.physio_event.triggers | length) >= 1 and
  .experiment.experiment_id == $experiment_id and
  .observer.latest_snapshot != null
' "${OUT}/run-report.json" >/dev/null
jq -e --arg experiment_id "${EXPERIMENT_ID}" '
  .event.experiment_id == $experiment_id and
  .event.experiment_condition == "hrv_aware"
' "${OUT}/feedback-event.json" >/dev/null
jq -e '.status == "ok" and .pipeline_physio_present == true and .hrv_aware_flag == true and .physio_event_recorded == true and .trigger_count >= 1' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core[[:space:]]+1/1[[:space:]]+1[[:space:]]+1' "${OUT}/final-cluster-health.txt"
grep -Eq 'pod/beagle-core-.*[[:space:]]+1/1[[:space:]]+Running' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] hrv-aware pipeline smoke validation passed"
