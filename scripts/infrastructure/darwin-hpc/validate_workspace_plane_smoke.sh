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
  beagle-health-before.json \
  beagle-health-after.json \
  bootstrap-before.json \
  pilot.json \
  session-before-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  final-cluster-health.txt \
  workspace-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
[[ -n "${WORKSPACE_ID}" ]] || {
  echo "[FAIL] workspace-id.txt is empty" >&2
  exit 1
}

jq -e '.status == "ok"' "${OUT}/beagle-health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/beagle-health-after.json" >/dev/null

jq -e --arg workspace_id "${WORKSPACE_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .recovered_session == false
' "${OUT}/bootstrap-before.json" >/dev/null

SESSION_ID="$(jq -r '.session_id' "${OUT}/bootstrap-before.json")"
[[ -n "${SESSION_ID}" && "${SESSION_ID}" != "null" ]] || {
  echo "[FAIL] bootstrap-before.json missing session_id" >&2
  exit 1
}

jq -e --arg workspace_id "${WORKSPACE_ID}" --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .final_job.state == "COMPLETED"
  and .artifact_manifest.job_id == .submitted_job.job_id
  and .published_result.profile_id == "cpu-short-v1"
  and .published_result_manifest.job_id == .published_result.job_id
  and (.handoff | length > 0)
' "${OUT}/pilot.json" >/dev/null

SUBMITTED_JOB_ID="$(jq -r '.submitted_job.job_id' "${OUT}/pilot.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/pilot.json")"

jq -e --arg workspace_id "${WORKSPACE_ID}" --arg session_id "${SESSION_ID}" --argjson job_id "${SUBMITTED_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .last_job_id == $job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-before-restart.json" >/dev/null

jq -e --arg workspace_id "${WORKSPACE_ID}" --arg session_id "${SESSION_ID}" --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .recovered_session == true
  and .last_published_result_job_id == $published_job_id
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e --arg workspace_id "${WORKSPACE_ID}" --arg session_id "${SESSION_ID}" --argjson job_id "${SUBMITTED_JOB_ID}" --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .last_job_id == $job_id
  and .last_published_result_job_id == $published_job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-after-restart.json" >/dev/null

echo "[OK] workspace plane smoke validation passed"
