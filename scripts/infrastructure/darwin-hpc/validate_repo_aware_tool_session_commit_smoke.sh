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
  source-summary.json \
  build.log \
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health-before.json \
  bootstrap-before.json \
  seed-pilot.json \
  context-packet-before.json \
  step-sequence.json \
  step-1-payload.json \
  step-1-response.json \
  context-packet-after-step-1.json \
  step-2-payload.json \
  step-2-response.json \
  context-packet-after-step-2.json \
  step-3-payload.json \
  step-3-response.json \
  context-packet-after-step-3.json \
  memory-query-after-step-3.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  context-packet-after-restart.json \
  tool-return-ledger-tail.jsonl \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-workstream.txt \
  expected-branch.txt \
  base-commit.txt \
  patch-ref.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt \
  session-output.patch; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
BASE_COMMIT="$(cat "${OUT}/base-commit.txt")"
PATCH_REF="$(cat "${OUT}/patch-ref.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
STEP_1_SUMMARY="$(jq -r '.steps[0].summary' "${OUT}/step-sequence.json")"
STEP_2_SUMMARY="$(jq -r '.steps[1].summary' "${OUT}/step-sequence.json")"
STEP_3_SUMMARY="$(jq -r '.steps[2].summary' "${OUT}/step-sequence.json")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg base_commit "${BASE_COMMIT}" \
  --arg patch_ref "${PATCH_REF}" '
  .expected_workstream == $expected_workstream
  and .expected_branch == $expected_branch
  and .base_commit == $base_commit
  and .patch_ref == $patch_ref
  and (.patch_ref_source_present == true or .patch_ref_source_present == 1)
  and (.repo_patch_test_present == true or .repo_patch_test_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
' "${OUT}/source-summary.json" >/dev/null

grep -Eq '^diff --git ' "${OUT}/session-output.patch"

jq -e \
  --arg patch_ref "${PATCH_REF}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg base_commit "${BASE_COMMIT}" '
  (.steps | length) == 3
  and (.steps[0].tool == "codex")
  and (.steps[1].tool == "claude-code")
  and (.steps[2].tool == "cursor")
  and (.steps[2].patch_ref == $patch_ref)
  and (.steps[2].repo_refs.branch == $expected_branch)
  and (.steps[2].repo_refs.commit == $base_commit)
' "${OUT}/step-sequence.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .published_result.job_id == $published_result_job_id
' "${OUT}/seed-pilot.json" >/dev/null

for step_num in 1 2 3; do
  STEP_TOOL="$(jq -r ".steps[$((step_num - 1))].tool" "${OUT}/step-sequence.json")"
  STEP_ACTION="$(jq -r ".steps[$((step_num - 1))].action_type" "${OUT}/step-sequence.json")"
  STEP_SUMMARY="$(jq -r ".steps[$((step_num - 1))].summary" "${OUT}/step-sequence.json")"

  jq -e \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SESSION_ID}" \
    --arg step_tool "${STEP_TOOL}" \
    --arg step_action "${STEP_ACTION}" '
    .workstream_id == $expected_workstream
    and .workspace_id == $workspace_id
    and .session_id == $session_id
    and .tool == $step_tool
    and .action_type == $step_action
  ' "${OUT}/step-${step_num}-payload.json" >/dev/null

  jq -e \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SESSION_ID}" \
    --arg step_tool "${STEP_TOOL}" \
    --arg step_action "${STEP_ACTION}" '
    .status == "ok"
    and .workstream_id == $expected_workstream
    and .workspace_id == $workspace_id
    and .session_id == $session_id
    and .tool == $step_tool
    and .action_type == $step_action
    and .handoff_updated == true
    and .memory_ingested == true
    and (.memory_id != null)
    and .ledger_appended == true
  ' "${OUT}/step-${step_num}-response.json" >/dev/null

  jq -e \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SESSION_ID}" \
    --arg step_summary "${STEP_SUMMARY}" \
    --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
    .status == "ok"
    and .packet.workstream_id == $expected_workstream
    and .packet.workspace_id == $workspace_id
    and .packet.session_id == $session_id
    and .packet.last_result.summary.job_id == $published_result_job_id
    and (.packet.handoff.last_handoff | contains($step_summary))
  ' "${OUT}/context-packet-after-step-${step_num}.json" >/dev/null
done

jq -e \
  --arg patch_ref "${PATCH_REF}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg base_commit "${BASE_COMMIT}" '
  .patch_ref == $patch_ref
  and (.last_handoff | contains($patch_ref))
  and (.last_handoff | contains($expected_branch))
  and (.last_handoff | contains($base_commit))
' "${OUT}/step-3-response.json" >/dev/null

jq -e \
  --arg step_1_summary "${STEP_1_SUMMARY}" \
  --arg step_2_summary "${STEP_2_SUMMARY}" \
  --arg step_3_summary "${STEP_3_SUMMARY}" \
  --arg patch_ref "${PATCH_REF}" '
  (.packet.handoff.last_handoff | contains($step_3_summary))
  and (.packet.handoff.last_handoff | contains($step_2_summary))
  and (.packet.handoff.last_handoff | contains($step_1_summary))
  and (.packet.handoff.last_handoff | contains($patch_ref))
' "${OUT}/context-packet-after-step-3.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" '
  (.highlights | map(select((.conversation_id // "") == $session_id and (.source // "") == "codex")) | length) >= 1
  and (.highlights | map(select((.conversation_id // "") == $session_id and (.source // "") == "claude-code")) | length) >= 1
  and (.highlights | map(select((.conversation_id // "") == $session_id and (.source // "") == "cursor")) | length) >= 1
' "${OUT}/memory-query-after-step-3.json" >/dev/null

jq -s -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg patch_ref "${PATCH_REF}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg base_commit "${BASE_COMMIT}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  map(select(.workspace_id == $workspace_id and .session_id == $session_id)) as $entries
  | ($entries | length) == 3
  and (($entries | map(.tool)) == ["codex", "claude-code", "cursor"])
  and (($entries | map(.action_type)) == ["implementation", "analysis", "note"])
  and (($entries[-1].patch_ref // "") == $patch_ref)
  and (($entries[-1].repo_refs.branch // "") == $expected_branch)
  and (($entries[-1].repo_refs.commit // "") == $base_commit)
  and (($entries[-1].repo_refs.paths | length) >= 2)
  and (($entries[-1].result_refs[0]) == ("result:" + ($published_result_job_id | tostring)))
' "${OUT}/tool-return-ledger-tail.jsonl" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg step_1_summary "${STEP_1_SUMMARY}" \
  --arg step_2_summary "${STEP_2_SUMMARY}" \
  --arg step_3_summary "${STEP_3_SUMMARY}" \
  --arg patch_ref "${PATCH_REF}" '
  .status == "ok"
  and .packet.workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and (.packet.handoff.last_handoff | contains($step_1_summary))
  and (.packet.handoff.last_handoff | contains($step_2_summary))
  and (.packet.handoff.last_handoff | contains($step_3_summary))
  and (.packet.handoff.last_handoff | contains($patch_ref))
' "${OUT}/context-packet-after-restart.json" >/dev/null

jq -e \
  --arg patch_ref "${PATCH_REF}" \
  --arg base_commit "${BASE_COMMIT}" '
  .status == "ok"
  and .step_count == 3
  and .tools == ["codex", "claude-code", "cursor"]
  and .action_types == ["implementation", "analysis", "note"]
  and .patch_ref == $patch_ref
  and .step_3_patch_ref == $patch_ref
  and .base_commit == $base_commit
  and .patch_bytes > 0
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] repo-aware tool session commit validator passed"
