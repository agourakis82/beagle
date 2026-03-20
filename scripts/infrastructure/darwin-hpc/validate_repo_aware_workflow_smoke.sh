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
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"

[[ -n "${WORKSPACE_ID}" ]] || {
  echo "[FAIL] workspace-id.txt is empty" >&2
  exit 1
}
[[ -n "${EXPECTED_REPO}" ]] || {
  echo "[FAIL] expected-repo.txt is empty" >&2
  exit 1
}
[[ -n "${EXPECTED_BRANCH}" ]] || {
  echo "[FAIL] expected-branch.txt is empty" >&2
  exit 1
}

jq -e '.status == "ok"' "${OUT}/beagle-health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/beagle-health-after.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .recovered_session == false
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
' "${OUT}/bootstrap-before.json" >/dev/null

SESSION_ID="$(jq -r '.session_id' "${OUT}/bootstrap-before.json")"
[[ -n "${SESSION_ID}" && "${SESSION_ID}" != "null" ]] || {
  echo "[FAIL] bootstrap-before.json missing session_id" >&2
  exit 1
}

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and .final_job.state == "COMPLETED"
  and .artifact_manifest.job_id == .submitted_job.job_id
  and .published_result.profile_id == "cpu-short-v1"
  and .published_result_manifest.job_id == .published_result.job_id
  and (.handoff | contains($expected_repo))
  and (.handoff | contains($expected_branch))
' "${OUT}/pilot.json" >/dev/null

SUBMITTED_JOB_ID="$(jq -r '.submitted_job.job_id' "${OUT}/pilot.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/pilot.json")"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --argjson job_id "${SUBMITTED_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_id == $job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-before-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and .recovered_session == true
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_published_result_job_id == $published_job_id
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --argjson job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_id == $job_id
  and .last_published_result_job_id == $published_job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-after-restart.json" >/dev/null

echo "[OK] repo-aware workflow smoke validation passed"
