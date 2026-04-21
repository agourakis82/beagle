#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/workstream-recipe-smoke}"
RAW_OUT="${RAW_OUT:-${OUT}/raw-sustained-run}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b143-${STAMP}}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-general-noninfra}"
EXPECTED_GPU_EXECUTION_NODE="${EXPECTED_GPU_EXECUTION_NODE:-r740-proxmox}"
RECIPE_ROOT="${RECIPE_ROOT:-${ROOT}/docs/darwin/hpc/workstreams/recipes}"
WORKSTREAM_SPEC="${WORKSTREAM_SPEC:-${ROOT}/docs/darwin/hpc/workstreams/${WORKSTREAM_ID}.yaml}"
REPO_RECIPE_PATH="${REPO_RECIPE_PATH:-${RECIPE_ROOT}/${WORKSTREAM_ID}.repo_native_dev_loop.yaml}"
CPU_RECIPE_PATH="${CPU_RECIPE_PATH:-${RECIPE_ROOT}/${WORKSTREAM_ID}.operator_cpu_loop.yaml}"
GPU_RECIPE_PATH="${GPU_RECIPE_PATH:-${RECIPE_ROOT}/${WORKSTREAM_ID}.operator_gpu_loop.yaml}"
RECOVERY_RECIPE_PATH="${RECOVERY_RECIPE_PATH:-${RECIPE_ROOT}/${WORKSTREAM_ID}.recovery_resume_loop.yaml}"
LOOP1_REQUEST_ID="${LOOP1_REQUEST_ID:-b143-repo-${STAMP}}"
LOOP2_RUN_LABEL="${LOOP2_RUN_LABEL:-b143-${STAMP}-operator-cpu}"
LOOP3_RUN_LABEL="${LOOP3_RUN_LABEL:-b143-${STAMP}-operator-gpu}"
SKIP_RAW_RUN="${SKIP_RAW_RUN:-0}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require cp
require jq
require python3

mkdir -p "${OUT}" "${RAW_OUT}"

ROOT="${ROOT}" \
WORKSTREAM_SPEC="${WORKSTREAM_SPEC}" \
RECIPE_ROOT="${RECIPE_ROOT}" \
REPO_RECIPE_PATH="${REPO_RECIPE_PATH}" \
CPU_RECIPE_PATH="${CPU_RECIPE_PATH}" \
GPU_RECIPE_PATH="${GPU_RECIPE_PATH}" \
RECOVERY_RECIPE_PATH="${RECOVERY_RECIPE_PATH}" \
python3 - <<'PY' > "${OUT}/recipe-manifest.json"
import json
import os
from pathlib import Path
import yaml

root = Path(os.environ["ROOT"])
workstream_spec_path = Path(os.environ["WORKSTREAM_SPEC"])
recipe_paths = [
    Path(os.environ["REPO_RECIPE_PATH"]),
    Path(os.environ["CPU_RECIPE_PATH"]),
    Path(os.environ["GPU_RECIPE_PATH"]),
    Path(os.environ["RECOVERY_RECIPE_PATH"]),
]

with workstream_spec_path.open() as handle:
    workstream_spec = yaml.safe_load(handle)

recipes = []
for path in recipe_paths:
    with path.open() as handle:
        recipe = yaml.safe_load(handle)
    recipes.append(
        {
            "id": recipe["id"],
            "kind": recipe["kind"],
            "file": str(path.relative_to(root)),
            "step_ids": [step["id"] for step in recipe["steps"]],
            "recovery_points": recipe["recovery_points"],
        }
    )

print(
    json.dumps(
        {
            "phase": "B14.3",
            "workstream_id": workstream_spec["id"],
            "workstream_spec": str(workstream_spec_path.relative_to(root)),
            "recipe_root": str(Path(os.environ["RECIPE_ROOT"]).relative_to(root)),
            "recipes": recipes,
        },
        indent=2,
    )
)
PY

if [[ "${SKIP_RAW_RUN}" != "1" ]]; then
  OUT="${RAW_OUT}" \
  WORKSPACE_ID="${WORKSPACE_ID}" \
  EXPECTED_REPO="${EXPECTED_REPO}" \
  EXPECTED_BRANCH="${EXPECTED_BRANCH}" \
  EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE}" \
  EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE}" \
  EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE}" \
  EXPECTED_GPU_EXECUTION_NODE="${EXPECTED_GPU_EXECUTION_NODE}" \
  LOOP1_REQUEST_ID="${LOOP1_REQUEST_ID}" \
  LOOP2_RUN_LABEL="${LOOP2_RUN_LABEL}" \
  LOOP3_RUN_LABEL="${LOOP3_RUN_LABEL}" \
  bash "${ROOT}/scripts/infrastructure/darwin-hpc/run_sustained_default_dev_plane_validation.sh"
fi

cp "${RAW_OUT}/final-cluster-health.txt" "${OUT}/final-cluster-health.txt"

jq -nc \
  --arg recipe_id "${WORKSTREAM_ID}.repo_native_dev_loop" \
  --arg recipe_file "docs/darwin/hpc/workstreams/recipes/${WORKSTREAM_ID}.repo_native_dev_loop.yaml" \
  --slurpfile loop "${RAW_OUT}/loop1.json" \
  --slurpfile session "${RAW_OUT}/session-after-loop1.json" \
  '{
    status: "ok",
    recipe_id: $recipe_id,
    recipe_file: $recipe_file,
    loop_kind: "repo_native_dev_loop",
    recipe_steps: ["edit", "build", "deploy", "validate", "handoff"],
    workspace_id: $loop[0].workspace_id,
    expected_repo: $loop[0].expected_repo,
    expected_branch: $loop[0].expected_branch,
    changed_file_count: $loop[0].changed_file_count,
    bridge_status: $loop[0].bridge_status,
    active_dev_plane: $loop[0].active_dev_plane,
    fallback_active: $loop[0].fallback_active,
    postdeploy_default_dev_plane: $loop[0].postdeploy_default_dev_plane,
    postdeploy_vm_fallback_role: $loop[0].postdeploy_vm_fallback_role,
    postdeploy_promotion_scope: $loop[0].postdeploy_promotion_scope,
    handoff_ready: (
      $loop[0].bridge_status == "success"
      and $loop[0].active_dev_plane == "beagle-cluster"
      and $loop[0].fallback_active == false
      and ($session[0].session_id // "") != ""
    ),
    handoff_present: (($session[0].last_handoff // "") | length > 0),
    raw_artifact: "raw-sustained-run/loop1.json"
  }' \
  > "${OUT}/repo-native-loop.json"

jq -nc \
  --arg recipe_id "${WORKSTREAM_ID}.operator_cpu_loop" \
  --arg recipe_file "docs/darwin/hpc/workstreams/recipes/${WORKSTREAM_ID}.operator_cpu_loop.yaml" \
  --slurpfile loop "${RAW_OUT}/loop2.json" \
  --slurpfile pilot "${RAW_OUT}/loop2-pilot.json" \
  '{
    status: "ok",
    recipe_id: $recipe_id,
    recipe_file: $recipe_file,
    loop_kind: "operator_cpu_loop",
    recipe_steps: ["bootstrap", "control_surface_lookup", "submit_cpu_batch", "result_resolution", "persist_state"],
    workspace_id: $loop[0].workspace_id,
    session_id: $loop[0].session_id,
    expected_repo: $loop[0].expected_repo,
    expected_branch: $loop[0].expected_branch,
    submitted_profile_id: $pilot[0].submitted_job.profile_id,
    final_job_state: $pilot[0].final_job.state,
    published_result_job_id: $loop[0].published_result_job_id,
    active_dev_plane: $loop[0].active_dev_plane,
    fallback_active: $loop[0].fallback_active,
    raw_artifact: "raw-sustained-run/loop2.json"
  }' \
  > "${OUT}/operator-cpu-loop.json"

jq -nc \
  --arg recipe_id "${WORKSTREAM_ID}.operator_gpu_loop" \
  --arg recipe_file "docs/darwin/hpc/workstreams/recipes/${WORKSTREAM_ID}.operator_gpu_loop.yaml" \
  --slurpfile loop "${RAW_OUT}/loop3.json" \
  --slurpfile pilot "${RAW_OUT}/loop3-pilot.json" \
  '{
    status: "ok",
    recipe_id: $recipe_id,
    recipe_file: $recipe_file,
    loop_kind: "operator_gpu_loop",
    recipe_steps: ["bootstrap", "control_surface_lookup", "submit_gpu_single", "publication_retrieval", "persist_state"],
    workspace_id: $loop[0].workspace_id,
    session_id: $loop[0].session_before_restart,
    expected_repo: $loop[0].expected_repo,
    expected_branch: $loop[0].expected_branch,
    submitted_profile_id: $pilot[0].submitted_job.profile_id,
    final_job_state: $pilot[0].final_job.state,
    expected_execution_node: $loop[0].expected_execution_node,
    final_job_node_list: $pilot[0].final_job.node_list,
    published_result_job_id: $loop[0].published_result_job_id,
    active_dev_plane: $loop[0].postrestart_default_dev_plane,
    fallback_active: $loop[0].fallback_active_after_restart,
    raw_artifact: "raw-sustained-run/loop3.json"
  }' \
  > "${OUT}/operator-gpu-loop.json"

jq -nc \
  --arg recipe_id "${WORKSTREAM_ID}.recovery_resume_loop" \
  --arg recipe_file "docs/darwin/hpc/workstreams/recipes/${WORKSTREAM_ID}.recovery_resume_loop.yaml" \
  --slurpfile bootstrap "${RAW_OUT}/bootstrap-after-restart.json" \
  --slurpfile session "${RAW_OUT}/session-after-restart.json" \
  --slurpfile loop "${RAW_OUT}/loop3.json" \
  --slurpfile smoke "${RAW_OUT}/smoke.json" \
  '{
    status: "ok",
    recipe_id: $recipe_id,
    recipe_file: $recipe_file,
    loop_kind: "recovery_resume_loop",
    recipe_steps: ["session_restart", "repo_branch_recovery", "last_task_result_recovery", "resume_semantics"],
    workspace_id: $smoke[0].workspace_id,
    predeploy_session_id: $smoke[0].predeploy_session_id,
    postdeploy_session_id: $smoke[0].postdeploy_session_id,
    after_restart_session_id: $smoke[0].after_restart_session_id,
    same_session_line: (
      $smoke[0].predeploy_session_id == $smoke[0].postdeploy_session_id
      and $smoke[0].postdeploy_session_id == $smoke[0].after_restart_session_id
      and $loop[0].session_before_restart == $loop[0].session_after_restart
    ),
    workstream_name: $bootstrap[0].workstream_cutover_policy.workstream_name,
    promotion_scope: $bootstrap[0].workstream_cutover_policy.promotion_scope,
    active_dev_plane_after_restart: $loop[0].postrestart_default_dev_plane,
    fallback_active_after_restart: $loop[0].fallback_active_after_restart,
    fallback_observed: $loop[0].fallback_observed,
    last_task_kind: $loop[0].task_kind,
    last_published_result_job_id: $session[0].last_published_result_job_id,
    handoff_present: (($loop[0].last_handoff // "") | length > 0),
    raw_artifact: "raw-sustained-run/smoke.json"
  }' \
  > "${OUT}/recovery-resume-loop.json"

jq -nc \
  --arg phase "B14.3" \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg raw_out "raw-sustained-run" \
  --slurpfile manifest "${OUT}/recipe-manifest.json" \
  --slurpfile raw_smoke "${RAW_OUT}/smoke.json" \
  --slurpfile raw_loop3 "${RAW_OUT}/loop3.json" \
  --slurpfile repo_loop "${OUT}/repo-native-loop.json" \
  --slurpfile cpu_loop "${OUT}/operator-cpu-loop.json" \
  --slurpfile gpu_loop "${OUT}/operator-gpu-loop.json" \
  --slurpfile recovery_loop "${OUT}/recovery-resume-loop.json" \
  '{
    status: "ok",
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $raw_smoke[0].workspace_id,
    raw_output_dir: $raw_out,
    recipe_count: ($manifest[0].recipes | length),
    recipe_ids: ($manifest[0].recipes | map(.id)),
    repo_native_dev_loop: $repo_loop[0].status,
    operator_cpu_loop: $cpu_loop[0].status,
    operator_gpu_loop: $gpu_loop[0].status,
    recovery_resume_loop: $recovery_loop[0].status,
    raw_sustained_workspace_id: $raw_smoke[0].workspace_id,
    raw_sustained_session_id: $raw_smoke[0].after_restart_session_id,
    default_dev_plane: $raw_loop3[0].postrestart_default_dev_plane,
    fallback_observed: $raw_loop3[0].fallback_observed
  }' \
  > "${OUT}/smoke.json"

echo "[OK] workstream recipe smoke completed"
