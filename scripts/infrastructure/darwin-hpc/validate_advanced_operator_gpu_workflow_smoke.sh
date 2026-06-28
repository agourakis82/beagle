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
  beagle-health-before.json \
  beagle-health-after.json \
  bootstrap-before.json \
  control-before.json \
  results-before.json \
  pilot.json \
  result-after.json \
  result-manifest-after.json \
  session-before-restart.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-execution-node.txt \
  run-label.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_EXECUTION_NODE="$(cat "${OUT}/expected-execution-node.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"

[[ -n "${WORKSPACE_ID}" ]] || {
  echo "[FAIL] workspace-id.txt is empty" >&2
  exit 1
}
[[ -n "${EXPECTED_REPO}" ]] || {
  echo "[FAIL] expected-repo.txt is empty" >&2
  exit 1
}
[[ -n "${EXPECTED_BRANCH}" ]] || {
  echo "[FAIL] expected-branch.txt is empty" >&2
  exit 1
}
[[ -n "${EXPECTED_EXECUTION_NODE}" ]] || {
  echo "[FAIL] expected-execution-node.txt is empty" >&2
  exit 1
}
[[ -n "${RUN_LABEL}" ]] || {
  echo "[FAIL] run-label.txt is empty" >&2
  exit 1
}

jq -e '.status == "ok"' "${OUT}/beagle-health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/beagle-health-after.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/control-before.json" >/dev/null
jq -e '.profiles | map(.id) | index("gpu-single-v1") != null' "${OUT}/control-before.json" >/dev/null
jq -e '.bridge_health.status == "ok"' "${OUT}/control-before.json" >/dev/null
jq -e '.total >= 1' "${OUT}/results-before.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .recovered_session == false
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and (.current_task == null)
' "${OUT}/bootstrap-before.json" >/dev/null

SESSION_ID="$(jq -r '.session_id' "${OUT}/bootstrap-before.json")"
[[ -n "${SESSION_ID}" && "${SESSION_ID}" != "null" ]] || {
  echo "[FAIL] bootstrap-before.json missing session_id" >&2
  exit 1
}

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
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
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
  and (.handoff | contains($expected_repo))
  and (.handoff | contains($expected_branch))
' "${OUT}/pilot.json" >/dev/null

SUBMITTED_JOB_ID="$(jq -r '.submitted_job.job_id' "${OUT}/pilot.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/pilot.json")"

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
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and (.current_task == null)
  and .last_workflow_kind == "advanced_operator_gpu_workflow"
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_id == $submitted_job_id
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
  and .last_successful_task.submitted_job_id == $submitted_job_id
  and .last_successful_task.published_result_job_id == $published_job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-before-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and .recovered_session == true
  and (.current_task == null)
  and .last_workflow_kind == "advanced_operator_gpu_workflow"
  and .last_job_node_list == $expected_node
  and .last_published_result_job_id == $published_job_id
  and .last_result_lookup_job_id == $published_job_id
  and .last_result_lookup_node_list == $expected_node
  and .last_successful_task.task_kind == "advanced_operator_gpu_workflow"
  and .last_successful_task.execution_node == $expected_node
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_node "${EXPECTED_EXECUTION_NODE}" \
  --arg run_label "${RUN_LABEL}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
  and .canonical_repo == $expected_repo
  and .canonical_branch == $expected_branch
  and .repo_context.canonical_repo == $expected_repo
  and .repo_context.canonical_branch == $expected_branch
  and (.current_task == null)
  and .last_workflow_kind == "advanced_operator_gpu_workflow"
  and .last_workflow_repo == $expected_repo
  and .last_workflow_branch == $expected_branch
  and .last_job_id == $submitted_job_id
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
  and .last_successful_task.submitted_job_id == $submitted_job_id
  and .last_successful_task.published_result_job_id == $published_job_id
  and (.last_handoff | length > 0)
' "${OUT}/session-after-restart.json" >/dev/null

echo "[OK] advanced operator GPU workflow smoke validation passed"
