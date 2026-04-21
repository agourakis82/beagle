#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/cross-subagent-session-handoff}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require jq
require grep

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/workspace-subagent-list.json" \
  "${OUT}/subagent-handoff-request.json" \
  "${OUT}/workspace-subagent-handoff-post.json" \
  "${OUT}/workspace-subagent-handoff.json" \
  "${OUT}/workspace-subagent-handoff-after-restart.json" \
  "${OUT}/tool-claude-code.json" \
  "${OUT}/workspace-context.json" \
  "${OUT}/workspace-context-after-restart.json" \
  "${OUT}/workspace-context.env" \
  "${OUT}/experiments.env" \
  "${OUT}/core-identity.txt" \
  "${OUT}/experiments-identity.txt" \
  "${OUT}/core-identity-after-restart.txt" \
  "${OUT}/experiments-identity-after-restart.txt" \
  "${OUT}/workspace-health.txt" \
  "${OUT}/workspace-health-after-restart.txt" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing artifact: ${path}" >&2
    exit 1
  }
done

jq -e '
  .handoff_source_present == 1 and
  .routing_source_present == 1 and
  .subagents_source_present == 1 and
  .cockpit_source_present == 1 and
  .http_source_present == 1 and
  .contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B20.8" and
  .subagents.workspace_subagent_handoff_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff" and
  (.subagents.roles | length) == 2 and
  any(.subagents.roles[]; .subagent_id == "core" and .role_tag == "core-runtime") and
  any(.subagents.roles[]; .subagent_id == "experiments" and .role_tag == "experiments-analysis")
' "${OUT}/workspace-subagent-list.json" >/dev/null

jq -e '
  .phase == "B20.9" and
  .handoff.workstream_id == "beagle-darwin-hpc-governance" and
  .handoff.workspace_id == "beagle-cluster-pilot" and
  .handoff.session_id == "ws-cluster-workspace-habitat" and
  .handoff.source_subagent_id == "core" and
  .handoff.target_subagent_id == "experiments" and
  .handoff.intent == "analysis" and
  .target_route.selection.selected_subagent_id == "experiments" and
  .target_route.selection.selected_role_tag == "experiments-analysis" and
  .propagation.handoff_present == true and
  .propagation.target_env_file == "/workspace/beagle/.beagle/context/subagents/experiments.env" and
  .propagation.target_workspace_folder == "/workspace/beagle/crates/beagle-experiments" and
  .context_packet.handoff.last_handoff == .handoff.handoff_text and
  .context_packet.last_result.available == true and
  .handoff.managed_attach_state == "coder-compatible-ready" and
  .handoff.stable_attach_alias == "beagle-cluster-pilot.coder"
' "${OUT}/workspace-subagent-handoff-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-subagent-handoff-post.json" '
  .handoff.handoff_id == $post[0].handoff.handoff_id and
  .handoff.source_subagent_id == "core" and
  .handoff.target_subagent_id == "experiments" and
  .context_packet.handoff.last_handoff == .handoff.handoff_text
' "${OUT}/workspace-subagent-handoff.json" >/dev/null

jq -e '
  .tool.recommended_subagent_id == "experiments" and
  .tool.recommended_work_mode == "analysis" and
  .tool.workspace_subagent_handoff_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff"
' "${OUT}/tool-claude-code.json" >/dev/null

grep -q "BEAGLE_SUBAGENT_ROLE_TAG='experiments-analysis'" "${OUT}/experiments.env"
grep -q "BEAGLE_SUBAGENT_WORK_MODES='experiments,analysis,evaluation,evidence,manuscript,paper'" "${OUT}/experiments.env"
grep -q "BEAGLE_SUBAGENT_DEFAULT_TOOLS='claude-code'" "${OUT}/experiments.env"

IFS=$'\t' read -r core_workstream core_workspace core_session core_subagent core_role_tag core_pwd < "${OUT}/core-identity.txt"
[[ "${core_workstream}" == "beagle-darwin-hpc-governance" ]]
[[ "${core_workspace}" == "beagle-cluster-pilot" ]]
[[ "${core_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${core_subagent}" == "core" ]]
[[ "${core_role_tag}" == "core-runtime" ]]
[[ "${core_pwd}" == "/workspace/beagle" ]]

IFS=$'\t' read -r exp_workstream exp_workspace exp_session exp_subagent exp_role_tag exp_pwd < "${OUT}/experiments-identity.txt"
[[ "${exp_workstream}" == "beagle-darwin-hpc-governance" ]]
[[ "${exp_workspace}" == "beagle-cluster-pilot" ]]
[[ "${exp_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${exp_subagent}" == "experiments" ]]
[[ "${exp_role_tag}" == "experiments-analysis" ]]
[[ "${exp_pwd}" == "/workspace/beagle/crates/beagle-experiments" ]]

IFS=$'\t' read -r _ _ restart_session restart_subagent restart_role_tag restart_pwd < "${OUT}/experiments-identity-after-restart.txt"
[[ "${restart_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${restart_subagent}" == "experiments" ]]
[[ "${restart_role_tag}" == "experiments-analysis" ]]
[[ "${restart_pwd}" == "/workspace/beagle/crates/beagle-experiments" ]]

jq -e --slurpfile post "${OUT}/workspace-subagent-handoff-post.json" '
  .handoff.handoff_id == $post[0].handoff.handoff_id and
  .handoff.session_id == $post[0].handoff.session_id and
  .handoff.target_subagent_id == "experiments" and
  .target_route.selection.selected_subagent_id == "experiments" and
  .context_packet.handoff.last_handoff == .handoff.handoff_text
' "${OUT}/workspace-subagent-handoff-after-restart.json" >/dev/null

jq -e '
  .phase == "B20.9" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "core" and
  .target_subagent_id == "experiments" and
  .target_selected_subagent == "experiments" and
  .managed_attach_state == "coder-compatible-ready" and
  .stable_attach_alias == "beagle-cluster-pilot.coder" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "deployment.apps/beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core.*1/1" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace.*1/1" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary).*UP" "${OUT}/final-cluster-health.txt"

echo "[OK] cross-subagent session handoff smoke artifacts validated"
