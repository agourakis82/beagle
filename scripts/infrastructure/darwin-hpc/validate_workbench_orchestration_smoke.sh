#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/workbench-orchestration}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B252_BASE_OUT="${B252_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/collaborative-compute-experiment-workbench}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for file in \
  source-summary.json \
  health-before.json \
  health-after.json \
  workbench-before.json \
  bootstrap-before.json \
  session-before.json \
  workbench-run-request.json \
  workbench-run-dispatch-response.json \
  workbench-reservation.json \
  workbench-run.json \
  workbench-execution-state.json \
  workbench-result-binding.json \
  workbench-context-after-run.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  workbench-run-after-restart.json \
  workbench-result-binding-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  session-id.txt \
  run-label.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B252_BASE_OUT}/smoke.json"

jq -e '
  .workbench_reservation_source_present == 1 and
  .workbench_run_source_present == 1 and
  .workbench_result_binding_source_present == 1 and
  .workbench_orchestration_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .reservation_schema_present == 1 and
  .run_schema_present == 1 and
  .result_binding_schema_present == 1 and
  .orchestration_bundle_schema_present == 1 and
  .b252_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.2" and
  .same_beagle_owned_identity == true and
  .vscode_ready == true and
  .cursor_ready == true
' "${B252_BASE_OUT}/smoke.json" >/dev/null

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/session-id.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"

[[ -n "${WORKSPACE_ID}" ]] || {
  echo "[FAIL] workspace-id.txt is empty" >&2
  exit 1
}
[[ -n "${SESSION_ID}" ]] || {
  echo "[FAIL] session-id.txt is empty" >&2
  exit 1
}
[[ -n "${RUN_LABEL}" ]] || {
  echo "[FAIL] run-label.txt is empty" >&2
  exit 1
}

jq -e '.status == "ok"' "${OUT}/health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/health-after.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok" and
  .phase == "B25.2" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .compute_selection.scheduler_kind == "slurm-backed-profile-tenancy" and
  .collaboration_access.partner_access_state == "operator-mediated-ready"
' "${OUT}/workbench-before.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok" and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  (.recovered_session == false or .recovered_session == true)
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e '
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1" and
  .recipe_kind == "workbench-smoke" and
  .experiment_id == "b253-workbench-smoke"
' "${OUT}/workbench-run-request.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.3"
' "${OUT}/workbench-run-dispatch-response.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .phase == "B25.3" and
  .contract_kind == "workbench-reservation" and
  .contract_version == "beagle-workbench-reservation-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .reservation_state == "reserved" and
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .compute_profile_id == "cpu-short-v1" and
  .compute_kind == "cpu" and
  .compute_partition == "cpu" and
  .gpu_requested == false and
  .scheduler_kind == "slurm-backed-profile-tenancy" and
  .quota_policy_kind == "typed-profile-quota-aware" and
  .submit_mode == "scoped-profile-submit" and
  .gpu_access_mode == "typed-isolated-gpu" and
  .bounded_partner_access == true and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis"
' "${OUT}/workbench-reservation.json" >/dev/null

RUN_ID="$(jq -r '.run_id' "${OUT}/workbench-run.json")"
RESERVATION_ID="$(jq -r '.reservation_id' "${OUT}/workbench-run.json")"
SUBMITTED_JOB_ID="$(jq -r '.submitted_job_id' "${OUT}/workbench-run.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result_job_id' "${OUT}/workbench-run.json")"

[[ -n "${RUN_ID}" && "${RUN_ID}" != "null" ]] || {
  echo "[FAIL] workbench-run.json missing run_id" >&2
  exit 1
}

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg reservation_id "${RESERVATION_ID}" '
  .phase == "B25.3" and
  .contract_kind == "workbench-run-orchestration" and
  .contract_version == "beagle-workbench-run-orchestration-v1" and
  .reservation_id == $reservation_id and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1" and
  .run_label != "" and
  .scheduler_kind == "slurm-backed-profile-tenancy" and
  .submit_mode == "scoped-profile-submit" and
  .current_state == "succeeded" and
  (.lifecycle_transitions | map(.state)) == ["reserved", "queued", "running", "succeeded"] and
  (.submitted_job_id | tonumber) > 0 and
  (.published_result_job_id | tonumber) > 0 and
  (.published_result_manifest_key | length) > 0 and
  .artifact_ready == true and
  .bounded_partner_access == true and
  .direct_cluster_admin_grant == false and
  .direct_kubernetes_access_grant == false
' "${OUT}/workbench-run.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg reservation_id "${RESERVATION_ID}" \
  --arg run_id "${RUN_ID}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .phase == "B25.3" and
  .contract_kind == "workbench-result-binding" and
  .contract_version == "beagle-workbench-result-binding-v1" and
  .reservation_id == $reservation_id and
  .run_id == $run_id and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .compute_profile_id == "cpu-short-v1" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .submitted_job_id == $submitted_job_id and
  .published_result_job_id == $published_result_job_id and
  .final_job_state == "COMPLETED" and
  .artifact_ready == true and
  (.result_refs | length) == 3 and
  ((.result_refs | map(.ref_kind) | sort) == ["published-result", "result-manifest", "submitted-job"])
' "${OUT}/workbench-result-binding.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .last_workflow_kind == "operator_real_workflow_pilot" and
  .last_job_id == $submitted_job_id and
  .last_job_profile_id == "cpu-short-v1" and
  .last_job_run_label == $run_label and
  .last_published_result_job_id == $published_result_job_id and
  .last_published_result_profile_id == "cpu-short-v1" and
  .last_result_lookup_job_id == $published_result_job_id and
  .last_result_lookup_profile_id == "cpu-short-v1" and
  .last_successful_task.task_kind == "operator_real_workflow_pilot" and
  .last_successful_task.task_state == "completed" and
  .last_successful_task.profile_id == "cpu-short-v1" and
  .last_successful_task.workflow_run_label == $run_label and
  .last_successful_task.submitted_job_id == $submitted_job_id and
  .last_successful_task.published_result_job_id == $published_result_job_id
' "${OUT}/workbench-execution-state.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok" and
  .phase == "B25.2" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .collaboration_access.partner_access_state == "operator-mediated-ready" and
  .compute_selection.scheduler_kind == "slurm-backed-profile-tenancy" and
  .run.current_profile_id == "cpu-short-v1" and
  .run.selected_subagent_id == "experiments" and
  .run.current_state == "succeeded" and
  .run.last_result_reference.job_id == $published_result_job_id and
  .run.last_result_reference.profile_id == "cpu-short-v1" and
  (
    .run.last_result_reference.state == "COMPLETED" or
    (
      .run.last_result_reference.state == null and
      (.run.last_result_reference.manifest_key | length) > 0
    )
  )
' "${OUT}/workbench-context-after-run.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok" and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .last_workflow_kind == "operator_real_workflow_pilot" and
  .last_job_id == $submitted_job_id and
  .last_published_result_job_id == $published_result_job_id and
  .last_result_lookup_job_id == $published_result_job_id and
  .last_successful_task.task_kind == "operator_real_workflow_pilot"
' "${OUT}/session-after-restart.json" >/dev/null

jq -e \
  --arg run_id "${RUN_ID}" \
  --arg reservation_id "${RESERVATION_ID}" '
  .run_id == $run_id and
  .reservation_id == $reservation_id and
  .current_state == "succeeded"
' "${OUT}/workbench-run-after-restart.json" >/dev/null

jq -e \
  --arg run_id "${RUN_ID}" \
  --arg reservation_id "${RESERVATION_ID}" '
  .run_id == $run_id and
  .reservation_id == $reservation_id and
  (.result_refs | length) == 3
' "${OUT}/workbench-result-binding-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok" and
  .phase == "B25.3" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .requester_role_id == "partner-dev" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1" and
  .reservation_state == "reserved" and
  .canary_stage == "bounded-workbench-run-live" and
  .run_current_state == "succeeded" and
  .lifecycle_states == ["reserved", "queued", "running", "succeeded"] and
  .submitted_job_id == $submitted_job_id and
  .published_result_job_id == $published_result_job_id and
  .result_refs_bound == 3 and
  .bounded_partner_access == true and
  .partner_access_state == "operator-mediated-ready" and
  .live_selected_subagent_id == "experiments" and
  .execution_current_state == "succeeded" and
  .workspace_last_workflow_kind == "operator_real_workflow_pilot" and
  .workspace_last_job_profile_id == "cpu-short-v1" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] workbench orchestration smoke artifacts validated"
