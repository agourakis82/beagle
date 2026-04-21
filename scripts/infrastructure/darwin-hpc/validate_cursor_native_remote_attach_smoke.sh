#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/cursor-native-remote-attach}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_WORKSPACE_ID="${EXPECTED_WORKSPACE_ID:-beagle-cluster-pilot}"
EXPECTED_SESSION_ID="${EXPECTED_SESSION_ID:-ws-cluster-workspace-habitat}"
EXPECTED_SSH_USER="${EXPECTED_SSH_USER:-openvscode-server}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

require_file "${OUT}/source-summary.json"
require_file "${OUT}/cursor-remote-lane.json"
require_file "${OUT}/cursor-native-attach.json"
require_file "${OUT}/tool-cursor.json"
require_file "${OUT}/workspace-context.json"
require_file "${OUT}/workspace-context-after-restart.json"
require_file "${OUT}/workspace-runtime-summary.json"
require_file "${OUT}/workspace-health.txt"
require_file "${OUT}/ssh-attach-identity.txt"
require_file "${OUT}/ssh-attach-context.env"
require_file "${OUT}/ssh-attach-context-packet.json"
require_file "${OUT}/smoke.json"
require_file "${OUT}/final-cluster-health.txt"
require_file "${OUT}/habitat/smoke.json"

jq -e '
  .cursor_remote_lane_source_present == 1 and
  .http_source_present == 1 and
  .workspace_deployment_present == 1 and
  .workspace_service_present == 1 and
  .ssh_dockerfile_present == 1 and
  .ssh_entrypoint_present == 1 and
  .contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '.status == "ok" and .restart_recovered_session == true' "${OUT}/habitat/smoke.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg ssh_user "${EXPECTED_SSH_USER}" '
  .status == "ok" and
  .phase == "B20.2a" and
  .lane.workstream_id == $workstream_id and
  .lane.workspace_id == $workspace_id and
  .lane.session_id == $session_id and
  .lane.connection_metadata.connection_mode == "same-workspace-remote-ssh" and
  .lane.connection_metadata.recommended_transport == "kubernetes-port-forward+ssh" and
  .lane.connection_metadata.ssh_transport_ready == true and
  .lane.connection_metadata.ssh_user == $ssh_user and
  .lane.connection_metadata.ssh_service_port == 2222 and
  .lane.connection_metadata.suggested_ssh_port_forward_command == "kubectl -n beagle port-forward service/beagle-workspace 18022:2222" and
  .lane.connection_metadata.suggested_ssh_command == "ssh -p 18022 openvscode-server@127.0.0.1"
' "${OUT}/cursor-remote-lane.json" >/dev/null

jq -e '.status == "ok" and .phase == "B20.2a"' "${OUT}/cursor-native-attach.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  '.tool.tool_id == "cursor" and
   .tool.remote_lane_kind == "cursor-remote-lane" and
   .tool.remote_lane_path == ("/api/darwin/workstreams/" + $workstream_id + "/cursor-remote-lane") and
   .tool.native_attach_path == ("/api/darwin/workstreams/" + $workstream_id + "/cursor-native-attach")' \
  "${OUT}/tool-cursor.json" >/dev/null

IFS=$'\t' read -r ssh_workstream ssh_workspace ssh_session < "${OUT}/ssh-attach-identity.txt"
[[ "${ssh_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || {
  echo "[FAIL] ssh attach workstream mismatch: ${ssh_workstream}" >&2
  exit 1
}
[[ "${ssh_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || {
  echo "[FAIL] ssh attach workspace mismatch: ${ssh_workspace}" >&2
  exit 1
}
[[ "${ssh_session}" == "${EXPECTED_SESSION_ID}" ]] || {
  echo "[FAIL] ssh attach session mismatch: ${ssh_session}" >&2
  exit 1
}

grep -q "BEAGLE_WORKSTREAM_ID='${EXPECTED_WORKSTREAM}'" "${OUT}/ssh-attach-context.env"
grep -q "BEAGLE_WORKSPACE_ID='${EXPECTED_WORKSPACE_ID}'" "${OUT}/ssh-attach-context.env"
grep -q "BEAGLE_SESSION_ID='${EXPECTED_SESSION_ID}'" "${OUT}/ssh-attach-context.env"
grep -q "BEAGLE_WORKSPACE_SSH_ENABLED='true'" "${OUT}/ssh-attach-context.env"
grep -q "BEAGLE_WORKSPACE_SSH_SERVICE_PORT='2222'" "${OUT}/ssh-attach-context.env"

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id
' "${OUT}/ssh-attach-context-packet.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.2a" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .connection_mode == "same-workspace-remote-ssh" and
  .recommended_transport == "kubernetes-port-forward+ssh" and
  .ssh_transport_ready == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] cursor native remote attach smoke artifacts validated"
