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
  timeline-source-summary.json \
  build.log \
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health-before.json \
  bootstrap-before.json \
  seed-pilot.json \
  action-hold.json \
  action-resume.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  timeline.json \
  timeline-limit.json \
  timeline-event-hold.json \
  timeline-event-recovery.json \
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
  seed-session-id.txt \
  timeline-limit.txt \
  timeline-hold-event-id.txt \
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
TIMELINE_LIMIT="$(cat "${OUT}/timeline-limit.txt")"
TIMELINE_HOLD_EVENT_ID="$(cat "${OUT}/timeline-hold-event-id.txt")"
TIMELINE_RECOVERY_EVENT_ID="$(cat "${OUT}/timeline-recovery-event-id.txt")"

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
  and (.timeline_source_present == true or .timeline_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
' "${OUT}/timeline-source-summary.json" >/dev/null

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
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == "beagle-darwin-hpc-governance"
  and .identity.workspace_id == $workspace_id
  and .identity.session_id == $session_id
  and .identity.repo == $expected_repo
  and .identity.branch == $expected_branch
  and .identity.active_dev_plane == $expected_default_dev_plane
  and .identity.fallback_active == false
  and .identity.governance_state == $resumed_state
  and .identity.governance_last_transition == $resumed_last_transition
  and .returned_events >= 6
  and .total_events >= .returned_events
' "${OUT}/timeline.json" >/dev/null

jq -e '
  def idx_kind($kind):
    (.events | to_entries[] | select(.value.event_kind == $kind) | .key) // -1;
  def idx_gov($transition):
    (.events | to_entries[] | select(.value.event_kind == "governance_transition" and .value.governance_transition == $transition) | .key) // -1;
  (idx_kind("session_bootstrap")) >= 0
  and (idx_kind("workflow_completed")) > idx_kind("session_bootstrap")
  and (idx_kind("result_reference")) > idx_kind("workflow_completed")
  and (idx_gov("hold")) > idx_kind("result_reference")
  and (idx_gov("resume")) > idx_gov("hold")
  and (idx_kind("recovery_bootstrap")) > idx_gov("resume")
  and ((.events[] | select(.event_kind == "workflow_completed") | .handoff) | contains("completed cpu-batch-v1 job"))
  and ((.events[] | select(.event_kind == "governance_transition" and .governance_transition == "hold") | .handoff) | contains("governance action hold moved canonical -> held"))
  and ((.events[] | select(.event_kind == "governance_transition" and .governance_transition == "resume") | .handoff) | contains("governance action resume moved held -> canonical"))
' "${OUT}/timeline.json" >/dev/null

jq -e \
  --argjson timeline_limit "${TIMELINE_LIMIT}" '
  .status == "ok"
  and .limit == $timeline_limit
  and .returned_events == $timeline_limit
  and (.events | length) == $timeline_limit
  and .events[0].event_kind == "governance_transition"
  and .events[0].governance_transition == "hold"
  and .events[1].event_kind == "governance_transition"
  and .events[1].governance_transition == "resume"
  and .events[2].event_kind == "recovery_bootstrap"
' "${OUT}/timeline-limit.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg hold_event_id "${TIMELINE_HOLD_EVENT_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg held_state "${EXPECTED_HELD_STATE}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .event.event_id == $hold_event_id
  and .event.event_kind == "governance_transition"
  and .event.governance_transition == "hold"
  and .event.session_id == $session_id
  and .event.from_state == "canonical"
  and .event.to_state == $held_state
' "${OUT}/timeline-event-hold.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg recovery_event_id "${TIMELINE_RECOVERY_EVENT_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .event.event_id == $recovery_event_id
  and .event.event_kind == "recovery_bootstrap"
  and .event.session_id == $session_id
  and .event.governance_state == $resumed_state
  and .event.governance_transition == $resumed_last_transition
  and .event.active_dev_plane == $expected_default_dev_plane
  and (.event.handoff // "" | contains("governance action resume moved held -> canonical"))
' "${OUT}/timeline-event-recovery.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.promotion_state.state == $resumed_state
  and .workstream_cutover_policy.promotion_state.last_transition == $resumed_last_transition
  and (.last_handoff // "" | contains("governance action resume moved held -> canonical"))
' "${OUT}/session-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" '
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
  and .same_session_line == true
  and .timeline_event_count >= 6
  and .timeline_limit_event_count >= 3
  and .fallback_active_after_restart == false
  and .active_dev_plane_after_restart == $expected_default_dev_plane
' "${OUT}/smoke.json" >/dev/null

grep -q '"action":"hold"' "${OUT}/governance-ledger-tail.jsonl"
grep -q '"action":"resume"' "${OUT}/governance-ledger-tail.jsonl"
grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] operator timeline smoke validation passed"
