#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/code-provenance-capture}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B255_BASE_OUT="${B255_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/reproducibility-capsule}"

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
  code-provenance.json \
  workspace-snapshot.json \
  source-fingerprint.json \
  run-capsule-with-code.json \
  run-diff-with-code.json \
  workbench-context-after-run.json \
  bootstrap-after-restart.json \
  run-capsule-after-restart.json \
  code-provenance-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  session-id.txt \
  run-label.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B255_BASE_OUT}/smoke.json"

jq -e '
  .code_provenance_source_present == 1 and
  .workspace_snapshot_source_present == 1 and
  .source_fingerprint_source_present == 1 and
  .run_capsule_source_present == 1 and
  .run_diff_source_present == 1 and
  .workbench_run_source_present == 1 and
  .workspace_plane_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .code_provenance_schema_present == 1 and
  .workspace_snapshot_schema_present == 1 and
  .source_fingerprint_schema_present == 1 and
  .b255_base_present == 1 and
  (.expected_branch | length) > 0 and
  (.expected_commit | length) > 0 and
  (.expected_tree_ish | length) > 0 and
  (.expected_source_fingerprint | length) > 0
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.5" and
  .same_beagle_owned_identity == true and
  .code_diff_explicit == true and
  .config_changed == true and
  .environment_changed == true and
  .result_changed == true
' "${B255_BASE_OUT}/smoke.json" >/dev/null

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/session-id.txt")"
RUN_LABEL="$(cat "${OUT}/run-label.txt")"
EXPECTED_BRANCH="$(jq -r '.expected_branch' "${OUT}/source-summary.json")"
EXPECTED_COMMIT="$(jq -r '.expected_commit' "${OUT}/source-summary.json")"
EXPECTED_TREE_ISH="$(jq -r '.expected_tree_ish' "${OUT}/source-summary.json")"
EXPECTED_DIRTY_STATE="$(jq -r '.expected_dirty_state' "${OUT}/source-summary.json")"
EXPECTED_PATCH_REF="$(jq -r '.expected_patch_ref // empty' "${OUT}/source-summary.json")"
EXPECTED_SOURCE_FINGERPRINT="$(jq -r '.expected_source_fingerprint' "${OUT}/source-summary.json")"
EXPECTED_ATTESTED_REPO_ROOT="$(jq -r '.attested_repo_root' "${OUT}/source-summary.json")"
EXPECTED_LOCKFILE_COUNT="$(jq -r '.expected_lockfile_fingerprints | length' "${OUT}/source-summary.json")"

[[ -n "${WORKSPACE_ID}" ]] || { echo "[FAIL] workspace-id.txt is empty" >&2; exit 1; }
[[ -n "${SESSION_ID}" ]] || { echo "[FAIL] session-id.txt is empty" >&2; exit 1; }
[[ -n "${RUN_LABEL}" ]] || { echo "[FAIL] run-label.txt is empty" >&2; exit 1; }

jq -e '.status == "ok"' "${OUT}/health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/health-after.json" >/dev/null

jq -e \
  --arg run_label "${RUN_LABEL}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg patch_ref "${EXPECTED_PATCH_REF}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .selected_subagent_id == "experiments" and
  .task_family == "analysis" and
  .compute_profile_id == "cpu-short-v1" and
  .run_label == $run_label and
  .code_provenance_capture.workspace_snapshot.branch == $branch and
  .code_provenance_capture.workspace_snapshot.commit == $commit and
  .code_provenance_capture.workspace_snapshot.tree_ish == $tree_ish and
  .code_provenance_capture.workspace_snapshot.dirty_state == $dirty_state and
  (
    if $patch_ref == "" then
      (.code_provenance_capture.workspace_snapshot.patch_ref == null)
    else
      (.code_provenance_capture.workspace_snapshot.patch_ref == $patch_ref)
    end
  ) and
  .code_provenance_capture.source_fingerprint.source_fingerprint == $source_fingerprint
' "${OUT}/workbench-run-request.json" >/dev/null

jq -e '.status == "ok" and .phase == "B25.3"' "${OUT}/workbench-run-dispatch-response.json" >/dev/null

RUN_ID="$(jq -r '.run_id' "${OUT}/run-capsule-with-code.json")"
SUBMITTED_JOB_ID="$(jq -r '.submitted_job_id' "${OUT}/run-capsule-with-code.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result_job_id' "${OUT}/run-capsule-with-code.json")"

[[ -n "${RUN_ID}" && "${RUN_ID}" != "null" ]] || { echo "[FAIL] run-capsule-with-code.json missing run_id" >&2; exit 1; }

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --arg repo_root "${EXPECTED_ATTESTED_REPO_ROOT}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg patch_ref "${EXPECTED_PATCH_REF}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" \
  --argjson expected_lockfile_count "${EXPECTED_LOCKFILE_COUNT}" '
  .phase == "B25.6" and
  .contract_kind == "code-provenance" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .run_label == $run_label and
  .repo_root == $repo_root and
  .branch == $branch and
  .commit == $commit and
  .tree_ish == $tree_ish and
  .dirty_state == $dirty_state and
  (
    if $patch_ref == "" then
      (.patch_ref == null)
    else
      (.patch_ref == $patch_ref)
    end
  ) and
  .source_fingerprint == $source_fingerprint and
  (.lockfile_fingerprints | length) == $expected_lockfile_count and
  (.artifact_manifest_key | length) > 0
' "${OUT}/code-provenance.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --arg repo_root "${EXPECTED_ATTESTED_REPO_ROOT}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg patch_ref "${EXPECTED_PATCH_REF}" '
  .phase == "B25.6" and
  .contract_kind == "workspace-snapshot" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .run_label == $run_label and
  .repo_root == $repo_root and
  .branch == $branch and
  .commit == $commit and
  .tree_ish == $tree_ish and
  .dirty_state == $dirty_state and
  (
    if $patch_ref == "" then
      (.patch_ref == null)
    else
      (.patch_ref == $patch_ref)
    end
  )
' "${OUT}/workspace-snapshot.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --arg repo_root "${EXPECTED_ATTESTED_REPO_ROOT}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" \
  --argjson expected_lockfile_count "${EXPECTED_LOCKFILE_COUNT}" '
  .phase == "B25.6" and
  .contract_kind == "source-fingerprint" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .run_label == $run_label and
  .repo_root == $repo_root and
  .algorithm == "sha256" and
  .source_fingerprint == $source_fingerprint and
  (.lockfile_fingerprints | length) == $expected_lockfile_count
' "${OUT}/source-fingerprint.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --arg repo_root "${EXPECTED_ATTESTED_REPO_ROOT}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg patch_ref "${EXPECTED_PATCH_REF}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .phase == "B25.6" and
  .contract_kind == "run-capsule" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .run_label == $run_label and
  .git.repo_root == $repo_root and
  .git.branch == $branch and
  .git.commit == $commit and
  .git.tree_ish == $tree_ish and
  (
    if $patch_ref == "" then
      (.git.patch_ref == null)
    else
      (.git.patch_ref == $patch_ref)
    end
  ) and
  (.code_provenance.branch == $branch) and
  (.code_provenance.commit == $commit) and
  (.code_provenance.tree_ish == $tree_ish) and
  (.source_fingerprint.source_fingerprint == $source_fingerprint) and
  .deterministic_identity_confirmed == true and
  (.result_refs | length) >= 3
' "${OUT}/run-capsule-with-code.json" >/dev/null

jq -e \
  --arg run_id "${RUN_ID}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" '
  .phase == "B25.6" and
  .contract_kind == "run-diff" and
  .same_beagle_owned_identity == true and
  .current_run_id == $run_id and
  .current_submitted_job_id == $submitted_job_id and
  (.code.prior_summary | length) > 0 and
  (.code.current_summary | length) > 0 and
  (
    if .code.changed then
      (.changed_categories | index("code")) != null
    else
      (.changed_categories | index("code")) == null and
      .code.changed_fields == []
    end
  ) and
  .result.changed == true
' "${OUT}/run-diff-with-code.json" >/dev/null

jq -e \
  --arg run_id "${RUN_ID}" \
  --arg run_label "${RUN_LABEL}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .status == "ok" and
  .phase == "B25.6" and
  .same_beagle_owned_identity == true and
  .run_id == $run_id and
  .run_label == $run_label and
  .branch == $branch and
  .commit == $commit and
  .tree_ish == $tree_ish and
  .dirty_state == $dirty_state and
  .source_fingerprint == $source_fingerprint and
  .code_diff_explicit == true and
  (
    if .code_changed then
      (.changed_categories | index("code")) != null
    else
      (.changed_categories | index("code")) == null
    end
  ) and
  .bounded_partner_access == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

jq -e --arg run_id "${RUN_ID}" '.run_id == $run_id' "${OUT}/run-capsule-after-restart.json" >/dev/null
jq -e \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .branch == $branch and
  .commit == $commit and
  .tree_ish == $tree_ish and
  .dirty_state == $dirty_state and
  .source_fingerprint == $source_fingerprint
' "${OUT}/code-provenance-after-restart.json" >/dev/null

grep -q 'beagle-core' "${OUT}/final-cluster-health.txt"
grep -q 'beagle-workspace' "${OUT}/final-cluster-health.txt"
grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"

echo "[OK] B25.6 code provenance artifacts validated"
