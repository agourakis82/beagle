#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/operator-friendly-attach-plane}"
HABITAT_OUT="${OUT}/habitat"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
BASE_VALIDATOR="${BASE_VALIDATOR:-/home/devsounio/beagle/scripts/infrastructure/darwin-hpc/validate_cluster_workspace_habitat_smoke.sh}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

require_file "${BASE_VALIDATOR}"

OUT="${HABITAT_OUT}" "${BASE_VALIDATOR}"

for file in \
  source-summary.json \
  workspace-context.json \
  workspace-context-after-restart.json \
  workspace-runtime-summary.json \
  workspace-health.txt \
  tool-cursor.json \
  workspace-attach.json \
  attach-helper-summary.json \
  attach-ssh-config \
  attach-identity.txt \
  attach-context.env \
  attach-context-packet.json \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

EXPECTED_WORKSPACE_ID="$(jq -r '.habitat.workspace_id' "${OUT}/workspace-context.json")"
EXPECTED_SESSION_ID="$(jq -r '.habitat.session_id' "${OUT}/workspace-context.json")"

jq -e '
  .workspace_attach_source_present == 1 and
  .workspace_habitat_source_present == 1 and
  .http_source_present == 1 and
  .helper_present == 1 and
  .contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.3" and
  .attach.workstream_id == $workstream_id and
  .attach.workspace_id == $workspace_id and
  .attach.session_id == $session_id and
  .attach.attach_metadata.recommended_client == "cursor" and
  .attach.attach_metadata.attach_method == "helper-managed-native-remote-ssh" and
  .attach.attach_metadata.attach_plane_kind == "operator-friendly-cluster-internal" and
  .attach.attach_metadata.stable_attach_host_alias == $workspace_id and
  .attach.attach_metadata.ssh_user == "openvscode-server" and
  .attach.attach_metadata.ssh_service_port == 2222 and
  .attach.attach_metadata.repo_root == "/workspace/beagle" and
  .attach.helper_snippets.helper_command == ("scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh --workstream " + $workstream_id + " --client cursor") and
  .attach.helper_snippets.browser_helper_command == ("scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh --workstream " + $workstream_id + " --client browser") and
  .attach.helper_snippets.ssh_helper_command == ("scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh --workstream " + $workstream_id + " --client ssh") and
  (.attach.helper_snippets.ssh_config_snippet | contains("Host " + $workspace_id)) and
  (.attach.helper_snippets.cursor_remote_hint | contains("Cursor Remote-SSH")) and
  .lane.workstream_id == $workstream_id and
  .lane.workspace_id == $workspace_id and
  .lane.session_id == $session_id and
  .habitat.workstream_id == $workstream_id and
  .habitat.workspace_id == $workspace_id and
  .habitat.session_id == $session_id and
  .context_packet.workstream_id == $workstream_id and
  .context_packet.workspace_id == $workspace_id and
  .context_packet.session_id == $session_id
' "${OUT}/workspace-attach.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.3" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .client == "cursor" and
  .attach_host_alias == $workspace_id and
  .attach_method == "helper-managed-native-remote-ssh" and
  (.ssh_config_path | endswith("/ssh_config")) and
  (.ssh_command | contains("ssh -F")) and
  (.helper_command | contains("--client cursor"))
' "${OUT}/attach-helper-summary.json" >/dev/null

grep -Fq "Host ${EXPECTED_WORKSPACE_ID}" "${OUT}/attach-ssh-config"
grep -Fq "HostName 127.0.0.1" "${OUT}/attach-ssh-config"
grep -Fq "User openvscode-server" "${OUT}/attach-ssh-config"
grep -Fq "Port " "${OUT}/attach-ssh-config"

IFS=$'\t' read -r attach_workstream attach_workspace attach_session < "${OUT}/attach-identity.txt"
[[ "${attach_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || {
  echo "[FAIL] attach workstream mismatch: ${attach_workstream}" >&2
  exit 1
}
[[ "${attach_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || {
  echo "[FAIL] attach workspace mismatch: ${attach_workspace}" >&2
  exit 1
}
[[ "${attach_session}" == "${EXPECTED_SESSION_ID}" ]] || {
  echo "[FAIL] attach session mismatch: ${attach_session}" >&2
  exit 1
}

grep -Fq "export BEAGLE_WORKSTREAM_ID='${EXPECTED_WORKSTREAM}'" "${OUT}/attach-context.env"
grep -Fq "export BEAGLE_WORKSPACE_ID='${EXPECTED_WORKSPACE_ID}'" "${OUT}/attach-context.env"
grep -Fq "export BEAGLE_SESSION_ID='${EXPECTED_SESSION_ID}'" "${OUT}/attach-context.env"
grep -Fq "export BEAGLE_WORKSPACE_ATTACH_PATH='/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-attach'" "${OUT}/attach-context.env"
grep -Fq "export BEAGLE_WORKSPACE_ATTACH_HELPER='/workspace/beagle/scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh'" "${OUT}/attach-context.env"

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .packet.workstream_id == $workstream_id and
  .packet.workspace_id == $workspace_id and
  .packet.session_id == $session_id
' "${OUT}/attach-context-packet.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.3" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .recommended_client == "cursor" and
  .attach_method == "helper-managed-native-remote-ssh" and
  .attach_host_alias == $workspace_id and
  .helper_managed_attach_ready == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] operator-friendly attach plane smoke artifacts validated"
