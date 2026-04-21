#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-registry-sweep}"
B257_BASE_OUT="${B257_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/replay-branch-fork-execution}"
B255_BASE_OUT="${B255_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/reproducibility-capsule}"
B253_BASE_OUT="${B253_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/workbench-orchestration}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"

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
  study-registry.json \
  study-dag.json \
  study-sweep.json \
  comparative-result-summary.json \
  study-registry-after-restart.json \
  comparative-result-summary-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  session-id.txt \
  study-id.txt \
  baseline-run-id.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B257_BASE_OUT}/smoke.json"
require_file "${B255_BASE_OUT}/smoke.json"
require_file "${B253_BASE_OUT}/smoke.json"

jq -e '
  .study_registry_source_present == 1 and
  .study_dag_source_present == 1 and
  .study_sweep_source_present == 1 and
  .workbench_run_source_present == 1 and
  .workbench_result_binding_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .study_registry_schema_present == 1 and
  .study_dag_schema_present == 1 and
  .study_sweep_schema_present == 1 and
  .b257_base_present == 1 and
  .b255_base_present == 1 and
  .b253_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '.status == "ok" and .phase == "B25.7" and .same_beagle_owned_identity == true' "${B257_BASE_OUT}/smoke.json" >/dev/null
jq -e '.status == "ok" and .phase == "B25.5" and .same_beagle_owned_identity == true' "${B255_BASE_OUT}/smoke.json" >/dev/null
jq -e '.status == "ok" and .phase == "B25.3" and .same_beagle_owned_identity == true' "${B253_BASE_OUT}/smoke.json" >/dev/null

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/session-id.txt")"
STUDY_ID="$(cat "${OUT}/study-id.txt")"
BASELINE_RUN_ID="$(cat "${OUT}/baseline-run-id.txt")"

[[ -n "${WORKSPACE_ID}" ]] || { echo "[FAIL] workspace-id.txt is empty" >&2; exit 1; }
[[ -n "${SESSION_ID}" ]] || { echo "[FAIL] session-id.txt is empty" >&2; exit 1; }
[[ -n "${STUDY_ID}" ]] || { echo "[FAIL] study-id.txt is empty" >&2; exit 1; }
[[ -n "${BASELINE_RUN_ID}" ]] || { echo "[FAIL] baseline-run-id.txt is empty" >&2; exit 1; }

jq -e '.status == "ok"' "${OUT}/health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/health-after.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg study_id "${STUDY_ID}" \
  --arg baseline_run_id "${BASELINE_RUN_ID}" '
  .phase == "B26.1" and
  .contract_kind == "study-registry" and
  .contract_version == "beagle-study-registry-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .study_id == $study_id and
  .baseline_run_id == $baseline_run_id and
  .same_beagle_owned_identity == true and
  .run_count >= 1 and
  .variant_count >= 1 and
  (.run_ids | length) == .run_count and
  (.runs | length) == .run_count and
  (.variant_ids | length) == .variant_count
' "${OUT}/study-registry.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg study_id "${STUDY_ID}" '
  .phase == "B26.1" and
  .contract_kind == "study-dag" and
  .contract_version == "beagle-study-dag-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .study_id == $study_id and
  .same_beagle_owned_identity == true and
  .node_count == (.nodes | length) and
  .edge_count == (.edges | length) and
  (.nodes | length) >= 2 and
  (.edges | length) >= 1 and
  any(.nodes[]; .node_kind == "study")
' "${OUT}/study-dag.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg study_id "${STUDY_ID}" '
  .phase == "B26.1" and
  .contract_kind == "study-sweep" and
  .contract_version == "beagle-study-sweep-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .study_id == $study_id and
  .same_beagle_owned_identity == true and
  .variant_count == (.variants | length) and
  .run_count >= 1 and
  .variant_count >= 1 and
  any(.variants[]; .variant_kind == "baseline")
' "${OUT}/study-sweep.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg study_id "${STUDY_ID}" \
  --arg baseline_run_id "${BASELINE_RUN_ID}" '
  .phase == "B26.1" and
  .contract_kind == "comparative-result-summary" and
  .contract_version == "beagle-comparative-result-summary-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .study_id == $study_id and
  .baseline_run_id == $baseline_run_id and
  .same_beagle_owned_identity == true and
  .compared_run_count == (.runs | length) and
  (.changed_categories_union | type) == "array"
' "${OUT}/comparative-result-summary.json" >/dev/null

jq -e \
  --arg study_id "${STUDY_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .study_id == $study_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true
' "${OUT}/study-registry-after-restart.json" >/dev/null

jq -e \
  --arg study_id "${STUDY_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .study_id == $study_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true
' "${OUT}/comparative-result-summary-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg study_id "${STUDY_ID}" '
  .status == "ok" and
  .phase == "B26.1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .study_id == $study_id and
  .study_registered == true and
  .multiple_runs_tied == true and
  .bounded_sweep_represented == true and
  .comparative_summary_generated == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\)|slurm' "${OUT}/final-cluster-health.txt"

echo "[OK] study registry / sweep smoke artifacts validated"
