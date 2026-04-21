#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/replay-branch-fork-execution}"
B256_BASE_OUT="${B256_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/code-provenance-capture}"
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
  replay-request-before.json \
  replay-execution-replay-request.json \
  replay-execution-replay-response.json \
  run-capsule-after-replay.json \
  replay-request-after-replay.json \
  replay-execution-fork-request.json \
  replay-execution-fork-response.json \
  replay-execution-latest.json \
  run-capsule-after-fork.json \
  run-diff-after-fork.json \
  replay-request-after-fork.json \
  replay-execution-after-restart.json \
  run-capsule-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  session-id.txt \
  replay-run-label.txt \
  fork-run-label.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B256_BASE_OUT}/smoke.json"

jq -e '
  .replay_execution_source_present == 1 and
  .run_capsule_source_present == 1 and
  .workbench_run_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .replay_request_schema_present == 1 and
  .replay_execution_schema_present == 1 and
  .b256_base_present == 1 and
  (.expected_branch | length) > 0 and
  (.expected_commit | length) > 0 and
  (.expected_tree_ish | length) > 0 and
  (.expected_source_fingerprint | length) > 0
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.6" and
  .same_beagle_owned_identity == true and
  .code_diff_explicit == true and
  .deterministic_identity_confirmed == true
' "${B256_BASE_OUT}/smoke.json" >/dev/null

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/session-id.txt")"
REPLAY_RUN_LABEL="$(cat "${OUT}/replay-run-label.txt")"
FORK_RUN_LABEL="$(cat "${OUT}/fork-run-label.txt")"
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
[[ -n "${REPLAY_RUN_LABEL}" ]] || { echo "[FAIL] replay-run-label.txt is empty" >&2; exit 1; }
[[ -n "${FORK_RUN_LABEL}" ]] || { echo "[FAIL] fork-run-label.txt is empty" >&2; exit 1; }

jq -e '.status == "ok"' "${OUT}/health-before.json" >/dev/null
jq -e '.status == "ok"' "${OUT}/health-after.json" >/dev/null

jq -e \
  --arg run_label "${REPLAY_RUN_LABEL}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg patch_ref "${EXPECTED_PATCH_REF}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .execution_mode == "replay" and
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
' "${OUT}/replay-execution-replay-request.json" >/dev/null

jq -e \
  --arg run_label "${FORK_RUN_LABEL}" '
  .requested_by == "partner-dev" and
  .requester_role_id == "partner-dev" and
  .execution_mode == "branch-fork" and
  .run_label == $run_label
' "${OUT}/replay-execution-fork-request.json" >/dev/null

SOURCE_RUN_ID_BEFORE="$(jq -r '.source_run_id' "${OUT}/replay-request-before.json")"
REPLAY_RUN_ID="$(jq -r '.run_orchestration.run.run_id' "${OUT}/replay-execution-replay-response.json")"
FORK_RUN_ID="$(jq -r '.run_orchestration.run.run_id' "${OUT}/replay-execution-fork-response.json")"

[[ -n "${SOURCE_RUN_ID_BEFORE}" && "${SOURCE_RUN_ID_BEFORE}" != "null" ]] || {
  echo "[FAIL] replay-request-before.json missing source_run_id" >&2
  exit 1
}
[[ -n "${REPLAY_RUN_ID}" && "${REPLAY_RUN_ID}" != "null" ]] || {
  echo "[FAIL] replay-execution-replay-response.json missing replay run id" >&2
  exit 1
}
[[ -n "${FORK_RUN_ID}" && "${FORK_RUN_ID}" != "null" ]] || {
  echo "[FAIL] replay-execution-fork-response.json missing fork run id" >&2
  exit 1
}

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg source_run_id "${SOURCE_RUN_ID_BEFORE}" \
  --arg replay_run_label "${REPLAY_RUN_LABEL}" '
  .status == "ok" and
  .phase == "B25.7" and
  .replay_request.workstream_id == $workstream_id and
  .replay_request.workspace_id == $workspace_id and
  .replay_request.session_id == $session_id and
  .replay_execution.workstream_id == $workstream_id and
  .replay_execution.workspace_id == $workspace_id and
  .replay_execution.session_id == $session_id and
  .replay_execution.same_beagle_owned_identity == true and
  .replay_execution.execution_mode == "replay" and
  .replay_execution.source_run_id == $source_run_id and
  .run_orchestration.run.run_label == $replay_run_label and
  .run_orchestration.run.same_beagle_owned_identity == true and
  .run_orchestration.phase == "B25.3"
' "${OUT}/replay-execution-replay-response.json" >/dev/null

jq -e \
  --arg replay_run_id "${REPLAY_RUN_ID}" \
  --arg replay_run_label "${REPLAY_RUN_LABEL}" '
  .run_id == $replay_run_id and
  .run_label == $replay_run_label and
  .same_beagle_owned_identity == true
' "${OUT}/run-capsule-after-replay.json" >/dev/null

jq -e \
  --arg replay_run_id "${REPLAY_RUN_ID}" '
  .source_run_id == $replay_run_id and
  (.source_run_label | length) > 0 and
  (.source_intent_text | length) > 0 and
  (.replay_execution_path | length) > 0
' "${OUT}/replay-request-after-replay.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg replay_run_id "${REPLAY_RUN_ID}" \
  --arg fork_run_label "${FORK_RUN_LABEL}" '
  .status == "ok" and
  .phase == "B25.7" and
  .replay_execution.workstream_id == $workstream_id and
  .replay_execution.workspace_id == $workspace_id and
  .replay_execution.session_id == $session_id and
  .replay_execution.same_beagle_owned_identity == true and
  .replay_execution.execution_mode == "branch-fork" and
  .replay_execution.source_run_id == $replay_run_id and
  .run_orchestration.run.run_label == $fork_run_label and
  .run_orchestration.run.same_beagle_owned_identity == true
' "${OUT}/replay-execution-fork-response.json" >/dev/null

jq -e \
  --arg run_id "${FORK_RUN_ID}" \
  --arg run_label "${FORK_RUN_LABEL}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg tree_ish "${EXPECTED_TREE_ISH}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg patch_ref "${EXPECTED_PATCH_REF}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .run_id == $run_id and
  .run_label == $run_label and
  .same_beagle_owned_identity == true and
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
  .code_provenance.dirty_state == $dirty_state and
  .source_fingerprint.source_fingerprint == $source_fingerprint
' "${OUT}/run-capsule-after-fork.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg run_id "${FORK_RUN_ID}" \
  --arg replay_run_id "${REPLAY_RUN_ID}" '
  .phase == "B25.6" and
  .contract_kind == "run-diff" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .current_run_id == $run_id and
  .prior_run_id == $replay_run_id and
  .lineage_relation == "direct-parent" and
  .result.changed == true and
  (.changed_categories | index("result")) != null and
  (.code.prior_summary | length) > 0 and
  (.code.current_summary | length) > 0
' "${OUT}/run-diff-after-fork.json" >/dev/null

jq -e \
  --arg run_id "${FORK_RUN_ID}" \
  --arg source_run_id "${REPLAY_RUN_ID}" '
  .dispatched_run_id == $run_id and
  .source_run_id == $source_run_id and
  .execution_mode == "branch-fork" and
  .same_beagle_owned_identity == true
' "${OUT}/replay-execution-latest.json" >/dev/null

jq -e \
  --arg run_id "${FORK_RUN_ID}" \
  --arg run_label "${FORK_RUN_LABEL}" \
  --arg branch "${EXPECTED_BRANCH}" \
  --arg commit "${EXPECTED_COMMIT}" \
  --arg dirty_state "${EXPECTED_DIRTY_STATE}" \
  --arg source_fingerprint "${EXPECTED_SOURCE_FINGERPRINT}" '
  .status == "ok" and
  .phase == "B25.7" and
  .same_beagle_owned_identity == true and
  .branch_fork_run_id == $run_id and
  .branch_fork_run_label == $run_label and
  .source_branch == $branch and
  .source_commit == $commit and
  .source_dirty_state == $dirty_state and
  .source_source_fingerprint == $source_fingerprint and
  .code_diff_explicit == true and
  .branch_fork_lineage_relation == "direct-parent" and
  .restart_preserved_latest_receipt == true and
  .restart_preserved_latest_capsule == true
' "${OUT}/smoke.json" >/dev/null

jq -e \
  --arg run_id "${FORK_RUN_ID}" '
  .dispatched_run_id == $run_id and
  .execution_mode == "branch-fork" and
  .same_beagle_owned_identity == true
' "${OUT}/replay-execution-after-restart.json" >/dev/null

jq -e --arg run_id "${FORK_RUN_ID}" '.run_id == $run_id' "${OUT}/run-capsule-after-restart.json" >/dev/null

grep -Eq 'beagle-core|beagle-workspace|Slurmctld' "${OUT}/final-cluster-health.txt"

echo "[OK] replay / branch fork execution smoke artifacts validated"
