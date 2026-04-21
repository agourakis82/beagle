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
  tool-cursor.json \
  tool-claude-code.json \
  tool-codex.json \
  tool-return-payload.json \
  tool-return-response.json \
  context-packet-after-return.json \
  memory-query-after-return.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  context-packet-after-restart.json \
  tool-return-ledger-tail.jsonl \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt \
  expected-workstream.txt \
  expected-tool.txt \
  expected-action-type.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_TOOL="$(cat "${OUT}/expected-tool.txt")"
EXPECTED_ACTION_TYPE="$(cat "${OUT}/expected-action-type.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_tool "${EXPECTED_TOOL}" \
  --arg expected_action_type "${EXPECTED_ACTION_TYPE}" '
  .expected_workstream == $expected_workstream
  and .expected_tool == $expected_tool
  and .expected_action_type == $expected_action_type
  and (.tool_return_source_present == true or .tool_return_source_present == 1)
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .published_result.job_id == $published_result_job_id
' "${OUT}/seed-pilot.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .packet.workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and .packet.handoff.handoff_present == true
' "${OUT}/context-packet-before.json" >/dev/null

for tool_file in tool-cursor.json tool-claude-code.json tool-codex.json; do
  jq -e \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SESSION_ID}" '
    .status == "ok"
    and .tool.tool_return_path == ("/api/darwin/workstreams/" + $expected_workstream + "/tool-return")
    and .context_packet.workstream_id == $expected_workstream
    and .context_packet.workspace_id == $workspace_id
    and .context_packet.session_id == $session_id
  ' "${OUT}/${tool_file}" >/dev/null
done

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_tool "${EXPECTED_TOOL}" \
  --arg expected_action_type "${EXPECTED_ACTION_TYPE}" '
  .workstream_id == $expected_workstream
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .tool == $expected_tool
  and .action_type == $expected_action_type
' "${OUT}/tool-return-payload.json" >/dev/null

RETURN_SUMMARY="$(jq -r '.summary' "${OUT}/tool-return-payload.json")"
MEMORY_TEXT="$(jq -r '.memory_text' "${OUT}/tool-return-payload.json")"
HANDOFF_PATCH="$(jq -r '.handoff_patch' "${OUT}/tool-return-payload.json")"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_tool "${EXPECTED_TOOL}" \
  --arg expected_action_type "${EXPECTED_ACTION_TYPE}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .tool == $expected_tool
  and .action_type == $expected_action_type
  and .handoff_updated == true
  and .memory_ingested == true
  and (.memory_id != null)
  and .ledger_appended == true
' "${OUT}/tool-return-response.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg return_summary "${RETURN_SUMMARY}" \
  --arg handoff_patch "${HANDOFF_PATCH}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .packet.workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and .packet.last_result.summary.job_id == $published_result_job_id
  and (.packet.handoff.last_handoff | contains($return_summary))
  and (.packet.handoff.last_handoff | contains($handoff_patch))
' "${OUT}/context-packet-after-return.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" \
  --arg expected_tool "${EXPECTED_TOOL}" \
  --arg memory_text "${MEMORY_TEXT}" '
  (.highlights | length) >= 1
  and ((.highlights | map(select((.conversation_id // "") == $session_id and (.source // "") == $expected_tool and (.snippet // "" | contains($memory_text[0:40])))) | length) >= 1)
' "${OUT}/memory-query-after-return.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg return_summary "${RETURN_SUMMARY}" '
  .status == "ok"
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and (.packet.handoff.last_handoff | contains($return_summary))
' "${OUT}/context-packet-after-restart.json" >/dev/null

grep -F "\"workstream_id\":\"${EXPECTED_WORKSTREAM}\"" "${OUT}/tool-return-ledger-tail.jsonl" >/dev/null
grep -F "\"workspace_id\":\"${WORKSPACE_ID}\"" "${OUT}/tool-return-ledger-tail.jsonl" >/dev/null
grep -F "\"session_id\":\"${SESSION_ID}\"" "${OUT}/tool-return-ledger-tail.jsonl" >/dev/null
grep -F "\"tool\":\"${EXPECTED_TOOL}\"" "${OUT}/tool-return-ledger-tail.jsonl" >/dev/null
grep -F "\"action_type\":\"${EXPECTED_ACTION_TYPE}\"" "${OUT}/tool-return-ledger-tail.jsonl" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_tool "${EXPECTED_TOOL}" \
  --arg expected_action_type "${EXPECTED_ACTION_TYPE}" \
  --arg return_summary "${RETURN_SUMMARY}" \
  --arg memory_text "${MEMORY_TEXT}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .expected_workstream == $expected_workstream
  and .expected_tool == $expected_tool
  and .expected_action_type == $expected_action_type
  and (.tool_return_memory_id != null)
  and (.handoff_after_return | contains($return_summary))
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] tool return path validator passed"
