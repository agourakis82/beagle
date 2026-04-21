#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/managed-workspace-launch-resume}"
BASE_OUT="${OUT}/managed-attach-plane"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
BASE_VALIDATOR="${BASE_VALIDATOR:-/home/devsounio/beagle/scripts/infrastructure/darwin-hpc/validate_managed_attach_plane_smoke.sh}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

require_file "${BASE_VALIDATOR}"

OUT="${BASE_OUT}" bash "${BASE_VALIDATOR}"

for file in \
  source-summary.json \
  workspace-context.json \
  workspace-context-after-restart.json \
  workspace-runtime-summary.json \
  workspace-health.txt \
  tool-cursor.json \
  workspace-launch-resume.json \
  launch-summary.json \
  launch-identity.txt \
  launch-context.env \
  launch-context-packet.json \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

EXPECTED_WORKSPACE_ID="$(jq -r '.habitat.workspace_id' "${OUT}/workspace-context.json")"
EXPECTED_SESSION_ID="$(jq -r '.habitat.session_id' "${OUT}/workspace-context.json")"
EXPECTED_ALIAS="${EXPECTED_WORKSPACE_ID}.coder"

jq -e '
  .launch_source_present == 1 and
  .workspace_habitat_source_present == 1 and
  .cockpit_source_present == 1 and
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
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" '
  .status == "ok" and
  .phase == "B20.5" and
  .launch.workstream_id == $workstream_id and
  .launch.workspace_id == $workspace_id and
  .launch.session_id == $session_id and
  .launch.workspace_launch_resume_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-launch-resume") and
  .launch.managed_attach_path == ("/api/darwin/workstreams/" + $workstream_id + "/managed-attach") and
  .launch.cursor_remote_lane_path == ("/api/darwin/workstreams/" + $workstream_id + "/cursor-remote-lane") and
  .launch.cursor_native_attach_path == ("/api/darwin/workstreams/" + $workstream_id + "/cursor-native-attach") and
  .launch.launch_metadata.recommended_client == "cursor" and
  .launch.launch_metadata.launch_method == "tool-dock-managed-workspace-launch-resume" and
  .launch.launch_metadata.launch_state == "resume-ready" and
  .launch.launch_metadata.attach_method == "managed-coder-compatible-remote-ssh" and
  .launch.launch_metadata.managed_attach_state == "coder-compatible-ready" and
  .launch.launch_metadata.browser_fallback_ready == true and
  .launch.launch_metadata.cursor_managed_attach_ready == true and
  .launch.launch_metadata.stable_launch_alias == $alias and
  .launch.launch_metadata.attach_transport == "managed-kubernetes-port-forward+ssh" and
  .launch.launch_metadata.workspace_habitat_env_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-habitat/context.env") and
  .launch.launch_metadata.launch_state_dir == "~/.beagle/managed-attach/beagle-darwin-hpc-governance" and
  .launch.launch_metadata.handoff_ref == ("/api/darwin/workstreams/" + $workstream_id + "/handoff") and
  .launch.launch_metadata.context_packet_ref == ("/api/darwin/workstreams/" + $workstream_id + "/context-packet") and
  .launch.launch_metadata.attach_snippet_ref == "~/.beagle/managed-attach/beagle-darwin-hpc-governance/ssh_config" and
  .launch.launch_metadata.launch_helper_ref == "scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh" and
  .launch.helper_snippets.helper_script_repo_relative_path == "scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh" and
  .launch.helper_snippets.cursor_resume_command == ("scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh --workstream " + $workstream_id + " --client cursor") and
  .launch.helper_snippets.browser_resume_command == ("scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh --workstream " + $workstream_id + " --client browser") and
  .launch.helper_snippets.ssh_resume_command == ("scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh --workstream " + $workstream_id + " --client ssh") and
  .managed_attach.attach_metadata.attach_method == "managed-coder-compatible-remote-ssh" and
  .managed_attach.attach_metadata.managed_attach_state == "coder-compatible-ready" and
  .habitat.workstream_id == $workstream_id and
  .habitat.workspace_id == $workspace_id and
  .habitat.session_id == $session_id and
  .context_packet.workstream_id == $workstream_id and
  .context_packet.workspace_id == $workspace_id and
  .context_packet.session_id == $session_id
' "${OUT}/workspace-launch-resume.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" '
  .status == "ok" and
  .phase == "B20.5" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .client == "cursor" and
  .launch_method == "tool-dock-managed-workspace-launch-resume" and
  .launch_state == "resume-ready" and
  .attach_method == "managed-coder-compatible-remote-ssh" and
  .managed_attach_state == "coder-compatible-ready" and
  .attach_host_alias == $alias and
  .recommended_client == "cursor" and
  .browser_fallback_ready == true and
  .cursor_resume_ready == true and
  (.helper_command | contains("launch_managed_workspace_session.sh")) and
  (.ssh_command | contains("ssh -F"))
' "${OUT}/launch-summary.json" >/dev/null

IFS=$'\t' read -r launch_workstream launch_workspace launch_session < "${OUT}/launch-identity.txt"
[[ "${launch_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || {
  echo "[FAIL] launch workstream mismatch: ${launch_workstream}" >&2
  exit 1
}
[[ "${launch_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || {
  echo "[FAIL] launch workspace mismatch: ${launch_workspace}" >&2
  exit 1
}
[[ "${launch_session}" == "${EXPECTED_SESSION_ID}" ]] || {
  echo "[FAIL] launch session mismatch: ${launch_session}" >&2
  exit 1
}

grep -Fq "export BEAGLE_WORKSTREAM_ID='${EXPECTED_WORKSTREAM}'" "${OUT}/launch-context.env"
grep -Fq "export BEAGLE_WORKSPACE_ID='${EXPECTED_WORKSPACE_ID}'" "${OUT}/launch-context.env"
grep -Fq "export BEAGLE_SESSION_ID='${EXPECTED_SESSION_ID}'" "${OUT}/launch-context.env"
grep -Fq "export BEAGLE_MANAGED_ATTACH_PATH='/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/managed-attach'" "${OUT}/launch-context.env"
grep -Fq "export BEAGLE_WORKSPACE_LAUNCH_RESUME_PATH='/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-launch-resume'" "${OUT}/launch-context.env"
grep -Fq "export BEAGLE_WORKSPACE_LAUNCH_RESUME_HELPER='/workspace/beagle/scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh'" "${OUT}/launch-context.env"

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .packet.workstream_id == $workstream_id and
  .packet.workspace_id == $workspace_id and
  .packet.session_id == $session_id
' "${OUT}/launch-context-packet.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" '
  .status == "ok" and
  .phase == "B20.5" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .recommended_client == "cursor" and
  .launch_method == "tool-dock-managed-workspace-launch-resume" and
  .launch_state == "resume-ready" and
  .managed_attach_state == "coder-compatible-ready" and
  .attach_host_alias == $alias and
  .cursor_resume_ready == true and
  .browser_fallback_ready == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" '
  .tool.tool_id == "cursor" and
  .tool.managed_attach_path == ("/api/darwin/workstreams/" + $workstream_id + "/managed-attach") and
  .tool.workspace_launch_resume_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-launch-resume")
' "${OUT}/tool-cursor.json" >/dev/null

grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] managed workspace launch/resume smoke artifacts validated"
