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
  control-before.json \
  results-before.json \
  pilot.json \
  result-after.json \
  result-manifest-after.json \
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
jq -e '.status == "ok"' "${OUT}/control-before.json" >/dev/null
jq -e '.profiles | length > 0' "${OUT}/control-before.json" >/dev/null
jq -e '.bridge_health.status == "ok"' "${OUT}/control-before.json" >/dev/null
jq -e '.total >= 1' "${OUT}/results-before.json" >/dev/null

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
  and (.current_task == null)
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
  and .catalog_before.total >= 1
  and (.catalog_before.latest_result.job_id | type == "number")
  and .final_job.state == "COMPLETED"
  and .artifact_manifest.job_id == .submitted_job.job_id
  and .published_result.profile_id == "cpu-short-v1"
  and .resolved_result_lookup.job_id == .published_result.job_id
  and .published_result_manifest.job_id == .published_result.job_id
  and .last_successful_task.task_kind == "operator_real_workflow_pilot"
  and .last_successful_task.task_state == "completed"
  and .last_successful_task.repo == $expected_repo
  and .last_successful_task.branch == $expected_branch
  and (.handoff | contains($expected_repo))
  and (.handoff | contains($expected_branch))
' "${OUT}/pilot.json" >/dev/null

SUBMITTED_JOB_ID="$(jq -r '.submitted_job.job_id' "${OUT}/pilot.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/pilot.json")"

jq -e \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id
' "${OUT}/result-after.json" >/dev/null

jq -e \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id
' "${OUT}/result-manifest-after.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and (.current_task == null)
  and .last_workflow_kind == "operator_real_workflow_pilot"
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_id == $submitted_job_id
  and .last_published_result_job_id == $published_job_id
  and .last_successful_task.task_kind == "operator_real_workflow_pilot"
  and .last_successful_task.submitted_job_id == $submitted_job_id
  and .last_successful_task.published_result_job_id == $published_job_id
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
  and (.current_task == null)
  and .last_workflow_kind == "operator_real_workflow_pilot"
  and .last_published_result_job_id == $published_job_id
  and .last_successful_task.task_kind == "operator_real_workflow_pilot"
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and (.current_task == null)
  and .last_workflow_kind == "operator_real_workflow_pilot"
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_id == $submitted_job_id
  and .last_published_result_job_id == $published_job_id
  and .last_successful_task.task_kind == "operator_real_workflow_pilot"
  and .last_successful_task.submitted_job_id == $submitted_job_id
  and .last_successful_task.published_result_job_id == $published_job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-after-restart.json" >/dev/null

echo "[OK] operator-real workflow smoke validation passed"
