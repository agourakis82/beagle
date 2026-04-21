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
  governance-policy-summary.json \
  build.log \
  bootstrap-before.json \
  session-before.json \
  control-before-seed.json \
  results-before-seed.json \
  seed-pilot.json \
  seed-result-after.json \
  seed-result-manifest-after.json \
  session-after-seed.json \
  configmap-before.yaml \
  beagle-health-held.json \
  bootstrap-held.json \
  session-held.json \
  configmap-held.yaml \
  beagle-health-after-resume.json \
  bootstrap-after-resume.json \
  session-after-resume.json \
  configmap-resumed.yaml \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-workstream.txt \
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
  seed-published-result-job-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
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

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg expected_held_state "${EXPECTED_HELD_STATE}" \
  --arg expected_held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --arg expected_resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg expected_resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .expected_workstream == $expected_workstream
  and .expected_state_before == $expected_state_before
  and .expected_last_transition_before == $expected_last_transition_before
  and .held_state == $expected_held_state
  and .held_last_transition == $expected_held_last_transition
  and .resumed_state == $expected_resumed_state
  and .resumed_last_transition == $expected_resumed_last_transition
  and (.workspace_source_present == true or .workspace_source_present == 1)
  and (.config_model_present == true or .config_model_present == 1)
  and (.config_lib_present == true or .config_lib_present == 1)
  and (.configmap_present == true or .configmap_present == 1)
  and (.workstream_spec_present == true or .workstream_spec_present == 1)
  and (.registry_present == true or .registry_present == 1)
' "${OUT}/governance-policy-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.promotion_state.state == $expected_state_before
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_last_transition_before
  and (.workstream_cutover_policy.promotion_state.allowed_states | index("held") != null)
  and (.workstream_cutover_policy.promotion_state.allowed_states | index("rollback") != null)
  and (.workstream_cutover_policy.promotion_state.allowed_states | index("recovery") != null)
  and (.workstream_cutover_policy.promotion_state.allowed_transitions | map(.name) | index("hold") != null)
  and (.workstream_cutover_policy.promotion_state.allowed_transitions | map(.name) | index("rollback") != null)
  and (.workstream_cutover_policy.promotion_state.allowed_transitions | map(.name) | index("recover") != null)
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
' "${OUT}/bootstrap-before.json" >/dev/null

SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-before.json")"
[[ -n "${SESSION_ID}" ]] || {
  echo "[FAIL] bootstrap-before.json missing session_id" >&2
  exit 1
}

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" '
  .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
' "${OUT}/session-before.json" >/dev/null

jq -e '.status == "ok"' "${OUT}/control-before-seed.json" >/dev/null
jq -e --arg seed_profile_id "${SEED_PROFILE_ID}" '.profiles | map(.id) | index($seed_profile_id) != null' "${OUT}/control-before-seed.json" >/dev/null
jq -e --arg seed_profile_id "${SEED_PROFILE_ID}" '
  .total >= 1
  and (
    (.results[0].profile_id // .entries[0].profile_id // "") == $seed_profile_id
  )
' "${OUT}/results-before-seed.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .submitted_job.profile_id == $seed_profile_id
  and .final_job.state == "COMPLETED"
  and .published_result.profile_id == $seed_profile_id
  and .last_successful_task.task_kind == "single_rich_operator_workflow"
  and .last_successful_task.workflow_run_label == $seed_run_label
' "${OUT}/seed-pilot.json" >/dev/null

jq -e \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" '
  .job_id == $published_job_id and .profile_id == $seed_profile_id
' "${OUT}/seed-result-after.json" >/dev/null

jq -e \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id
' "${OUT}/seed-result-manifest-after.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.promotion_state.state == $expected_state_before
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_last_transition_before
  and .last_workflow_kind == "single_rich_operator_workflow"
  and .last_job_profile_id == $seed_profile_id
  and .last_job_run_label == $seed_run_label
  and .last_published_result_job_id == $published_job_id
  and .last_successful_task.task_kind == "single_rich_operator_workflow"
  and (.last_handoff // "" | length > 0)
' "${OUT}/session-after-seed.json" >/dev/null

grep -Eq "BEAGLE_WORKSPACE_CUTOVER_STATE: ${EXPECTED_STATE_BEFORE}" "${OUT}/configmap-before.yaml"
grep -Eq "BEAGLE_WORKSTREAM_LAST_TRANSITION: ${EXPECTED_LAST_TRANSITION_BEFORE}" "${OUT}/configmap-before.yaml"
grep -Eq "BEAGLE_WORKSPACE_CUTOVER_STATE: ${EXPECTED_HELD_STATE}" "${OUT}/configmap-held.yaml"
grep -Eq "BEAGLE_WORKSTREAM_LAST_TRANSITION: ${EXPECTED_HELD_LAST_TRANSITION}" "${OUT}/configmap-held.yaml"
grep -Eq "BEAGLE_WORKSPACE_CUTOVER_STATE: ${EXPECTED_RESUMED_STATE}" "${OUT}/configmap-resumed.yaml"
grep -Eq "BEAGLE_WORKSTREAM_LAST_TRANSITION: ${EXPECTED_RESUMED_LAST_TRANSITION}" "${OUT}/configmap-resumed.yaml"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_held_state "${EXPECTED_HELD_STATE}" \
  --arg expected_held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.promotion_state.state == $expected_held_state
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_held_last_transition
  and .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
  and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
  and .workstream_cutover_policy.promotion_scope == $expected_promotion_scope
  and .session_id == $session_id
' "${OUT}/bootstrap-held.json" >/dev/null

SEED_HANDOFF="$(jq -r '.last_handoff // ""' "${OUT}/session-after-seed.json")"

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_held_state "${EXPECTED_HELD_STATE}" \
  --arg expected_held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --arg seed_handoff "${SEED_HANDOFF}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.promotion_state.state == $expected_held_state
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_held_last_transition
  and .last_workflow_kind == "single_rich_operator_workflow"
  and .last_job_profile_id == $seed_profile_id
  and .last_job_run_label == $seed_run_label
  and .last_published_result_job_id == $published_job_id
  and .last_successful_task.task_kind == "single_rich_operator_workflow"
  and (.last_handoff // "") == $seed_handoff
' "${OUT}/session-held.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg expected_resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.promotion_state.state == $expected_resumed_state
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_resumed_last_transition
  and .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
  and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
  and .workstream_cutover_policy.promotion_scope == $expected_promotion_scope
  and .session_id == $session_id
' "${OUT}/bootstrap-after-resume.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg expected_resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --arg seed_handoff "${SEED_HANDOFF}" \
  --argjson published_job_id "${SEED_PUBLISHED_RESULT_JOB_ID}" '
  .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .workstream_cutover_policy.promotion_state.state == $expected_resumed_state
  and .workstream_cutover_policy.promotion_state.last_transition == $expected_resumed_last_transition
  and .last_workflow_kind == "single_rich_operator_workflow"
  and .last_job_profile_id == $seed_profile_id
  and .last_job_run_label == $seed_run_label
  and .last_published_result_job_id == $published_job_id
  and .last_successful_task.task_kind == "single_rich_operator_workflow"
  and (.last_handoff // "") == $seed_handoff
' "${OUT}/session-after-resume.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg expected_held_state "${EXPECTED_HELD_STATE}" \
  --arg expected_held_last_transition "${EXPECTED_HELD_LAST_TRANSITION}" \
  --arg expected_resumed_state "${EXPECTED_RESUMED_STATE}" \
  --arg expected_resumed_last_transition "${EXPECTED_RESUMED_LAST_TRANSITION}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_workstream == $expected_workstream
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .state_before == $expected_state_before
  and .last_transition_before == $expected_last_transition_before
  and .held_state == $expected_held_state
  and .held_last_transition == $expected_held_last_transition
  and .resumed_state == $expected_resumed_state
  and .resumed_last_transition == $expected_resumed_last_transition
  and .seed_profile_id == $seed_profile_id
  and .seed_run_label == $seed_run_label
  and .seed_final_job_state == "COMPLETED"
  and .same_session_line == true
  and .last_handoff_preserved_while_held == true
  and .last_result_preserved_while_held == true
  and .last_handoff_preserved_after_resume == true
  and .last_result_preserved_after_resume == true
  and .active_dev_plane_held == $expected_default_dev_plane
  and .active_dev_plane_after_resume == $expected_default_dev_plane
  and .fallback_active_held == false
  and .fallback_active_after_resume == false
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).+UP|Slurmctld\(primary\) at .+ is UP' "${OUT}/final-cluster-health.txt"

echo "[OK] workstream governance smoke validation passed"
