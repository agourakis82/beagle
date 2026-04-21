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
  scope-summary.json \
  bootstrap-after-deploy.json \
  session-after-deploy.json \
  bridge-execute.json \
  bridge-ledger-tail.jsonl \
  pilot.json \
  fallback-enter.json \
  session-during-fallback.json \
  fallback-return.json \
  session-after-return.json \
  fallback-ledger-tail.jsonl \
  smoke.json \
  session-after-restart.json \
  bootstrap-after-restart.json \
  final-cluster-health.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  fallback-reason.txt \
  return-reason.txt \
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
FALLBACK_REASON="$(cat "${OUT}/fallback-reason.txt")"
RETURN_REASON="$(cat "${OUT}/return-reason.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/published-result-job-id.txt")"

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" '
  .status == "ok"
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and (
    .dev_plane_policy == null
    or (
      .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
      and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
      and (.dev_plane_policy.promotion_scope // "") != ""
    )
  )
  and (.active_dev_plane == null or .active_dev_plane == $expected_default_dev_plane)
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and (.included_scope | index("beagle-darwin")) != null
  and (.included_scope | index("beagle-monorepo")) != null
  and (.included_scope | index("docs-contracts-templates-scripts-darwin-hpc")) != null
  and (.excluded_scope | index("edge-ingress")) != null
  and (.excluded_scope | index("high-availability")) != null
  and (.excluded_scope | index("provider-expansion")) != null
  and (.excluded_scope | index("phase-b9-b10-b11-b12-reopen")) != null
  and (.model_scope_present == true or .model_scope_present == 1)
  and (.lib_scope_present == true or .lib_scope_present == 1)
  and (.workspace_scope_present == true or .workspace_scope_present == 1)
  and (.config_scope_present == true or .config_scope_present == 1)
  and (.workspace_policy_present == true or .workspace_policy_present == 1)
  and (.fallback_route_present == true or .fallback_route_present == 1)
' "${OUT}/scope-summary.json" >/dev/null

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
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
' "${OUT}/bootstrap-after-deploy.json" >/dev/null

jq -e \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
' "${OUT}/session-after-deploy.json" >/dev/null

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
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/result-after.json" >/dev/null

jq -e \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_result_job_id
' "${OUT}/result-manifest-after.json" >/dev/null

jq -e \
  --arg fallback_reason "${FALLBACK_REASON}" '
  .status == "ok"
  and .active_dev_plane == "vm-fallback"
  and .fallback_active == true
  and .fallback_event_count == 1
  and .last_fallback_event.event_kind == "fallback_entered"
  and .last_fallback_event.reason == $fallback_reason
' "${OUT}/fallback-enter.json" >/dev/null

jq -e \
  --arg fallback_reason "${FALLBACK_REASON}" '
  .active_dev_plane == "vm-fallback"
  and .fallback_active == true
  and .fallback_event_count == 1
  and .last_fallback_event.event_kind == "fallback_entered"
  and .last_fallback_event.reason == $fallback_reason
' "${OUT}/session-during-fallback.json" >/dev/null

jq -e \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg return_reason "${RETURN_REASON}" '
  .status == "ok"
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .fallback_event_count == 1
  and .last_fallback_event.event_kind == "returned_to_canonical"
  and .last_fallback_event.reason == $return_reason
  and (.last_fallback_event.duration_seconds // -1) >= 0
' "${OUT}/fallback-return.json" >/dev/null

jq -e \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .last_fallback_event.event_kind == "returned_to_canonical"
' "${OUT}/session-after-return.json" >/dev/null

grep -Fq '"event_kind":"fallback_entered"' "${OUT}/fallback-ledger-tail.jsonl"
grep -Fq '"event_kind":"returned_to_canonical"' "${OUT}/fallback-ledger-tail.jsonl"
grep -Fq "\"reason\":\"${FALLBACK_REASON}\"" "${OUT}/fallback-ledger-tail.jsonl"
grep -Fq "\"reason\":\"${RETURN_REASON}\"" "${OUT}/fallback-ledger-tail.jsonl"

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
  and .after_return_session_id == .predeploy_session_id
  and .after_restart_session_id == .predeploy_session_id
  and .return_duration_seconds >= 0
' "${OUT}/smoke.json" >/dev/null

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
  and .active_dev_plane == $expected_default_dev_plane
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .last_fallback_event.event_kind == "returned_to_canonical"
  and .last_handoff != null
  and (.last_handoff | contains("returned to " + $expected_default_dev_plane))
' "${OUT}/session-after-restart.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] scoped dev plane expansion smoke validation passed"
