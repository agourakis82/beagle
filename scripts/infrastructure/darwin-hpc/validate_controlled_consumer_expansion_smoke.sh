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
  operator-self.json \
  operator-bootstrap.json \
  operator-control.json \
  research-self.json \
  research-control-denied.code \
  research-control-denied.json \
  research-profiles.json \
  research-submit-denied.code \
  research-submit-denied.json \
  research-submit.code \
  research-submit.json \
  research-status.json \
  research-artifact-manifest.json \
  research-stdout.json \
  research-stderr.json \
  research-results.json \
  research-result.json \
  research-result-manifest.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt \
  allowed-profile-id.txt \
  denied-profile-id.txt \
  run-label.txt \
  research-job-id.txt \
  published-result-job-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
ALLOWED_PROFILE_ID="$(cat "${OUT}/allowed-profile-id.txt")"
DENIED_PROFILE_ID="$(cat "${OUT}/denied-profile-id.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
RESEARCH_JOB_ID="$(cat "${OUT}/research-job-id.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/published-result-job-id.txt")"

jq -e '.status == "ok"' "${OUT}/beagle-health.json" >/dev/null

jq -e '
  .id == "beagle-operator"
  and .lane == "operator"
  and .allow_workspace_plane == true
  and .allow_hpc_control == true
  and .allow_hpc_submit == true
  and .allow_bridge_execute == true
  and (.allowed_profiles | index("gpu-single-v1") != null)
' "${OUT}/operator-self.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
' "${OUT}/operator-bootstrap.json" >/dev/null

jq -e '
  .status == "ok"
  and .bridge_health.status == "ok"
  and (.profiles | map(.id) | index("cpu-short-v1") != null)
  and (.profiles | map(.id) | index("cpu-batch-v1") != null)
  and (.profiles | map(.id) | index("gpu-single-v1") != null)
' "${OUT}/operator-control.json" >/dev/null

jq -e '
  .id == "darwin-research"
  and .lane == "research"
  and .allow_workspace_plane == false
  and .allow_hpc_control == false
  and .allow_hpc_submit == true
  and .allow_hpc_read == true
  and .allow_bridge_execute == false
  and (.allowed_profiles | index("cpu-short-v1") != null)
  and (.allowed_profiles | index("cpu-batch-v1") != null)
  and (.allowed_profiles | index("gpu-single-v1") == null)
' "${OUT}/research-self.json" >/dev/null

[[ "$(cat "${OUT}/research-control-denied.code")" == "403" ]] || {
  echo "[FAIL] research control endpoint was not denied" >&2
  exit 1
}
jq -e '.error == "darwin_consumer_forbidden"' "${OUT}/research-control-denied.json" >/dev/null

jq -e '
  (.profiles | map(.id) | index("cpu-short-v1") != null)
  and (.profiles | map(.id) | index("cpu-batch-v1") != null)
  and (.profiles | map(.id) | index("gpu-single-v1") != null)
' "${OUT}/research-profiles.json" >/dev/null

[[ "$(cat "${OUT}/research-submit-denied.code")" == "403" ]] || {
  echo "[FAIL] denied research submit did not return 403" >&2
  exit 1
}
jq -e \
  --arg denied_profile "${DENIED_PROFILE_ID}" '
  .error == "darwin_consumer_forbidden"
  and (.detail | contains($denied_profile))
' "${OUT}/research-submit-denied.json" >/dev/null

[[ "$(cat "${OUT}/research-submit.code")" == "200" ]] || {
  echo "[FAIL] allowed research submit did not return 200" >&2
  exit 1
}
jq -e \
  --arg allowed_profile "${ALLOWED_PROFILE_ID}" '
  .job_id > 0
  and .profile_id == $allowed_profile
' "${OUT}/research-submit.json" >/dev/null

jq -e \
  --argjson research_job_id "${RESEARCH_JOB_ID}" \
  --arg allowed_profile "${ALLOWED_PROFILE_ID}" '
  .job_id == $research_job_id
  and .profile_id == $allowed_profile
  and .state == "COMPLETED"
' "${OUT}/research-status.json" >/dev/null

jq -e \
  --argjson research_job_id "${RESEARCH_JOB_ID}" '
  .job_id == $research_job_id
' "${OUT}/research-artifact-manifest.json" >/dev/null

jq -e \
  --argjson research_job_id "${RESEARCH_JOB_ID}" '
  .job_id == $research_job_id
' "${OUT}/research-stdout.json" >/dev/null

jq -e \
  --argjson research_job_id "${RESEARCH_JOB_ID}" '
  .job_id == $research_job_id
' "${OUT}/research-stderr.json" >/dev/null

jq -e \
  --arg allowed_profile "${ALLOWED_PROFILE_ID}" '
  .total >= 1
  and (.results[0].profile_id == $allowed_profile)
' "${OUT}/research-results.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" \
  --arg allowed_profile "${ALLOWED_PROFILE_ID}" '
  .job_id == $published_result_job_id
  and .profile_id == $allowed_profile
' "${OUT}/research-result.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/research-result-manifest.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] controlled consumer expansion smoke validation passed"
