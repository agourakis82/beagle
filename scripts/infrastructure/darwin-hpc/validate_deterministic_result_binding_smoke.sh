#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/deterministic-result-binding}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B253_BASE_OUT="${B253_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/workbench-orchestration}"

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
  run-result-identity-receipt.json \
  run-scoped-publication.json \
  deterministic-result-binding.json \
  workbench-context-after-deterministic-binding.json \
  workbench-execution-state.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  run-result-identity-receipt-after-restart.json \
  run-scoped-publication-after-restart.json \
  deterministic-result-binding-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  session-id.txt \
  run-label.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B253_BASE_OUT}/smoke.json"

jq -e '
  .workspace_plane_source_present == 1 and
  .workbench_run_source_present == 1 and
  .workbench_result_binding_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .run_scoped_publication_schema_present == 1 and
  .deterministic_result_binding_schema_present == 1 and
  .run_result_identity_receipt_schema_present == 1 and
  .b253_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.3" and
  .same_beagle_owned_identity == true and
  .run_current_state == "succeeded"
' "${B253_BASE_OUT}/smoke.json" >/dev/null

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
  .recipe_kind == "deterministic-binding-smoke" and
  .experiment_id == "b254-deterministic-binding-smoke"
' "${OUT}/workbench-run-request.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.3" and
  .run_result_identity_receipt.phase == "B25.4" and
  .run_scoped_publication.phase == "B25.4" and
  .deterministic_result_binding.phase == "B25.4"
' "${OUT}/workbench-run-dispatch-response.json" >/dev/null

RUN_ID="$(jq -r '.run_id' "${OUT}/run-result-identity-receipt.json")"
RESERVATION_ID="$(jq -r '.reservation_id' "${OUT}/run-result-identity-receipt.json")"
SUBMITTED_JOB_ID="$(jq -r '.submitted_job_id' "${OUT}/run-result-identity-receipt.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result_job_id' "${OUT}/run-result-identity-receipt.json")"
RECEIPT_ID="$(jq -r '.receipt_id' "${OUT}/run-result-identity-receipt.json")"
PUBLICATION_ID="$(jq -r '.publication_id' "${OUT}/run-scoped-publication.json")"
BINDING_ID="$(jq -r '.binding_id' "${OUT}/deterministic-result-binding.json")"

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg reservation_id "${RESERVATION_ID}" \
  --arg run_id "${RUN_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .phase == "B25.4" and
  .contract_kind == "run-result-identity-receipt" and
  .contract_version == "beagle-run-result-identity-receipt-v1" and
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
  .final_job_id == $submitted_job_id and
  .requested_run_label == $run_label and
  .published_result_job_id == $published_result_job_id and
  .published_result_job_id == $submitted_job_id and
  .published_result_run_label == $run_label and
  .resolved_result_lookup_job_id == $published_result_job_id and
  .result_manifest_job_id == $published_result_job_id and
  (
    .result_lookup_scope == "profile-and-run-label" or
    .result_lookup_scope == "submitted-job-and-run-label"
  ) and
  .catalog_before_matching_run_count == 0 and
  .catalog_after_matching_run_count == 1 and
  .deterministic_identity_confirmed == true
' "${OUT}/run-result-identity-receipt.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg reservation_id "${RESERVATION_ID}" \
  --arg run_id "${RUN_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .phase == "B25.4" and
  .contract_kind == "run-scoped-publication" and
  .contract_version == "beagle-run-scoped-publication-v1" and
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
  .requested_run_label == $run_label and
  .published_result_job_id == $published_result_job_id and
  .published_result_job_id == $submitted_job_id and
  .published_result_run_label == $run_label and
  .published_result_profile_id == "cpu-short-v1" and
  .final_job_state == "COMPLETED" and
  .publication_state == "published" and
  (
    .result_lookup_scope == "profile-and-run-label" or
    .result_lookup_scope == "submitted-job-and-run-label"
  ) and
  .catalog_before_matching_run_count == 0 and
  .catalog_after_matching_run_count == 1 and
  .no_profile_latest_ambiguity == true
' "${OUT}/run-scoped-publication.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg reservation_id "${RESERVATION_ID}" \
  --arg run_id "${RUN_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .phase == "B25.4" and
  .contract_kind == "deterministic-result-binding" and
  .contract_version == "beagle-deterministic-result-binding-v1" and
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
  .requested_run_label == $run_label and
  .published_result_job_id == $published_result_job_id and
  .published_result_job_id == $submitted_job_id and
  .published_result_run_label == $run_label and
  .resolved_result_lookup_job_id == $published_result_job_id and
  .result_manifest_job_id == $published_result_job_id and
  (
    .result_lookup_scope == "profile-and-run-label" or
    .result_lookup_scope == "submitted-job-and-run-label"
  ) and
  .catalog_before_matching_run_count == 0 and
  .catalog_after_matching_run_count == 1 and
  .run_identity_confirmed == true and
  .no_profile_latest_ambiguity == true and
  (.result_refs | length) == 4 and
  ((.result_refs | map(.ref_kind) | sort) == ["artifact-manifest", "published-result", "result-manifest", "submitted-job"])
' "${OUT}/deterministic-result-binding.json" >/dev/null

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
  .last_published_result_run_label == $run_label and
  .last_result_lookup_job_id == $published_result_job_id and
  .last_result_lookup_profile_id == "cpu-short-v1" and
  .last_result_lookup_run_label == $run_label and
  .last_successful_task.task_kind == "operator_real_workflow_pilot" and
  .last_successful_task.task_state == "completed" and
  .last_successful_task.profile_id == "cpu-short-v1" and
  .last_successful_task.workflow_run_label == $run_label and
  .last_successful_task.submitted_job_id == $submitted_job_id and
  .last_successful_task.published_result_job_id == $published_result_job_id and
  .last_successful_task.published_result_run_label == $run_label
' "${OUT}/workbench-execution-state.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
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
  .run.last_result_reference.run_label != null and
  .run.last_result_reference.manifest_key != null
' "${OUT}/workbench-context-after-deterministic-binding.json" >/dev/null

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

jq -e --arg receipt_id "${RECEIPT_ID}" '.receipt_id == $receipt_id and .deterministic_identity_confirmed == true' \
  "${OUT}/run-result-identity-receipt-after-restart.json" >/dev/null
jq -e --arg publication_id "${PUBLICATION_ID}" '.publication_id == $publication_id and .no_profile_latest_ambiguity == true' \
  "${OUT}/run-scoped-publication-after-restart.json" >/dev/null
jq -e --arg binding_id "${BINDING_ID}" '.binding_id == $binding_id and .run_identity_confirmed == true and .no_profile_latest_ambiguity == true' \
  "${OUT}/deterministic-result-binding-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok" and
  .phase == "B25.4" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .requester_role_id == "partner-dev" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1" and
  .requested_run_label == $run_label and
  .published_result_run_label == $run_label and
  .submitted_job_id == $submitted_job_id and
  .published_result_job_id == $published_result_job_id and
  .published_result_job_id == $submitted_job_id and
  .deterministic_identity_confirmed == true and
  .no_profile_latest_ambiguity == true and
  (
    .result_lookup_scope == "profile-and-run-label" or
    .result_lookup_scope == "submitted-job-and-run-label"
  ) and
  .catalog_before_matching_run_count == 0 and
  .catalog_after_matching_run_count == 1 and
  .result_refs_bound == 4 and
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

echo "[OK] deterministic result binding smoke artifacts validated"
