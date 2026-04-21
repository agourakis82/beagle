#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:?OUT is required}"
BASE_OUT="${BASE_OUT:-${OUT}/habitat}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq

for file in \
  source-summary.json \
  cursor-remote-lane.json \
  tool-cursor.json \
  workspace-context.json \
  workspace-context-after-restart.json \
  workspace-runtime-summary.json \
  workspace-health.txt \
  workspace-context-env-file-after-restart.txt \
  smoke.json \
  final-cluster-health.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

for file in \
  smoke.json \
  workspace-id.txt \
  seed-session-id.txt \
  expected-workstream.txt \
  expected-browser-url.txt \
  expected-context-packet-file.txt \
  expected-context-env-file.txt \
  workspace-context.json \
  workspace-context-after-restart.json; do
  [[ -s "${BASE_OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty habitat artifact: ${BASE_OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${BASE_OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${BASE_OUT}/seed-session-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${BASE_OUT}/expected-workstream.txt")"
EXPECTED_BROWSER_URL="$(cat "${BASE_OUT}/expected-browser-url.txt")"
EXPECTED_CONTEXT_PACKET_FILE="$(cat "${BASE_OUT}/expected-context-packet-file.txt")"
EXPECTED_CONTEXT_ENV_FILE="$(cat "${BASE_OUT}/expected-context-env-file.txt")"

jq -e '.status == "ok" and .restart_recovered_session == true' "${BASE_OUT}/smoke.json" >/dev/null

jq -e '
  (.cursor_lane_source_present == true or .cursor_lane_source_present == 1)
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_browser_url "${EXPECTED_BROWSER_URL}" \
  --arg expected_context_packet_file "${EXPECTED_CONTEXT_PACKET_FILE}" \
  --arg expected_context_env_file "${EXPECTED_CONTEXT_ENV_FILE}" '
  .status == "ok"
  and .phase == "B20.2"
  and .lane.lane_kind == "cursor-remote-lane"
  and .lane.workstream_id == $expected_workstream
  and .lane.workspace_id == $workspace_id
  and .lane.session_id == $session_id
  and .habitat.workstream_id == $expected_workstream
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
  and .context_packet.workstream_id == $expected_workstream
  and .context_packet.workspace_id == $workspace_id
  and .context_packet.session_id == $session_id
  and .lane.connection_metadata.remote_client == "cursor"
  and .lane.connection_metadata.connection_mode == "same-workspace-browser-first"
  and .lane.connection_metadata.recommended_transport == "kubernetes-port-forward"
  and .lane.connection_metadata.ssh_transport_ready == false
  and .lane.connection_metadata.browser_url == $expected_browser_url
  and .lane.connection_metadata.context_packet_file == $expected_context_packet_file
  and .lane.connection_metadata.context_env_file == $expected_context_env_file
  and .lane.tool_launch_path == ("/api/darwin/workstreams/" + $expected_workstream + "/tool-dock/cursor")
  and .lane.tool_return_path == ("/api/darwin/workstreams/" + $expected_workstream + "/tool-return")
' "${OUT}/cursor-remote-lane.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .tool.tool_id == "cursor"
  and .tool.remote_lane_kind == "cursor-remote-lane"
  and .tool.remote_lane_path == ("/api/darwin/workstreams/" + $expected_workstream + "/cursor-remote-lane")
  and .tool.workspace_habitat_path == ("/api/darwin/workstreams/" + $expected_workstream + "/workspace-habitat")
' "${OUT}/tool-cursor.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .habitat.workstream_id == $expected_workstream
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
' "${OUT}/workspace-context.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
' "${OUT}/workspace-context-after-restart.json" >/dev/null

grep -Fq "export BEAGLE_CURSOR_REMOTE_LANE_PATH='/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cursor-remote-lane'" "${OUT}/workspace-context-env-file-after-restart.txt"
grep -Eq '<!DOCTYPE html>|<html|OpenVSCode|openvscode|workbench' "${OUT}/workspace-health.txt"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_browser_url "${EXPECTED_BROWSER_URL}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .lane_kind == "cursor-remote-lane"
  and .connection_mode == "same-workspace-browser-first"
  and .recommended_transport == "kubernetes-port-forward"
  and .browser_url == $expected_browser_url
  and .restart_recovered_session == true
  and .ssh_transport_ready == false
' "${OUT}/smoke.json" >/dev/null

grep -q 'beagle-workspace' "${OUT}/final-cluster-health.txt"
grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"

echo "[OK] cursor remote lane smoke artifacts validated"
