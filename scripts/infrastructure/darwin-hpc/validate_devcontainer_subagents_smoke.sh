#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/devcontainer-subagents}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for file in \
  source-summary.json \
  workspace-context.json \
  workspace-context.env \
  workspace-context-after-restart.json \
  workspace-context-after-restart.env \
  workspace-health.txt \
  workspace-health-after-restart.txt \
  tool-cursor.json \
  tool-cursor-after-restart.json \
  workspace-subagents.json \
  workspace-subagents-after-restart.json \
  workspace-subagents-file.json \
  workspace-subagents-file-after-restart.json \
  core.env \
  experiments.env \
  core-after-restart.env \
  experiments-after-restart.env \
  core-devcontainer.json \
  experiments-devcontainer.json \
  core-devcontainer-after-restart.json \
  experiments-devcontainer-after-restart.json \
  core-identity.txt \
  experiments-identity.txt \
  core-identity-after-restart.txt \
  experiments-identity-after-restart.txt \
  core-sentinel-after-restart.txt \
  experiments-sentinel-after-restart.txt \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

EXPECTED_WORKSPACE_ID="$(jq -r '.subagents.workspace_id' "${OUT}/workspace-subagents.json")"
EXPECTED_SESSION_ID="$(jq -r '.subagents.session_id' "${OUT}/workspace-subagents.json")"
EXPECTED_ALIAS="${EXPECTED_WORKSPACE_ID}.coder"

jq -e '
  .subagents_source_present == 1 and
  .workspace_habitat_source_present == 1 and
  .http_source_present == 1 and
  .k8s_template_present == 1 and
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
  .phase == "B20.7" and
  .subagents.workstream_id == $workstream_id and
  .subagents.workspace_id == $workspace_id and
  .subagents.session_id == $session_id and
  .subagents.workspace_subagents_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-subagents") and
  .subagents.subagents_file == "/workspace/beagle/.beagle/context/workspace-subagents.json" and
  .subagents.subagents_dir == "/workspace/beagle/.beagle/context/subagents" and
  .subagents.devcontainer_dir == "/workspace/beagle/.devcontainer" and
  .subagents.attach_method == "managed-coder-compatible-remote-ssh" and
  .subagents.managed_attach_state == "coder-compatible-ready" and
  .subagents.stable_attach_alias == $alias and
  .subagents.browser_fallback_ready == true and
  .subagents.cursor_managed_attach_ready == true and
  (.subagents.roles | length) == 2 and
  any(.subagents.roles[]; .subagent_id == "core" and .access_state == "live" and .env_file == "/workspace/beagle/.beagle/context/subagents/core.env" and .devcontainer_config_file == "/workspace/beagle/.devcontainer/beagle-core/devcontainer.json" and .workspace_folder == "/workspace/beagle") and
  any(.subagents.roles[]; .subagent_id == "experiments" and .access_state == "live" and .env_file == "/workspace/beagle/.beagle/context/subagents/experiments.env" and .devcontainer_config_file == "/workspace/beagle/.devcontainer/beagle-experiments/devcontainer.json" and .workspace_folder == "/workspace/beagle/crates/beagle-experiments") and
  .template.workspace_id == $workspace_id and
  .launch.session_id == $session_id and
  .habitat.workstream_id == $workstream_id and
  .context_packet.workstream_id == $workstream_id
' "${OUT}/workspace-subagents.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" '
  .status == "ok" and
  .phase == "B20.7" and
  .subagents.workstream_id == $workstream_id and
  .subagents.workspace_id == $workspace_id and
  .subagents.session_id == $session_id and
  .subagents.attach_method == "managed-coder-compatible-remote-ssh" and
  .subagents.managed_attach_state == "coder-compatible-ready" and
  .subagents.stable_attach_alias == $alias and
  (.subagents.roles | length) == 2
' "${OUT}/workspace-subagents-after-restart.json" >/dev/null

jq -e '
  .phase == "B20.7" and
  .subagents_kind == "workspace-subagents" and
  .subagents_version == "beagle-workspace-devcontainer-subagents-v1" and
  (.roles | length) == 2
' "${OUT}/workspace-subagents-file-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .packet.workstream_id == $workstream_id and
  .packet.workspace_id == $workspace_id and
  .packet.session_id == $session_id
' "${OUT}/workspace-context.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .packet.workstream_id == $workstream_id and
  .packet.workspace_id == $workspace_id and
  .packet.session_id == $session_id
' "${OUT}/workspace-context-after-restart.json" >/dev/null
grep -q "BEAGLE_WORKSTREAM_ID='${EXPECTED_WORKSTREAM}'" "${OUT}/workspace-context.env"
grep -q "BEAGLE_SESSION_ID='${EXPECTED_SESSION_ID}'" "${OUT}/workspace-context-after-restart.env"

grep -q "vscode-workbench-web-configuration" "${OUT}/workspace-health.txt"
grep -q "vscode-workbench-web-configuration" "${OUT}/workspace-health-after-restart.txt"

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .lane.lane_kind == "cursor-remote-lane" and
  .lane.workstream_id == $workstream_id and
  .lane.workspace_id == $workspace_id and
  .lane.session_id == $session_id and
  .habitat.workstream_id == $workstream_id and
  .habitat.workspace_id == $workspace_id and
  .habitat.session_id == $session_id and
  .context_packet.workstream_id == $workstream_id and
  .context_packet.workspace_id == $workspace_id and
  .context_packet.session_id == $session_id
' "${OUT}/tool-cursor-after-restart.json" >/dev/null

grep -q "BEAGLE_SUBAGENT_ROLE='core'" "${OUT}/core.env"
grep -q "BEAGLE_WORKSTREAM_ID='${EXPECTED_WORKSTREAM}'" "${OUT}/core.env"
grep -q "BEAGLE_WORKSPACE_ID='${EXPECTED_WORKSPACE_ID}'" "${OUT}/core.env"
grep -q "BEAGLE_SUBAGENT_ROLE='experiments'" "${OUT}/experiments.env"
grep -q "BEAGLE_SESSION_ID='${EXPECTED_SESSION_ID}'" "${OUT}/experiments.env"

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .name == "beagle-core" and
  .workspaceFolder == "/workspace/beagle" and
  .remoteEnv.BEAGLE_WORKSTREAM_ID == $workstream_id and
  .remoteEnv.BEAGLE_WORKSPACE_ID == $workspace_id and
  .remoteEnv.BEAGLE_SESSION_ID == $session_id and
  .remoteEnv.BEAGLE_SUBAGENT_ROLE == "core"
' "${OUT}/core-devcontainer-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .name == "beagle-experiments" and
  .workspaceFolder == "/workspace/beagle/crates/beagle-experiments" and
  .remoteEnv.BEAGLE_WORKSTREAM_ID == $workstream_id and
  .remoteEnv.BEAGLE_WORKSPACE_ID == $workspace_id and
  .remoteEnv.BEAGLE_SESSION_ID == $session_id and
  .remoteEnv.BEAGLE_SUBAGENT_ROLE == "experiments"
' "${OUT}/experiments-devcontainer-after-restart.json" >/dev/null

IFS=$'\t' read -r core_workstream core_workspace core_session core_role core_folder < "${OUT}/core-identity-after-restart.txt"
[[ "${core_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || { echo "[FAIL] core workstream mismatch: ${core_workstream}" >&2; exit 1; }
[[ "${core_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || { echo "[FAIL] core workspace mismatch: ${core_workspace}" >&2; exit 1; }
[[ "${core_session}" == "${EXPECTED_SESSION_ID}" ]] || { echo "[FAIL] core session mismatch: ${core_session}" >&2; exit 1; }
[[ "${core_role}" == "core" ]] || { echo "[FAIL] core role mismatch: ${core_role}" >&2; exit 1; }
[[ "${core_folder}" == "/workspace/beagle" ]] || { echo "[FAIL] core folder mismatch: ${core_folder}" >&2; exit 1; }

IFS=$'\t' read -r exp_workstream exp_workspace exp_session exp_role exp_folder < "${OUT}/experiments-identity-after-restart.txt"
[[ "${exp_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || { echo "[FAIL] experiments workstream mismatch: ${exp_workstream}" >&2; exit 1; }
[[ "${exp_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || { echo "[FAIL] experiments workspace mismatch: ${exp_workspace}" >&2; exit 1; }
[[ "${exp_session}" == "${EXPECTED_SESSION_ID}" ]] || { echo "[FAIL] experiments session mismatch: ${exp_session}" >&2; exit 1; }
[[ "${exp_role}" == "experiments" ]] || { echo "[FAIL] experiments role mismatch: ${exp_role}" >&2; exit 1; }
[[ "${exp_folder}" == "/workspace/beagle/crates/beagle-experiments" ]] || { echo "[FAIL] experiments folder mismatch: ${exp_folder}" >&2; exit 1; }

IFS=$'\t' read -r core_s_workstream core_s_workspace core_s_session core_s_mode < "${OUT}/core-sentinel-after-restart.txt"
[[ "${core_s_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || { echo "[FAIL] core sentinel workstream mismatch: ${core_s_workstream}" >&2; exit 1; }
[[ "${core_s_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || { echo "[FAIL] core sentinel workspace mismatch: ${core_s_workspace}" >&2; exit 1; }
[[ "${core_s_session}" == "${EXPECTED_SESSION_ID}" ]] || { echo "[FAIL] core sentinel session mismatch: ${core_s_session}" >&2; exit 1; }
[[ "${core_s_mode}" == "core-live" ]] || { echo "[FAIL] core sentinel mode mismatch: ${core_s_mode}" >&2; exit 1; }

IFS=$'\t' read -r exp_s_workstream exp_s_workspace exp_s_session exp_s_mode < "${OUT}/experiments-sentinel-after-restart.txt"
[[ "${exp_s_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || { echo "[FAIL] experiments sentinel workstream mismatch: ${exp_s_workstream}" >&2; exit 1; }
[[ "${exp_s_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || { echo "[FAIL] experiments sentinel workspace mismatch: ${exp_s_workspace}" >&2; exit 1; }
[[ "${exp_s_session}" == "${EXPECTED_SESSION_ID}" ]] || { echo "[FAIL] experiments sentinel session mismatch: ${exp_s_session}" >&2; exit 1; }
[[ "${exp_s_mode}" == "experiments-live" ]] || { echo "[FAIL] experiments sentinel mode mismatch: ${exp_s_mode}" >&2; exit 1; }

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" '
  .status == "ok" and
  .phase == "B20.7" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .subagent_count == 2 and
  .core_access_state == "live" and
  .experiments_access_state == "live" and
  .managed_attach_state == "coder-compatible-ready" and
  .attach_host_alias == $alias and
  .core_workspace_folder == "/workspace/beagle" and
  .experiments_workspace_folder == "/workspace/beagle/crates/beagle-experiments" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] devcontainer subagents smoke artifacts validated"
