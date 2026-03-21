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
  bootstrap-before.json \
  session-before.json \
  control-before.json \
  results-before.json \
  bridge-health.json \
  bridge-providers.json \
  bridge-execute.json \
  bridge-ledger-tail.jsonl \
  pilot.json \
  result-after.json \
  result-manifest-after.json \
  session-before-restart.json \
  beagle-health-after.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt \
  run-label.txt \
  bridge-request-id.txt \
  published-result-job-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
BRIDGE_REQUEST_ID="$(cat "${OUT}/bridge-request-id.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/published-result-job-id.txt")"

jq -e '.status == "ok"' "${OUT}/beagle-health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/beagle-health-after.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
' "${OUT}/session-before.json" >/dev/null

jq -e '
  .status == "ok"
  and .bridge_health.status == "ok"
  and (.profiles | map(.id) | index("cpu-short-v1") != null)
' "${OUT}/control-before.json" >/dev/null

jq -e '
  .result_source == "object-plane"
  and .total >= 1
' "${OUT}/results-before.json" >/dev/null

jq -e '
  .status == "ok"
  and .implemented_providers >= 1
  and .configured_providers >= 1
' "${OUT}/bridge-health.json" >/dev/null

jq -e '
  any(.[]?;
    .provider == "deepseek"
    and .implemented == true
    and .configured == true
    and .cluster_callable == true
  )
' "${OUT}/bridge-providers.json" >/dev/null

jq -e '
  .status == "success"
  and .provider == "deepseek"
  and .model == "deepseek-chat"
  and (.output.text | type == "string")
  and (.output.text | length > 0)
' "${OUT}/bridge-execute.json" >/dev/null

grep -Fq "\"request_id\":\"${BRIDGE_REQUEST_ID}\"" "${OUT}/bridge-ledger-tail.jsonl"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg run_label "${RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .submitted_job.profile_id == "cpu-short-v1"
  and .final_job.state == "COMPLETED"
  and .last_successful_task.task_kind == "operator_real_workflow_pilot"
  and .last_successful_task.repo == $expected_repo
  and .last_successful_task.branch == $expected_branch
  and .last_successful_task.workflow_run_label == $run_label
  and (.handoff | contains($expected_repo))
  and (.handoff | contains($expected_branch))
' "${OUT}/pilot.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/result-after.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/result-manifest-after.json" >/dev/null

jq -e \
  --arg run_label "${RUN_LABEL}" '
  .last_job_run_label == $run_label
  and .last_handoff != null
  and .last_successful_task.task_kind == "operator_real_workflow_pilot"
' "${OUT}/session-before-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .last_workflow_kind == "operator_real_workflow_pilot"
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_run_label == $run_label
  and .last_published_result_job_id == $published_result_job_id
  and .last_handoff != null
  and (.last_handoff | contains($expected_repo))
  and (.last_handoff | contains($expected_branch))
' "${OUT}/session-after-restart.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] canonical dev cutover smoke validation passed"
