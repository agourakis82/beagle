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
  bootstrap-before.json \
  patch-summary.json \
  deploy.json \
  pilot.json \
  smoke.json \
  session-after-restart.json \
  final-cluster-health.txt \
  expected-repo.txt \
  expected-branch.txt \
  run-label.txt \
  workspace-contract-version.txt \
  published-result-job-id.txt \
  result-after.json \
  result-manifest-after.json; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
WORKSPACE_CONTRACT_VERSION="$(cat "${OUT}/workspace-contract-version.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/published-result-job-id.txt")"

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" '
  .field_name == "workspace_plane_contract_version"
  and .expected_contract_version == $expected_contract_version
  and (.field_present_in_source == true or .field_present_in_source == 1)
  and .source_match_count >= 1
' "${OUT}/patch-summary.json" >/dev/null

jq -e \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" '
  .expected_contract_version == $expected_contract_version
  and .postdeploy_contract_version == $expected_contract_version
  and .postdeploy_contract_version_matches == true
' "${OUT}/deploy.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg run_label "${RUN_LABEL}" '
  .status == "ok"
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .submitted_job.profile_id == "cpu-short-v1"
  and .final_job.state == "COMPLETED"
  and .last_successful_task.workflow_run_label == $run_label
' "${OUT}/pilot.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" \
  --arg run_label "${RUN_LABEL}" '
  .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_contract_version == $expected_contract_version
  and .postdeploy_contract_version == $expected_contract_version
  and .submitted_profile_id == "cpu-short-v1"
  and .pilot_status == "ok"
  and .workflow_run_label == $run_label
' "${OUT}/smoke.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/result-after.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/result-manifest-after.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" \
  --arg run_label "${RUN_LABEL}" '
  .workspace_plane_contract_version == $expected_contract_version
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_run_label == $run_label
  and .last_handoff != null
  and (.last_handoff | contains($expected_repo))
  and (.last_handoff | contains($expected_branch))
' "${OUT}/session-after-restart.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] repo-native dev loop smoke validation passed"
