#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/role-aware-subagent-routing}"
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
  workspace-subagents.json \
  workspace-subagent-list.json \
  route-codex.json \
  route-claude-code.json \
  route-cursor.json \
  tool-cursor.json \
  tool-claude-code.json \
  tool-codex.json \
  workspace-context.json \
  workspace-context.env \
  workspace-health.txt \
  workspace-subagents-file.json \
  core.env \
  experiments.env \
  core-identity.txt \
  experiments-identity.txt \
  workspace-subagents-after-restart.json \
  workspace-subagent-list-after-restart.json \
  route-codex-after-restart.json \
  tool-cursor-after-restart.json \
  workspace-context-after-restart.json \
  workspace-context-after-restart.env \
  workspace-health-after-restart.txt \
  workspace-subagents-file-after-restart.json \
  core-after-restart.env \
  experiments-after-restart.env \
  core-identity-after-restart.txt \
  experiments-identity-after-restart.txt \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

EXPECTED_WORKSPACE_ID="$(jq -r '.subagents.workspace_id' "${OUT}/workspace-subagents.json")"
EXPECTED_SESSION_ID="$(jq -r '.subagents.session_id' "${OUT}/workspace-subagents.json")"
EXPECTED_ALIAS="${EXPECTED_WORKSPACE_ID}.coder"

jq -e '
  .routing_source_present == 1 and
  .subagents_source_present == 1 and
  .cockpit_source_present == 1 and
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
  .subagents.stable_attach_alias == $alias and
  (.subagents.roles | length) == 2 and
  any(.subagents.roles[]; .subagent_id == "core" and .role_tag == "core-runtime" and (.recommended_work_modes | index("implementation")) != null and (.default_tools | index("codex")) != null) and
  any(.subagents.roles[]; .subagent_id == "experiments" and .role_tag == "experiments-analysis" and (.recommended_work_modes | index("analysis")) != null and (.default_tools | index("claude-code")) != null)
' "${OUT}/workspace-subagents.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.8" and
  .list.workstream_id == $workstream_id and
  .list.workspace_id == $workspace_id and
  .list.session_id == $session_id and
  .list.workspace_subagent_list_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-subagent-list") and
  .list.workspace_subagent_route_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-subagent-route") and
  (.list.roles | length) == 2
' "${OUT}/workspace-subagent-list.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.8" and
  .route.workstream_id == $workstream_id and
  .route.workspace_id == $workspace_id and
  .route.session_id == $session_id and
  .route.selection.requested_tool_id == "codex" and
  .route.selection.requested_work_mode == "implementation" and
  .route.selection.selected_subagent_id == "core" and
  .route.selection.selected_role_tag == "core-runtime" and
  .route.selection.selection_source == "work-mode" and
  .route.attach_metadata.workspace_folder == "/workspace/beagle" and
  .route.attach_metadata.env_file == "/workspace/beagle/.beagle/context/subagents/core.env" and
  .route.attach_metadata.devcontainer_config_file == "/workspace/beagle/.devcontainer/beagle-core/devcontainer.json"
' "${OUT}/route-codex.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.8" and
  .route.workstream_id == $workstream_id and
  .route.workspace_id == $workspace_id and
  .route.session_id == $session_id and
  .route.selection.requested_tool_id == "claude-code" and
  .route.selection.requested_work_mode == "analysis" and
  .route.selection.selected_subagent_id == "experiments" and
  .route.selection.selected_role_tag == "experiments-analysis" and
  .route.attach_metadata.workspace_folder == "/workspace/beagle/crates/beagle-experiments" and
  .route.attach_metadata.env_file == "/workspace/beagle/.beagle/context/subagents/experiments.env"
' "${OUT}/route-claude-code.json" >/dev/null

jq -e '
  .route.selection.requested_tool_id == "cursor" and
  .route.selection.requested_work_mode == "interactive-editing" and
  .route.selection.selected_subagent_id == "core"
' "${OUT}/route-cursor.json" >/dev/null

jq -e \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .tool.tool_id == "cursor" and
  .tool.workspace_id == $workspace_id and
  .tool.session_id == $session_id and
  .tool.workspace_subagent_list_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-list" and
  .tool.workspace_subagent_route_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=cursor&work_mode=interactive-editing" and
  .tool.recommended_subagent_id == "core" and
  .tool.recommended_work_mode == "interactive-editing"
' "${OUT}/tool-cursor.json" >/dev/null

jq -e '
  .tool.tool_id == "claude-code" and
  .tool.recommended_subagent_id == "experiments" and
  .tool.recommended_work_mode == "analysis" and
  .tool.workspace_subagent_route_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=claude-code&work_mode=analysis"
' "${OUT}/tool-claude-code.json" >/dev/null

jq -e '
  .tool.tool_id == "codex" and
  .tool.recommended_subagent_id == "core" and
  .tool.recommended_work_mode == "implementation" and
  .tool.workspace_subagent_route_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=codex&work_mode=implementation"
' "${OUT}/tool-codex.json" >/dev/null

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

grep -q "BEAGLE_SUBAGENT_ROLE_TAG='core-runtime'" "${OUT}/core.env"
grep -q "BEAGLE_SUBAGENT_WORK_MODES='core,runtime,implementation,control-plane,governance,interactive-editing'" "${OUT}/core.env"
grep -q "BEAGLE_SUBAGENT_DEFAULT_TOOLS='cursor,codex'" "${OUT}/core.env"
grep -q "BEAGLE_SUBAGENT_ROLE_TAG='experiments-analysis'" "${OUT}/experiments.env"
grep -q "BEAGLE_SUBAGENT_WORK_MODES='experiments,analysis,evaluation,evidence,manuscript,paper'" "${OUT}/experiments.env"
grep -q "BEAGLE_SUBAGENT_DEFAULT_TOOLS='claude-code'" "${OUT}/experiments.env"
grep -q "vscode-workbench-web-configuration" "${OUT}/workspace-health.txt"
grep -q "vscode-workbench-web-configuration" "${OUT}/workspace-health-after-restart.txt"

jq -e '
  .phase == "B20.7" and
  (.roles | length) == 2 and
  any(.roles[]; .subagent_id == "core" and .role_tag == "core-runtime") and
  any(.roles[]; .subagent_id == "experiments" and .role_tag == "experiments-analysis")
' "${OUT}/workspace-subagents-file-after-restart.json" >/dev/null

IFS=$'\t' read -r core_workstream core_workspace core_session core_role core_tag core_folder < "${OUT}/core-identity-after-restart.txt"
[[ "${core_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || { echo "[FAIL] core workstream mismatch: ${core_workstream}" >&2; exit 1; }
[[ "${core_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || { echo "[FAIL] core workspace mismatch: ${core_workspace}" >&2; exit 1; }
[[ "${core_session}" == "${EXPECTED_SESSION_ID}" ]] || { echo "[FAIL] core session mismatch: ${core_session}" >&2; exit 1; }
[[ "${core_role}" == "core" ]] || { echo "[FAIL] core role mismatch: ${core_role}" >&2; exit 1; }
[[ "${core_tag}" == "core-runtime" ]] || { echo "[FAIL] core tag mismatch: ${core_tag}" >&2; exit 1; }
[[ "${core_folder}" == "/workspace/beagle" ]] || { echo "[FAIL] core folder mismatch: ${core_folder}" >&2; exit 1; }

IFS=$'\t' read -r exp_workstream exp_workspace exp_session exp_role exp_tag exp_folder < "${OUT}/experiments-identity-after-restart.txt"
[[ "${exp_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || { echo "[FAIL] experiments workstream mismatch: ${exp_workstream}" >&2; exit 1; }
[[ "${exp_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || { echo "[FAIL] experiments workspace mismatch: ${exp_workspace}" >&2; exit 1; }
[[ "${exp_session}" == "${EXPECTED_SESSION_ID}" ]] || { echo "[FAIL] experiments session mismatch: ${exp_session}" >&2; exit 1; }
[[ "${exp_role}" == "experiments" ]] || { echo "[FAIL] experiments role mismatch: ${exp_role}" >&2; exit 1; }
[[ "${exp_tag}" == "experiments-analysis" ]] || { echo "[FAIL] experiments tag mismatch: ${exp_tag}" >&2; exit 1; }
[[ "${exp_folder}" == "/workspace/beagle/crates/beagle-experiments" ]] || { echo "[FAIL] experiments folder mismatch: ${exp_folder}" >&2; exit 1; }

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok" and
  .phase == "B20.8" and
  .list.workstream_id == $workstream_id and
  .list.workspace_id == $workspace_id and
  .list.session_id == $session_id and
  (.list.roles | length) == 2
' "${OUT}/workspace-subagent-list-after-restart.json" >/dev/null

jq -e '
  .route.selection.selected_subagent_id == "core" and
  .route.selection.selected_role_tag == "core-runtime"
' "${OUT}/route-codex-after-restart.json" >/dev/null

jq -e '
  .tool.tool_id == "cursor" and
  .tool.recommended_subagent_id == "core" and
  .tool.recommended_work_mode == "interactive-editing"
' "${OUT}/tool-cursor-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" '
  .status == "ok" and
  .phase == "B20.8" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .codex_selected_subagent == "core" and
  .claude_selected_subagent == "experiments" and
  .cursor_selected_subagent == "core" and
  .tool_cursor_subagent == "core" and
  .tool_claude_subagent == "experiments" and
  .tool_codex_subagent == "core" and
  .managed_attach_state == "coder-compatible-ready" and
  .attach_host_alias == $alias and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] role-aware subagent routing smoke artifacts validated"
