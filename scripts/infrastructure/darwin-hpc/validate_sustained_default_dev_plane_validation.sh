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
  git-status-before.txt \
  git-diff-stat-before.txt \
  bootstrap-after-deploy.json \
  session-after-deploy.json \
  loop1-bridge-execute.json \
  loop1-bridge-ledger-tail.jsonl \
  session-after-loop1.json \
  loop1.json \
  control-before-loop2.json \
  results-before-loop2.json \
  loop2-pilot.json \
  loop2-result-after.json \
  loop2-result-manifest-after.json \
  session-after-loop2.json \
  loop2.json \
  control-before-loop3.json \
  results-before-loop3.json \
  loop3-pilot.json \
  loop3-result-after.json \
  loop3-result-manifest-after.json \
  session-before-restart.json \
  fallback-summary.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  loop3.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  expected-gpu-execution-node.txt \
  loop1-request-id.txt \
  loop2-run-label.txt \
  loop3-run-label.txt \
  loop2-published-result-job-id.txt \
  loop3-published-result-job-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_PROMOTION_SCOPE="$(cat "${OUT}/expected-promotion-scope.txt")"
EXPECTED_GPU_EXECUTION_NODE="$(cat "${OUT}/expected-gpu-execution-node.txt")"
LOOP1_REQUEST_ID="$(cat "${OUT}/loop1-request-id.txt")"
LOOP2_RUN_LABEL="$(cat "${OUT}/loop2-run-label.txt")"
LOOP3_RUN_LABEL="$(cat "${OUT}/loop3-run-label.txt")"
LOOP2_PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/loop2-published-result-job-id.txt")"
LOOP3_PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/loop3-published-result-job-id.txt")"

[[ -n "${WORKSPACE_ID}" ]] || {
  echo "[FAIL] workspace-id.txt is empty" >&2
  exit 1
}

CHANGED_FILE_COUNT="$(awk 'END{print NR+0}' "${OUT}/git-status-before.txt")"
if (( CHANGED_FILE_COUNT < 1 )); then
  echo "[FAIL] loop1 did not capture a real repo-native delta" >&2
  exit 1
fi

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
' "${OUT}/bootstrap-before.json" >/dev/null

SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-before.json")"
[[ -n "${SESSION_ID}" ]] || {
  echo "[FAIL] bootstrap-before.json missing session_id" >&2
  exit 1
}

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
' "${OUT}/session-before.json" >/dev/null

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
' "${OUT}/session-after-deploy.json" >/dev/null

jq -e '.status == "success"' "${OUT}/loop1-bridge-execute.json" >/dev/null
grep -Fq "\"request_id\":\"${LOOP1_REQUEST_ID}\"" "${OUT}/loop1-bridge-ledger-tail.jsonl"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" '
  .status == "ok"
  and .loop_kind == "repo_native_dev_loop"
  and .workspace_id == $workspace_id
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .changed_file_count >= 1
  and .bridge_status == "success"
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .postdeploy_default_dev_plane == $expected_default_dev_plane
  and .postdeploy_vm_fallback_role == $expected_vm_fallback_role
  and .postdeploy_promotion_scope == $expected_promotion_scope
' "${OUT}/loop1.json" >/dev/null

jq -e '.status == "ok"' "${OUT}/control-before-loop2.json" >/dev/null
jq -e '.profiles | map(.id) | index("cpu-batch-v1") != null' "${OUT}/control-before-loop2.json" >/dev/null
jq -e '.bridge_health.status == "ok"' "${OUT}/control-before-loop2.json" >/dev/null
jq -e '.total >= 1' "${OUT}/results-before-loop2.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg run_label "${LOOP2_RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .catalog_before.profile_id == "cpu-batch-v1"
  and .catalog_before.total >= 1
  and .submitted_job.profile_id == "cpu-batch-v1"
  and .final_job.state == "COMPLETED"
  and .artifact_manifest.job_id == .submitted_job.job_id
  and .published_result.profile_id == "cpu-batch-v1"
  and .resolved_result_lookup.job_id == .published_result.job_id
  and .published_result_manifest.job_id == .published_result.job_id
  and .last_successful_task.task_kind == "single_rich_operator_workflow"
  and .last_successful_task.task_state == "completed"
  and .last_successful_task.profile_id == "cpu-batch-v1"
  and .last_successful_task.workflow_run_label == $run_label
  and .last_successful_task.repo == $expected_repo
  and .last_successful_task.branch == $expected_branch
' "${OUT}/loop2-pilot.json" >/dev/null

jq -e \
  --argjson published_job_id "${LOOP2_PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id and .profile_id == "cpu-batch-v1"
' "${OUT}/loop2-result-after.json" >/dev/null

jq -e \
  --argjson published_job_id "${LOOP2_PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id
' "${OUT}/loop2-result-manifest-after.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg run_label "${LOOP2_RUN_LABEL}" \
  --argjson published_job_id "${LOOP2_PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
  and .last_workflow_kind == "single_rich_operator_workflow"
  and .last_job_profile_id == "cpu-batch-v1"
  and .last_job_run_label == $run_label
  and .last_published_result_job_id == $published_job_id
  and .last_published_result_profile_id == "cpu-batch-v1"
  and .last_result_lookup_job_id == $published_job_id
  and .last_result_lookup_profile_id == "cpu-batch-v1"
  and .last_successful_task.task_kind == "single_rich_operator_workflow"
  and .last_successful_task.profile_id == "cpu-batch-v1"
' "${OUT}/session-after-loop2.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .loop_kind == "single_rich_operator_workflow"
  and .workspace_id == $workspace_id
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .profile_id == "cpu-batch-v1"
  and .final_job_state == "COMPLETED"
  and .task_kind == "single_rich_operator_workflow"
' "${OUT}/loop2.json" >/dev/null

jq -e '.status == "ok"' "${OUT}/control-before-loop3.json" >/dev/null
jq -e '.profiles | map(.id) | index("gpu-single-v1") != null' "${OUT}/control-before-loop3.json" >/dev/null
jq -e '.bridge_health.status == "ok"' "${OUT}/control-before-loop3.json" >/dev/null
jq -e '.total >= 1' "${OUT}/results-before-loop3.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" \
  --arg run_label "${LOOP3_RUN_LABEL}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .catalog_before.profile_id == "gpu-single-v1"
  and .catalog_before.total >= 1
  and .catalog_before.latest_result.profile_id == "gpu-single-v1"
  and .catalog_before.latest_result.node_list == $expected_node
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
' "${OUT}/loop3-pilot.json" >/dev/null

jq -e \
  --argjson published_job_id "${LOOP3_PUBLISHED_RESULT_JOB_ID}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" '
  .job_id == $published_job_id
  and .profile_id == "gpu-single-v1"
  and .node_list == $expected_node
' "${OUT}/loop3-result-after.json" >/dev/null

jq -e \
  --argjson published_job_id "${LOOP3_PUBLISHED_RESULT_JOB_ID}" '
  .job_id == $published_job_id
' "${OUT}/loop3-result-manifest-after.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" \
  --arg run_label "${LOOP3_RUN_LABEL}" \
  --argjson published_job_id "${LOOP3_PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
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
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" \
  --argjson published_job_id "${LOOP3_PUBLISHED_RESULT_JOB_ID}" '
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
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" \
  --arg run_label "${LOOP3_RUN_LABEL}" \
  --argjson published_job_id "${LOOP3_PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .active_dev_plane == $expected_default_dev_plane
  and .fallback_active == false
  and .dev_plane_policy.default_dev_plane == $expected_default_dev_plane
  and .dev_plane_policy.vm_fallback_role == $expected_vm_fallback_role
  and .dev_plane_policy.promotion_scope == $expected_promotion_scope
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
' "${OUT}/session-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" '
  .status == "ok"
  and .loop_kind == "advanced_operator_gpu_workflow"
  and .workspace_id == $workspace_id
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .profile_id == "gpu-single-v1"
  and .final_job_state == "COMPLETED"
  and .final_job_node_list == $expected_node
  and .resolved_result_node == $expected_node
  and .task_kind == "advanced_operator_gpu_workflow"
  and .restart_preserved_session == true
  and .active_dev_plane_after_restart == $expected_default_dev_plane
  and .fallback_active_after_restart == false
  and .postrestart_default_dev_plane == $expected_default_dev_plane
  and .postrestart_vm_fallback_role == $expected_vm_fallback_role
  and .postrestart_promotion_scope == $expected_promotion_scope
' "${OUT}/loop3.json" >/dev/null

jq -e \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_node "${EXPECTED_GPU_EXECUTION_NODE}" '
  .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .loop1_status == "ok"
  and .loop2_status == "ok"
  and .loop3_status == "ok"
  and .loop2_profile_id == "cpu-batch-v1"
  and .loop3_profile_id == "gpu-single-v1"
  and .loop3_expected_execution_node == $expected_node
  and .predeploy_session_id != ""
  and .postdeploy_session_id == .predeploy_session_id
  and .after_restart_session_id == .predeploy_session_id
' "${OUT}/smoke.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"
grep -Fq "Slurmctld(primary)" "${OUT}/final-cluster-health.txt"

echo "[OK] sustained default dev plane validation passed"
