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
  session-before.json \
  workstream-cutover-policy-summary.json \
  bootstrap-after-deploy.json \
  session-after-deploy.json \
  pilot.json \
  result-after.json \
  result-manifest-after.json \
  session-before-restart.json \
  fallback-summary.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-workstream.txt \
  expected-cutover-state.txt \
  expected-branch-lineage.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  expected-execution-node.txt \
  run-label.txt \
  published-result-job-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_CUTOVER_STATE="$(cat "${OUT}/expected-cutover-state.txt")"
EXPECTED_BRANCH_LINEAGE="$(cat "${OUT}/expected-branch-lineage.txt")"
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_PROMOTION_SCOPE="$(cat "${OUT}/expected-promotion-scope.txt")"
EXPECTED_EXECUTION_NODE="$(cat "${OUT}/expected-execution-node.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/published-result-job-id.txt")"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and (
    .workstream_cutover_policy == null
    or (
      .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
      and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
    )
  )
' "${OUT}/bootstrap-before.json" >/dev/null

SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-before.json")"
[[ -n "${SESSION_ID}" ]] || {
  echo "[FAIL] bootstrap-before.json missing session_id" >&2
  exit 1
}

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
' "${OUT}/session-before.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .expected_workstream == $expected_workstream
  and .expected_cutover_state == $expected_cutover_state
  and .expected_branch_lineage == $expected_branch_lineage
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and (.workstream_source_present == true or .workstream_source_present == 1)
  and (.config_model_present == true or .config_model_present == 1)
  and (.config_lib_present == true or .config_lib_present == 1)
  and (.configmap_present == true or .configmap_present == 1)
' "${OUT}/workstream-cutover-policy-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.cutover_state == $expected_cutover_state
  and .workstream_cutover_policy.branch_lineage == $expected_branch_lineage
  and .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
  and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
  and .workstream_cutover_policy.recovery_required == true
  and .workstream_cutover_policy.handoff_required == true
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
' "${OUT}/bootstrap-after-deploy.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .session_id == $session_id
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.cutover_state == $expected_cutover_state
  and .workstream_cutover_policy.branch_lineage == $expected_branch_lineage
  and .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
  and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
  and .workstream_cutover_policy.recovery_required == true
  and .workstream_cutover_policy.handoff_required == true
' "${OUT}/session-after-deploy.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --arg run_label "${RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .submitted_job.profile_id == "gpu-single-v1"
  and .final_job.state == "COMPLETED"
  and .final_job.node_list == $expected_node
  and .artifact_manifest.job_id == .submitted_job.job_id
  and .published_result.profile_id == "gpu-single-v1"
  and .published_result.node_list == $expected_node
  and .resolved_result_lookup.job_id == .published_result.job_id
  and .resolved_result_lookup.node_list == $expected_node
  and .published_result_manifest.job_id == .published_result.job_id
  and .last_successful_task.task_kind == "advanced_operator_gpu_workflow"
  and .last_successful_task.task_state == "completed"
  and .last_successful_task.profile_id == "gpu-single-v1"
  and .last_successful_task.workflow_run_label == $run_label
  and .last_successful_task.execution_node == $expected_node
  and .last_successful_task.resolved_result_node == $expected_node
  and .last_successful_task.repo == $expected_repo
  and .last_successful_task.branch == $expected_branch
  and (.handoff | contains($expected_repo))
  and (.handoff | contains($expected_branch))
' "${OUT}/pilot.json" >/dev/null

jq -e \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" '
  .job_id == $published_job_id
  and .profile_id == "gpu-single-v1"
  and .node_list == $expected_node
' "${OUT}/result-after.json" >/dev/null

jq -e \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id
' "${OUT}/result-manifest-after.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.cutover_state == $expected_cutover_state
  and .workstream_cutover_policy.branch_lineage == $expected_branch_lineage
  and .last_workflow_kind == "advanced_operator_gpu_workflow"
  and .last_job_profile_id == "gpu-single-v1"
  and .last_job_run_label == $run_label
  and .last_job_node_list == $expected_node
  and .last_published_result_job_id == $published_job_id
  and .last_published_result_profile_id == "gpu-single-v1"
  and .last_published_result_node_list == $expected_node
  and .last_result_lookup_job_id == $published_job_id
  and .last_result_lookup_profile_id == "gpu-single-v1"
  and .last_result_lookup_node_list == $expected_node
  and .last_successful_task.task_kind == "advanced_operator_gpu_workflow"
  and .last_successful_task.execution_node == $expected_node
  and (.last_handoff | length > 0)
' "${OUT}/session-before-restart.json" >/dev/null

jq -e '.observed == false or .observed == true' "${OUT}/fallback-summary.json" >/dev/null

if jq -e '.observed == true' "${OUT}/fallback-summary.json" >/dev/null; then
  for file in \
    fallback-enter.json \
    session-during-fallback.json \
    fallback-return.json \
    session-after-return.json \
    fallback-ledger-tail.jsonl; do
    [[ -s "${OUT}/${file}" ]] || {
      echo "[FAIL] missing optional fallback artifact: ${OUT}/${file}" >&2
      exit 1
    }
  done

  FALLBACK_REASON="$(jq -r '.fallback_reason // empty' "${OUT}/fallback-summary.json")"
  RETURN_REASON="$(jq -r '.return_reason // empty' "${OUT}/fallback-summary.json")"

  jq -e \
    --arg fallback_reason "${FALLBACK_REASON}" '
    .status == "ok"
    and .active_dev_plane == "vm-fallback"
    and .fallback_active == true
    and .last_fallback_event.event_kind == "fallback_entered"
    and .last_fallback_event.reason == $fallback_reason
  ' "${OUT}/fallback-enter.json" >/dev/null

  jq -e \
    --arg return_reason "${RETURN_REASON}" \
    --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" '
    .status == "ok"
    and .active_dev_plane == $expected_default_dev_plane
    and .fallback_active == false
    and .last_fallback_event.event_kind == "returned_to_canonical"
    and .last_fallback_event.reason == $return_reason
    and (.last_fallback_event.duration_seconds // -1) >= 0
  ' "${OUT}/fallback-return.json" >/dev/null

  grep -Fq '"event_kind":"fallback_entered"' "${OUT}/fallback-ledger-tail.jsonl"
  grep -Fq '"event_kind":"returned_to_canonical"' "${OUT}/fallback-ledger-tail.jsonl"
fi

jq -e '.status == "ok"' "${OUT}/beagle-health-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .recovered_session == true
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.cutover_state == $expected_cutover_state
  and .workstream_cutover_policy.branch_lineage == $expected_branch_lineage
  and .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
  and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
  and .workstream_cutover_policy.recovery_required == true
  and .workstream_cutover_policy.handoff_required == true
  and .last_workflow_kind == "advanced_operator_gpu_workflow"
  and .last_job_node_list == $expected_node
  and .last_published_result_job_id == $published_job_id
  and .last_result_lookup_job_id == $published_job_id
  and .last_successful_task.task_kind == "advanced_operator_gpu_workflow"
  and .last_successful_task.execution_node == $expected_node
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .workstream_cutover_policy.workstream_name == $expected_workstream
  and .workstream_cutover_policy.cutover_state == $expected_cutover_state
  and .workstream_cutover_policy.branch_lineage == $expected_branch_lineage
  and .workstream_cutover_policy.default_dev_plane == $expected_default_dev_plane
  and .workstream_cutover_policy.vm_fallback_role == $expected_vm_fallback_role
  and .workstream_cutover_policy.recovery_required == true
  and .workstream_cutover_policy.handoff_required == true
  and .last_workflow_kind == "advanced_operator_gpu_workflow"
  and .last_job_profile_id == "gpu-single-v1"
  and .last_job_run_label == $run_label
  and .last_job_node_list == $expected_node
  and .last_published_result_job_id == $published_job_id
  and .last_published_result_profile_id == "gpu-single-v1"
  and .last_published_result_node_list == $expected_node
  and .last_result_lookup_job_id == $published_job_id
  and .last_result_lookup_profile_id == "gpu-single-v1"
  and .last_result_lookup_node_list == $expected_node
  and .last_successful_task.task_kind == "advanced_operator_gpu_workflow"
  and .last_successful_task.profile_id == "gpu-single-v1"
  and .last_successful_task.workflow_run_label == $run_label
  and .last_successful_task.execution_node == $expected_node
  and .last_successful_task.resolved_result_node == $expected_node
  and (.last_handoff | length > 0)
' "${OUT}/session-after-restart.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_cutover_state "${EXPECTED_CUTOVER_STATE}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_execution_node "${EXPECTED_EXECUTION_NODE}" '
  .expected_workstream == $expected_workstream
  and .expected_cutover_state == $expected_cutover_state
  and .expected_branch_lineage == $expected_branch_lineage
  and .workstream_name == $expected_workstream
  and .cutover_state == $expected_cutover_state
  and .branch_lineage == $expected_branch_lineage
  and .recovery_required == true
  and .handoff_required == true
  and .default_dev_plane == $expected_default_dev_plane
  and .vm_fallback_role == $expected_vm_fallback_role
  and .profile_id == "gpu-single-v1"
  and .final_job_state == "COMPLETED"
  and .final_job_node_list == $expected_execution_node
  and .task_kind == "advanced_operator_gpu_workflow"
  and .active_dev_plane_after_restart == $expected_default_dev_plane
  and .fallback_active_after_restart == false
  and .predeploy_session_id != ""
  and .postdeploy_session_id == .predeploy_session_id
  and .after_restart_session_id == .predeploy_session_id
' "${OUT}/smoke.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] first real workstream cutover validation passed"
