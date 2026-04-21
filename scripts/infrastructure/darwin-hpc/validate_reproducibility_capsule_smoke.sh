#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/reproducibility-capsule}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B254_BASE_OUT="${B254_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/deterministic-result-binding}"

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
  prior-workbench-run-request.json \
  prior-workbench-run-dispatch-response.json \
  current-workbench-run-request.json \
  current-workbench-run-dispatch-response.json \
  run-capsule.json \
  prior-run-capsule.json \
  run-diff.json \
  replay-request.json \
  workbench-context-after-run.json \
  bootstrap-after-restart.json \
  run-capsule-after-restart.json \
  replay-request-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  session-id.txt \
  prior-run-label.txt \
  current-run-label.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B254_BASE_OUT}/smoke.json"

jq -e '
  .run_capsule_source_present == 1 and
  .run_diff_source_present == 1 and
  .workbench_run_source_present == 1 and
  .workbench_result_binding_source_present == 1 and
  .workspace_plane_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .run_capsule_schema_present == 1 and
  .run_diff_schema_present == 1 and
  .replay_request_schema_present == 1 and
  .b254_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.4" and
  .same_beagle_owned_identity == true and
  .deterministic_identity_confirmed == true and
  .no_profile_latest_ambiguity == true
' "${B254_BASE_OUT}/smoke.json" >/dev/null

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/session-id.txt")"
PRIOR_RUN_LABEL="$(cat "${OUT}/prior-run-label.txt")"
CURRENT_RUN_LABEL="$(cat "${OUT}/current-run-label.txt")"

[[ -n "${WORKSPACE_ID}" ]] || { echo "[FAIL] workspace-id.txt is empty" >&2; exit 1; }
[[ -n "${SESSION_ID}" ]] || { echo "[FAIL] session-id.txt is empty" >&2; exit 1; }
[[ -n "${PRIOR_RUN_LABEL}" ]] || { echo "[FAIL] prior-run-label.txt is empty" >&2; exit 1; }
[[ -n "${CURRENT_RUN_LABEL}" ]] || { echo "[FAIL] current-run-label.txt is empty" >&2; exit 1; }

jq -e '.status == "ok"' "${OUT}/health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/health-after.json" >/dev/null

jq -e '
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1"
' "${OUT}/prior-workbench-run-request.json" >/dev/null

jq -e '
  .requested_by == "beagle-operator" and
  .requester_role_id == "beagle-operator" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-batch-v1"
' "${OUT}/current-workbench-run-request.json" >/dev/null

jq -e '.status == "ok" and .phase == "B25.3"' "${OUT}/prior-workbench-run-dispatch-response.json" >/dev/null
jq -e '.status == "ok" and .phase == "B25.3"' "${OUT}/current-workbench-run-dispatch-response.json" >/dev/null

CURRENT_RUN_ID="$(jq -r '.run_id' "${OUT}/run-capsule.json")"
PRIOR_RUN_ID="$(jq -r '.run_id' "${OUT}/prior-run-capsule.json")"
CURRENT_JOB_ID="$(jq -r '.submitted_job_id' "${OUT}/run-capsule.json")"
PRIOR_JOB_ID="$(jq -r '.submitted_job_id' "${OUT}/prior-run-capsule.json")"

[[ -n "${CURRENT_RUN_ID}" && "${CURRENT_RUN_ID}" != "null" ]] || { echo "[FAIL] run-capsule.json missing run_id" >&2; exit 1; }
[[ -n "${PRIOR_RUN_ID}" && "${PRIOR_RUN_ID}" != "null" ]] || { echo "[FAIL] prior-run-capsule.json missing run_id" >&2; exit 1; }
[[ "${CURRENT_RUN_ID}" != "${PRIOR_RUN_ID}" ]] || { echo "[FAIL] current and prior run ids are identical" >&2; exit 1; }

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg current_run_label "${CURRENT_RUN_LABEL}" '
  .phase == "B25.5" and
  .contract_kind == "run-capsule" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .run_label == $current_run_label and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-batch-v1" and
  (.published_result_job_id | tonumber) > 0 and
  (.result_refs | length) >= 3 and
  (.config_fingerprint | length) > 0 and
  .deterministic_identity_confirmed == true
' "${OUT}/run-capsule.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg prior_run_label "${PRIOR_RUN_LABEL}" '
  .phase == "B25.5" and
  .contract_kind == "run-capsule" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .run_label == $prior_run_label and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1" and
  (.published_result_job_id | tonumber) > 0 and
  (.result_refs | length) >= 3 and
  (.config_fingerprint | length) > 0 and
  .deterministic_identity_confirmed == true
' "${OUT}/prior-run-capsule.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg current_run_id "${CURRENT_RUN_ID}" \
  --arg prior_run_id "${PRIOR_RUN_ID}" \
  --argjson current_job_id "${CURRENT_JOB_ID}" \
  --argjson prior_job_id "${PRIOR_JOB_ID}" '
  .phase == "B25.5" and
  .contract_kind == "run-diff" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .current_run_id == $current_run_id and
  .prior_run_id == $prior_run_id and
  .current_submitted_job_id == $current_job_id and
  .prior_submitted_job_id == $prior_job_id and
  .lineage_relation == "direct-parent" and
  (.code.prior_summary | length) > 0 and
  (.code.current_summary | length) > 0 and
  .config.changed == true and
  .environment.changed == true and
  .result.changed == true and
  (.changed_categories | index("config")) != null and
  (.changed_categories | index("environment")) != null and
  (.changed_categories | index("result")) != null
' "${OUT}/run-diff.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg current_run_id "${CURRENT_RUN_ID}" \
  --argjson current_job_id "${CURRENT_JOB_ID}" '
  .phase == "B25.5" and
  .contract_kind == "replay-request" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .source_run_id == $current_run_id and
  .source_submitted_job_id == $current_job_id and
  .replay_mode == "bounded-workbench-replay" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-batch-v1" and
  (.config_fingerprint | length) > 0 and
  (.result_manifest_key | length) > 0
' "${OUT}/replay-request.json" >/dev/null

jq -e \
  --arg current_run_id "${CURRENT_RUN_ID}" \
  --argjson current_job_id "${CURRENT_JOB_ID}" '
  .phase == "B25.5" and
  .status == "ok" and
  .same_beagle_owned_identity == true and
  .current_run_id == $current_run_id and
  .current_parent_run_id != null and
  .current_submitted_job_id == $current_job_id and
  .code_diff_explicit == true and
  .config_changed == true and
  .environment_changed == true and
  .result_changed == true and
  .partner_access_state == "operator-mediated-ready" and
  (.bootstrap_recovered_before == false or .bootstrap_recovered_before == true) and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

jq -e --arg current_run_id "${CURRENT_RUN_ID}" '.run_id == $current_run_id' "${OUT}/run-capsule-after-restart.json" >/dev/null
jq -e --arg current_run_id "${CURRENT_RUN_ID}" '.source_run_id == $current_run_id' "${OUT}/replay-request-after-restart.json" >/dev/null

grep -q 'beagle-core' "${OUT}/final-cluster-health.txt"
grep -q 'beagle-workspace' "${OUT}/final-cluster-health.txt"
grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"

echo "[OK] B25.5 reproducibility capsule artifacts validated"
