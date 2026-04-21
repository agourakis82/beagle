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
  beagle-health-before.json \
  seed-pilot-request.json \
  seed-pilot.json \
  workstreams-list.json \
  workstream-detail.json \
  workstream-recipes.json \
  workstream-status.json \
  workstream-last-result.json \
  workstream-handoff.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  workstream-status-after-restart.json \
  timeline.json \
  timeline-limit.json \
  timeline-event-workflow.json \
  timeline-event-recovery.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-workstream.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-branch-lineage.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  expected-governance-state.txt \
  expected-last-transition.txt \
  seed-profile-id.txt \
  seed-run-label.txt \
  seed-published-result-job-id.txt \
  seed-session-id.txt \
  timeline-limit.txt \
  timeline-workflow-event-id.txt \
  timeline-recovery-event-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_BRANCH_LINEAGE="$(cat "${OUT}/expected-branch-lineage.txt")"
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_PROMOTION_SCOPE="$(cat "${OUT}/expected-promotion-scope.txt")"
EXPECTED_GOVERNANCE_STATE="$(cat "${OUT}/expected-governance-state.txt")"
EXPECTED_LAST_TRANSITION="$(cat "${OUT}/expected-last-transition.txt")"
SEED_PROFILE_ID="$(cat "${OUT}/seed-profile-id.txt")"
SEED_RUN_LABEL="$(cat "${OUT}/seed-run-label.txt")"
SEED_PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
SEED_SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"
TIMELINE_LIMIT="$(cat "${OUT}/timeline-limit.txt")"
TIMELINE_WORKFLOW_EVENT_ID="$(cat "${OUT}/timeline-workflow-event-id.txt")"
TIMELINE_RECOVERY_EVENT_ID="$(cat "${OUT}/timeline-recovery-event-id.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .expected_workstream == $expected_workstream
  and .expected_branch == $expected_branch
  and .expected_branch_lineage == $expected_branch_lineage
  and .expected_governance_state == $expected_governance_state
  and .expected_last_transition == $expected_last_transition
  and (.workspace_source_present == true or .workspace_source_present == 1)
  and (.control_room_source_present == true or .control_room_source_present == 1)
  and (.timeline_source_present == true or .timeline_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.spec_present == true or .spec_present == 1)
  and (.recipe_repo_present == true or .recipe_repo_present == 1)
  and (.recipe_cpu_present == true or .recipe_cpu_present == 1)
  and (.recipe_recovery_present == true or .recipe_recovery_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
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
  and .last_successful_task.branch == $expected_branch
  and ((.handoff // "") | contains($workspace_id))
  and ((.handoff // "") | contains($expected_branch))
' "${OUT}/seed-pilot.json" >/dev/null

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
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" '
  .status == "ok"
  and .registry_entry.id == $expected_workstream
  and .spec.id == $expected_workstream
  and .spec.repo == $expected_repo
  and .spec.default_branch == $expected_branch
  and .spec.default_dev_plane == $expected_default_dev_plane
  and .spec.vm_fallback_role == $expected_vm_fallback_role
  and (.recipes | length) >= 3
' "${OUT}/workstream-detail.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .recipe_count >= 3
  and (.recipes | map(.kind) | index("repo_native_dev_loop") != null)
  and (.recipes | map(.kind) | index("operator_cpu_loop") != null)
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
  and .recipe_count >= 3
  and .live_session.workspace_id == $workspace_id
  and .live_session.session_id == $session_id
  and .live_session.active_dev_plane == $expected_default_dev_plane
  and .live_session.fallback_active == false
  and .handoff_ready == true
  and .result_ready == true
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

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_branch == $expected_branch
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.branch_lineage == $expected_branch
  and .workstream_cutover_policy.promotion_state.state == $expected_governance_state
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_last_transition
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.promotion_state.state == $expected_governance_state
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_last_transition
' "${OUT}/session-after-restart.json" >/dev/null

jq -e \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .live_session.session_id == $session_id
' "${OUT}/workstream-status-after-restart.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .identity.workspace_id == $workspace_id
  and .identity.session_id == $session_id
  and .identity.repo == $expected_repo
  and .identity.branch == $expected_branch
  and .identity.active_dev_plane == $expected_default_dev_plane
  and .identity.fallback_active == false
  and .identity.governance_state == $expected_governance_state
  and .returned_events >= 4
  and .total_events >= .returned_events
  and (.events | map(.event_kind) | index("workflow_completed") != null)
  and (.events | map(.event_kind) | index("result_reference") != null)
  and (.events | map(.event_kind) | index("recovery_bootstrap") != null)
' "${OUT}/timeline.json" >/dev/null

jq -e \
  --argjson timeline_limit "${TIMELINE_LIMIT}" '
  .status == "ok"
  and .limit == $timeline_limit
  and .returned_events == $timeline_limit
  and (.events | length) == $timeline_limit
' "${OUT}/timeline-limit.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workflow_event_id "${TIMELINE_WORKFLOW_EVENT_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .event.event_id == $workflow_event_id
  and .event.event_kind == "workflow_completed"
  and .event.session_id == $session_id
  and .event.branch == $expected_branch
  and .event.profile_id == $seed_profile_id
  and .event.result_job_id == $published_job_id
' "${OUT}/timeline-event-workflow.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg recovery_event_id "${TIMELINE_RECOVERY_EVENT_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .event.event_id == $recovery_event_id
  and .event.event_kind == "recovery_bootstrap"
  and .event.session_id == $session_id
  and .event.active_dev_plane == $expected_default_dev_plane
  and .event.governance_state == $expected_governance_state
' "${OUT}/timeline-event-recovery.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .expected_workstream == $expected_workstream
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_branch_lineage == $expected_branch_lineage
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .after_restart_workstream == $expected_workstream
  and .detail_branch == $expected_branch
  and .status_active_dev_plane == $expected_default_dev_plane
  and .handoff_present == true
  and .recipes_count >= 3
  and .timeline_returned_events >= 4
  and .timeline_limit_returned_events >= 1
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] second real workstream cutover smoke validation passed"
