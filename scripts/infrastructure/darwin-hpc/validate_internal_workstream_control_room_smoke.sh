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
  control-room-source-summary.json \
  build.log \
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health-before.json \
  bootstrap-before.json \
  seed-pilot.json \
  workstreams-list.json \
  workstream-detail.json \
  workstream-recipes.json \
  workstream-status.json \
  workstream-last-result.json \
  workstream-handoff.json \
  workstream-hold.json \
  workstream-hold.http \
  workstream-resume.json \
  workstream-resume.http \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-workstream.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  expected-governance-state.txt \
  expected-last-transition.txt \
  seed-profile-id.txt \
  seed-run-label.txt \
  seed-published-result-job-id.txt \
  expected-action-http-status.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_PROMOTION_SCOPE="$(cat "${OUT}/expected-promotion-scope.txt")"
EXPECTED_GOVERNANCE_STATE="$(cat "${OUT}/expected-governance-state.txt")"
EXPECTED_LAST_TRANSITION="$(cat "${OUT}/expected-last-transition.txt")"
SEED_PROFILE_ID="$(cat "${OUT}/seed-profile-id.txt")"
SEED_RUN_LABEL="$(cat "${OUT}/seed-run-label.txt")"
SEED_PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
EXPECTED_ACTION_HTTP_STATUS="$(cat "${OUT}/expected-action-http-status.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .expected_workstream == $expected_workstream
  and .expected_governance_state == $expected_governance_state
  and .expected_last_transition == $expected_last_transition
  and (.control_room_source_present == true or .control_room_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
' "${OUT}/control-room-source-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .submitted_job.profile_id == $seed_profile_id
  and .final_job.state == "COMPLETED"
  and .published_result.profile_id == $seed_profile_id
  and .last_successful_task.workflow_run_label == $seed_run_label
' "${OUT}/seed-pilot.json" >/dev/null

SEED_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/seed-pilot.json")"
[[ -n "${SEED_SESSION_ID}" ]] || {
  echo "[FAIL] seed-pilot.json missing session_id" >&2
  exit 1
}

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" '
  .status == "ok"
  and (.workstreams | map(.id) | index($expected_workstream) != null)
  and ((.workstreams[] | select(.id == $expected_workstream) | .latest_session.workspace_id) == $workspace_id)
' "${OUT}/workstreams-list.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .status == "ok"
  and .registry_entry.id == $expected_workstream
  and .spec.id == $expected_workstream
  and .spec.repo == $expected_repo
  and .spec.default_branch == $expected_branch
  and .spec.default_dev_plane == $expected_default_dev_plane
  and .spec.vm_fallback_role == $expected_vm_fallback_role
  and .status_view.workstream_id == $expected_workstream
  and .status_view.governance_state == $expected_governance_state
  and .status_view.governance_last_transition == $expected_last_transition
  and (.recipes | length) >= 4
' "${OUT}/workstream-detail.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .recipe_count >= 4
  and (.recipes | map(.kind) | index("repo_native_dev_loop") != null)
  and (.recipes | map(.kind) | index("operator_cpu_loop") != null)
  and (.recipes | map(.kind) | index("operator_gpu_loop") != null)
  and (.recipes | map(.kind) | index("recovery_resume_loop") != null)
' "${OUT}/workstream-recipes.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .repo == $expected_repo
  and .default_branch == $expected_branch
  and .default_dev_plane == $expected_default_dev_plane
  and .vm_fallback_role == $expected_vm_fallback_role
  and .governance_state == $expected_governance_state
  and .governance_last_transition == $expected_last_transition
  and .recipe_count >= 4
  and .live_session.workspace_id == $workspace_id
  and .live_session.session_id == $session_id
  and .live_session.active_dev_plane == $expected_default_dev_plane
  and .live_session.fallback_active == false
  and .handoff_ready == true
  and .result_ready == true
  and .actions.hold.enabled == false
  and .actions.resume.enabled == false
' "${OUT}/workstream-status.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .live_session.session_id == $session_id
  and .last_result_reference.job_id == $published_job_id
  and .result.job_id == $published_job_id
  and .manifest.job_id == $published_job_id
  and .result.profile_id == $seed_profile_id
  and .manifest.profile_id == $seed_profile_id
' "${OUT}/workstream-last-result.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .live_session.session_id == $session_id
  and .handoff_present == true
  and (.last_handoff // "" | length > 0)
  and .last_result_reference.job_id == $published_job_id
' "${OUT}/workstream-handoff.json" >/dev/null

[[ "$(tr -d '[:space:]' < "${OUT}/workstream-hold.http")" == "${EXPECTED_ACTION_HTTP_STATUS}" ]] || {
  echo "[FAIL] unexpected hold HTTP status" >&2
  exit 1
}
[[ "$(tr -d '[:space:]' < "${OUT}/workstream-resume.http")" == "${EXPECTED_ACTION_HTTP_STATUS}" ]] || {
  echo "[FAIL] unexpected resume HTTP status" >&2
  exit 1
}

jq -e '.error == "workstream_control_action_not_enabled"' "${OUT}/workstream-hold.json" >/dev/null
jq -e '.error == "workstream_control_action_not_enabled"' "${OUT}/workstream-resume.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --arg expected_action_http_status "${EXPECTED_ACTION_HTTP_STATUS}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .expected_workstream == $expected_workstream
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .governance_state == $expected_governance_state
  and .governance_last_transition == $expected_last_transition
  and .status_active_dev_plane == $expected_default_dev_plane
  and .status_fallback_active == false
  and .handoff_present == true
  and .recipes_count >= 4
  and .hold_http_status == $expected_action_http_status
  and .resume_http_status == $expected_action_http_status
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] internal workstream control room smoke validation passed"
