#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:?OUT is required}"
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
RAW_OUT="${RAW_OUT:-${OUT}/raw-sustained-run}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq
require python3

for file in \
  recipe-manifest.json \
  repo-native-loop.json \
  operator-cpu-loop.json \
  operator-gpu-loop.json \
  recovery-resume-loop.json \
  smoke.json \
  final-cluster-health.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

OUT="${RAW_OUT}" bash "${ROOT}/scripts/infrastructure/darwin-hpc/validate_sustained_default_dev_plane_validation.sh"

OUT="${OUT}" ROOT="${ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

out = Path(os.environ["OUT"])
root = Path(os.environ["ROOT"])
manifest = json.loads((out / "recipe-manifest.json").read_text())

assert manifest["phase"] == "B14.3"
assert manifest["workstream_id"] == "beagle-darwin-hpc-governance"
assert manifest["workstream_spec"] == "docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml"
assert manifest["recipe_root"] == "docs/darwin/hpc/workstreams/recipes"
assert len(manifest["recipes"]) == 4

expected = {
    "beagle-darwin-hpc-governance.repo_native_dev_loop": [
        "edit",
        "build",
        "deploy",
        "validate",
        "handoff",
    ],
    "beagle-darwin-hpc-governance.operator_cpu_loop": [
        "bootstrap",
        "control_surface_lookup",
        "submit_cpu_batch",
        "result_resolution",
        "persist_state",
    ],
    "beagle-darwin-hpc-governance.operator_gpu_loop": [
        "bootstrap",
        "control_surface_lookup",
        "submit_gpu_single",
        "publication_retrieval",
        "persist_state",
    ],
    "beagle-darwin-hpc-governance.recovery_resume_loop": [
        "session_restart",
        "repo_branch_recovery",
        "last_task_result_recovery",
        "resume_semantics",
    ],
}

spec = yaml.safe_load((root / "docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml").read_text())
recipe_links = spec["recipes"]

for recipe in manifest["recipes"]:
    recipe_id = recipe["id"]
    assert recipe_id in expected
    assert recipe["step_ids"] == expected[recipe_id]
    recipe_file = root / recipe["file"]
    loaded = yaml.safe_load(recipe_file.read_text())
    assert loaded["id"] == recipe_id
    assert loaded["workstream"] == "beagle-darwin-hpc-governance"
    assert [step["id"] for step in loaded["steps"]] == expected[recipe_id]

assert recipe_links["repo_native_dev_loop"] == "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.repo_native_dev_loop.yaml"
assert recipe_links["operator_cpu_loop"] == "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_cpu_loop.yaml"
assert recipe_links["operator_gpu_loop"] == "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_gpu_loop.yaml"
assert recipe_links["recovery_resume_loop"] == "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.recovery_resume_loop.yaml"
PY

jq -e '
  .status == "ok"
  and .recipe_id == "beagle-darwin-hpc-governance.repo_native_dev_loop"
  and .recipe_steps == ["edit", "build", "deploy", "validate", "handoff"]
  and .loop_kind == "repo_native_dev_loop"
  and .changed_file_count >= 1
  and .bridge_status == "success"
  and .active_dev_plane == "beagle-cluster"
  and .fallback_active == false
  and .postdeploy_default_dev_plane == "beagle-cluster"
  and .postdeploy_vm_fallback_role == "fallback-only"
  and .postdeploy_promotion_scope == "beagle-darwin-hpc-general-noninfra"
  and .handoff_ready == true
' "${OUT}/repo-native-loop.json" >/dev/null

jq -e '
  .status == "ok"
  and .recipe_id == "beagle-darwin-hpc-governance.operator_cpu_loop"
  and .recipe_steps == ["bootstrap", "control_surface_lookup", "submit_cpu_batch", "result_resolution", "persist_state"]
  and .loop_kind == "operator_cpu_loop"
  and .submitted_profile_id == "cpu-batch-v1"
  and .final_job_state == "COMPLETED"
  and .published_result_job_id >= 1
  and .active_dev_plane == "beagle-cluster"
  and .fallback_active == false
' "${OUT}/operator-cpu-loop.json" >/dev/null

jq -e '
  .status == "ok"
  and .recipe_id == "beagle-darwin-hpc-governance.operator_gpu_loop"
  and .recipe_steps == ["bootstrap", "control_surface_lookup", "submit_gpu_single", "publication_retrieval", "persist_state"]
  and .loop_kind == "operator_gpu_loop"
  and .submitted_profile_id == "gpu-single-v1"
  and .final_job_state == "COMPLETED"
  and .expected_execution_node == "r740-proxmox"
  and .final_job_node_list == "r740-proxmox"
  and .published_result_job_id >= 1
  and .active_dev_plane == "beagle-cluster"
  and .fallback_active == false
' "${OUT}/operator-gpu-loop.json" >/dev/null

jq -e '
  .status == "ok"
  and .recipe_id == "beagle-darwin-hpc-governance.recovery_resume_loop"
  and .recipe_steps == ["session_restart", "repo_branch_recovery", "last_task_result_recovery", "resume_semantics"]
  and .loop_kind == "recovery_resume_loop"
  and .same_session_line == true
  and .workstream_name == "beagle-darwin-hpc-governance"
  and .promotion_scope == "beagle-darwin-hpc-general-noninfra"
  and .active_dev_plane_after_restart == "beagle-cluster"
  and .fallback_active_after_restart == false
  and .last_task_kind == "advanced_operator_gpu_workflow"
  and .last_published_result_job_id >= 1
  and .handoff_present == true
' "${OUT}/recovery-resume-loop.json" >/dev/null

jq -e '
  .status == "ok"
  and .phase == "B14.3"
  and .workstream_id == "beagle-darwin-hpc-governance"
  and .recipe_count == 4
  and (.recipe_ids | index("beagle-darwin-hpc-governance.repo_native_dev_loop") != null)
  and (.recipe_ids | index("beagle-darwin-hpc-governance.operator_cpu_loop") != null)
  and (.recipe_ids | index("beagle-darwin-hpc-governance.operator_gpu_loop") != null)
  and (.recipe_ids | index("beagle-darwin-hpc-governance.recovery_resume_loop") != null)
  and .repo_native_dev_loop == "ok"
  and .operator_cpu_loop == "ok"
  and .operator_gpu_loop == "ok"
  and .recovery_resume_loop == "ok"
  and .default_dev_plane == "beagle-cluster"
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).+UP|Slurmctld\(primary\) at .+ is UP' "${OUT}/final-cluster-health.txt"

echo "[OK] workstream recipe smoke validation passed"
