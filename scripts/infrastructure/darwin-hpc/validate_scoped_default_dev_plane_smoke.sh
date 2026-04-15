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
  bootstrap-after-deploy.json \
  bridge-execute.json \
  bridge-ledger-tail.jsonl \
  policy-summary.json \
  pilot.json \
  smoke.json \
  session-after-restart.json \
  final-cluster-health.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  run-label.txt \
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
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_PROMOTION_SCOPE="$(cat "${OUT}/expected-promotion-scope.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/published-result-job-id.txt")"

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .dev_plane_policy == null
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .policy_field_name == "dev_plane_policy"
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and (.source_policy_present == true or .source_policy_present == 1)
  and (.config_default_present == true or .config_default_present == 1)
  and (.config_vm_role_present == true or .config_vm_role_present == 1)
  and (.config_scope_present == true or .config_scope_present == 1)
' "${OUT}/policy-summary.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .status == "ok"
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
' "${OUT}/bootstrap-after-deploy.json" >/dev/null

jq -e '
  .status == "success"
  and .provider == "deepseek"
' "${OUT}/bridge-execute.json" >/dev/null

grep -Fq '"provider":"deepseek"' "${OUT}/bridge-ledger-tail.jsonl"

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
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg run_label "${RUN_LABEL}" '
  .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .postdeploy_default_dev_plane == $expected_default_dev_plane
  and .postdeploy_vm_fallback_role == $expected_vm_fallback_role
  and .postdeploy_promotion_scope == $expected_promotion_scope
  and .bridge_provider == "deepseek"
  and .bridge_status == "success"
  and .pilot_status == "ok"
  and .workflow_run_label == $run_label
  and .predeploy_session_id != ""
  and .postdeploy_session_id == .predeploy_session_id
  and .after_restart_session_id == .predeploy_session_id
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
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg run_label "${RUN_LABEL}" '
  .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .last_job_run_label == $run_label
  and .last_handoff != null
  and (.last_handoff | contains($expected_repo))
  and (.last_handoff | contains($expected_branch))
' "${OUT}/session-after-restart.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] scoped default dev plane smoke validation passed"
