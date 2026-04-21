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
  control-room-actions-source-summary.json \
  build.log \
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health-before.json \
  bootstrap-before.json \
  seed-pilot.json \
  cockpit-before.json \
  status-before.json \
  handoff-before.json \
  action-hold.json \
  cockpit-held.json \
  status-held.json \
  handoff-held.json \
  action-resume.json \
  cockpit-resumed.json \
  status-resumed.json \
  handoff-resumed.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  cockpit-after-restart.json \
  status-after-restart.json \
  governance-ledger-tail.jsonl \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-workstream.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  expected-state-before.txt \
  expected-last-transition-before.txt \
  expected-held-state.txt \
  expected-held-last-transition.txt \
  expected-resumed-state.txt \
  expected-resumed-last-transition.txt \
  seed-profile-id.txt \
  seed-run-label.txt \
  seed-published-result-job-id.txt \
  seed-session-id.txt; do
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
EXPECTED_STATE_BEFORE="$(cat "${OUT}/expected-state-before.txt")"
EXPECTED_LAST_TRANSITION_BEFORE="$(cat "${OUT}/expected-last-transition-before.txt")"
EXPECTED_HELD_STATE="$(cat "${OUT}/expected-held-state.txt")"
EXPECTED_HELD_LAST_TRANSITION="$(cat "${OUT}/expected-held-last-transition.txt")"
EXPECTED_RESUMED_STATE="$(cat "${OUT}/expected-resumed-state.txt")"
EXPECTED_RESUMED_LAST_TRANSITION="$(cat "${OUT}/expected-resumed-last-transition.txt")"
SEED_PROFILE_ID="$(cat "${OUT}/seed-profile-id.txt")"
SEED_RUN_LABEL="$(cat "${OUT}/seed-run-label.txt")"
SEED_PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
SEED_SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg held_state "${EXPECTED_HELD_STATE}" \
  --arg held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .expected_workstream == $expected_workstream
  and .expected_state_before == $expected_state_before
  and .expected_last_transition_before == $expected_last_transition_before
  and .held_state == $held_state
  and .held_last_transition == $held_last_transition
  and .resumed_state == $resumed_state
  and .resumed_last_transition == $resumed_last_transition
  and (.action_source_present == true or .action_source_present == 1)
  and (.workspace_source_present == true or .workspace_source_present == 1)
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
' "${OUT}/control-room-actions-source-summary.json" >/dev/null

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

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .envelope.workspace_id == $workspace_id
  and .envelope.session_id == $session_id
  and .envelope.repo == $expected_repo
  and .envelope.branch == $expected_branch
  and .envelope.default_dev_plane == $expected_default_dev_plane
  and .envelope.vm_fallback_role == $expected_vm_fallback_role
  and .envelope.governance_state == $expected_state_before
  and .envelope.governance_last_transition == $expected_last_transition_before
  and .actions.hold.enabled == true
  and .actions.resume.enabled == false
  and (.tool_dock | length) == 3
' "${OUT}/cockpit-before.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .repo == $expected_repo
  and .default_branch == $expected_branch
  and .default_dev_plane == $expected_default_dev_plane
  and .vm_fallback_role == $expected_vm_fallback_role
  and .governance_state == $expected_state_before
  and .governance_last_transition == $expected_last_transition_before
  and .live_session.workspace_id == $workspace_id
  and .live_session.session_id == $session_id
  and .live_session.active_dev_plane == $expected_default_dev_plane
  and .live_session.fallback_active == false
  and .handoff_ready == true
  and .result_ready == true
  and .actions.hold.enabled == true
  and .actions.resume.enabled == false
' "${OUT}/status-before.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg held_state "${EXPECTED_HELD_STATE}" \
  --arg held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .action == "hold"
  and .session_id == $session_id
  and .previous_governance_state == "canonical"
  and .governance_state == $held_state
  and .governance_last_transition == $held_last_transition
  and .fallback_active == false
  and .ledger_appended == true
  and (.last_handoff // "" | contains("governance action hold moved canonical -> held"))
  and .last_result_reference.job_id == $published_job_id
' "${OUT}/action-hold.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg held_state "${EXPECTED_HELD_STATE}" \
  --arg held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .governance_state == $held_state
  and .governance_last_transition == $held_last_transition
  and .live_session.session_id == $session_id
  and .live_session.fallback_active == false
  and .handoff_ready == true
  and .result_ready == true
  and .actions.hold.enabled == false
  and .actions.resume.enabled == true
' "${OUT}/status-held.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg held_state "${EXPECTED_HELD_STATE}" \
  --arg held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .envelope.session_id == $session_id
  and .envelope.governance_state == $held_state
  and .envelope.governance_last_transition == $held_last_transition
  and .actions.hold.enabled == false
  and .actions.resume.enabled == true
  and .last_result.reference.job_id == $published_job_id
' "${OUT}/cockpit-held.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .live_session.session_id == $session_id
  and .handoff_present == true
  and (.last_handoff // "" | contains("governance action hold moved canonical -> held"))
  and .last_result_reference.job_id == $published_job_id
' "${OUT}/handoff-held.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .action == "resume"
  and .session_id == $session_id
  and .previous_governance_state == "held"
  and .governance_state == $resumed_state
  and .governance_last_transition == $resumed_last_transition
  and .fallback_active == false
  and .ledger_appended == true
  and (.last_handoff // "" | contains("governance action resume moved held -> canonical"))
  and .last_result_reference.job_id == $published_job_id
' "${OUT}/action-resume.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .governance_state == $resumed_state
  and .governance_last_transition == $resumed_last_transition
  and .live_session.session_id == $session_id
  and .live_session.fallback_active == false
  and .actions.hold.enabled == true
  and .actions.resume.enabled == false
' "${OUT}/status-resumed.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .envelope.session_id == $session_id
  and .envelope.governance_state == $resumed_state
  and .envelope.governance_last_transition == $resumed_last_transition
  and .actions.hold.enabled == true
  and .actions.resume.enabled == false
  and .last_result.reference.job_id == $published_job_id
' "${OUT}/cockpit-resumed.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .live_session.session_id == $session_id
  and .handoff_present == true
  and (.last_handoff // "" | contains("governance action resume moved held -> canonical"))
  and .last_result_reference.job_id == $published_job_id
' "${OUT}/handoff-resumed.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.promotion_state.state == $resumed_state
  and .workstream_cutover_policy.promotion_state.last_transition == $resumed_last_transition
  and .last_published_result_job_id == $published_job_id
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.promotion_state.state == $resumed_state
  and .workstream_cutover_policy.promotion_state.last_transition == $resumed_last_transition
  and (.last_handoff // "" | contains("governance action resume moved held -> canonical"))
  and .last_published_result_job_id == $published_job_id
' "${OUT}/session-after-restart.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .envelope.session_id == $session_id
  and .envelope.governance_state == $resumed_state
  and .envelope.governance_last_transition == $resumed_last_transition
  and .actions.hold.enabled == true
  and .actions.resume.enabled == false
' "${OUT}/cockpit-after-restart.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .governance_state == $resumed_state
  and .governance_last_transition == $resumed_last_transition
  and .live_session.session_id == $session_id
  and .actions.hold.enabled == true
  and .actions.resume.enabled == false
' "${OUT}/status-after-restart.json" >/dev/null

jq -s -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  map(select(.workspace_id == $workspace_id and .session_id == $session_id))
  | map(.action)
  | (index("hold") != null and index("resume") != null)
' "${OUT}/governance-ledger-tail.jsonl" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .expected_workstream == $expected_workstream
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .seed_profile_id == $seed_profile_id
  and .seed_run_label == $seed_run_label
  and .seed_session_id == $session_id
  and .seed_published_result_job_id == $published_job_id
  and .held_state == "held"
  and .held_last_transition == "hold"
  and .resumed_state == $resumed_state
  and .resumed_last_transition == $resumed_last_transition
  and .same_session_line == true
  and (.hold_handoff | contains("governance action hold moved canonical -> held"))
  and (.resume_handoff | contains("governance action resume moved held -> canonical"))
  and .hold_last_result_job_id == $published_job_id
  and .resume_last_result_job_id == $published_job_id
  and .cockpit_recipe_count >= 4
  and .fallback_active_after_restart == false
  and .active_dev_plane_after_restart == $expected_default_dev_plane
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] control room actions smoke validation passed"
