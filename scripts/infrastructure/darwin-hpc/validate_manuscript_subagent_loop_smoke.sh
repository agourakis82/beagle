#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-subagent-loop}"

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
  "${OUT}/route-manuscript.json" \
  "${OUT}/subagent-handoff-request.json" \
  "${OUT}/handoff-core-to-experiments.json" \
  "${OUT}/manuscript-handoff-request.json" \
  "${OUT}/workspace-manuscript-handoff-post.json" \
  "${OUT}/workspace-manuscript-handoff.json" \
  "${OUT}/campaign-context-packet.json" \
  "${OUT}/campaign-evidence-pack.json" \
  "${OUT}/campaign-claims.json" \
  "${OUT}/campaign-manuscript-pack.json" \
  "${OUT}/workspace-context.json" \
  "${OUT}/workspace-context-after-restart.json" \
  "${OUT}/workspace-context.env" \
  "${OUT}/experiments.env" \
  "${OUT}/manuscript.env" \
  "${OUT}/core-identity.txt" \
  "${OUT}/experiments-identity.txt" \
  "${OUT}/manuscript-identity.txt" \
  "${OUT}/experiments-identity-after-restart.txt" \
  "${OUT}/manuscript-identity-after-restart.txt" \
  "${OUT}/workspace-manuscript-handoff-after-restart.json" \
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
  .manuscript_source_present == 1 and
  .handoff_source_present == 1 and
  .routing_source_present == 1 and
  .subagents_source_present == 1 and
  .http_source_present == 1 and
  .configmap_present == 1 and
  .contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B20.8" and
  (.subagents.roles | length) == 3 and
  any(.subagents.roles[]; .subagent_id == "core" and .role_tag == "core-runtime") and
  any(.subagents.roles[]; .subagent_id == "experiments" and .role_tag == "experiments-analysis") and
  any(.subagents.roles[]; .subagent_id == "manuscript" and .role_tag == "manuscript-authoring")
' "${OUT}/workspace-subagent-list.json" >/dev/null

jq -e '
  .phase == "B20.8" and
  .route.selection.requested_tool_id == "claude-code" and
  .route.selection.requested_work_mode == "manuscript" and
  .route.selection.selected_subagent_id == "manuscript" and
  .route.selection.selected_role_tag == "manuscript-authoring" and
  .route.attach_metadata.workspace_folder == "/workspace/beagle/docs/darwin/hpc" and
  .route.attach_metadata.env_file == "/workspace/beagle/.beagle/context/subagents/manuscript.env"
' "${OUT}/route-manuscript.json" >/dev/null

jq -e '
  .phase == "B20.9" and
  .handoff.source_subagent_id == "core" and
  .handoff.target_subagent_id == "experiments" and
  .target_route.selection.selected_subagent_id == "experiments"
' "${OUT}/handoff-core-to-experiments.json" >/dev/null

jq -e --slurpfile upstream "${OUT}/handoff-core-to-experiments.json" '
  .phase == "B21.1" and
  .manuscript_handoff.workstream_id == "beagle-darwin-hpc-governance" and
  .manuscript_handoff.workspace_id == "beagle-cluster-pilot" and
  .manuscript_handoff.session_id == "ws-cluster-workspace-habitat" and
  .manuscript_handoff.source_subagent_id == "experiments" and
  .manuscript_handoff.target_subagent_id == "manuscript" and
  .manuscript_handoff.target_role_tag == "manuscript-authoring" and
  .manuscript_handoff.upstream_handoff_id == $upstream[0].handoff.handoff_id and
  .manuscript_handoff.target_route_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=claude-code&work_mode=manuscript&preferred_subagent=manuscript" and
  .target_route.selection.selected_subagent_id == "manuscript" and
  .target_route.selection.selected_role_tag == "manuscript-authoring" and
  .continuity.handoff_present == true and
  .continuity.claim_count >= 1 and
  .continuity.supported_claim_count >= 1 and
  .continuity.result_ref_count >= 1 and
  .continuity.memory_ref_count >= 1 and
  .continuity.recipe_ref_count >= 1 and
  .continuity.target_env_file == "/workspace/beagle/.beagle/context/subagents/manuscript.env" and
  .continuity.target_workspace_folder == "/workspace/beagle/docs/darwin/hpc" and
  .context_packet.handoff.last_handoff == .manuscript_handoff.subagent_handoff_text and
  .manuscript_handoff.managed_attach_state == "coder-compatible-ready" and
  .manuscript_handoff.stable_attach_alias == "beagle-cluster-pilot.coder" and
  .evidence_pack.campaign_id == .manuscript_handoff.campaign_id and
  .claims.campaign_id == .manuscript_handoff.campaign_id and
  .manuscript_pack.campaign_id == .manuscript_handoff.campaign_id
' "${OUT}/workspace-manuscript-handoff-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" '
  .manuscript_handoff.manuscript_handoff_id == $post[0].manuscript_handoff.manuscript_handoff_id and
  .manuscript_handoff.subagent_handoff_id == $post[0].manuscript_handoff.subagent_handoff_id and
  .manuscript_handoff.target_subagent_id == "manuscript" and
  .context_packet.handoff.last_handoff == .manuscript_handoff.subagent_handoff_text
' "${OUT}/workspace-manuscript-handoff.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" '
  .packet.campaign_id == $post[0].manuscript_handoff.campaign_id and
  .packet.active_workstream_id == "beagle-darwin-hpc-governance"
' "${OUT}/campaign-context-packet.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" '
  .pack.campaign_id == $post[0].manuscript_handoff.campaign_id and
  (.pack.result_refs | length) >= 1 and
  (.pack.memory_refs | length) >= 1
' "${OUT}/campaign-evidence-pack.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" '
  .campaign_id == $post[0].manuscript_handoff.campaign_id and
  (.claims | length) >= 1 and
  any(.claims[]; .claim_state == "supported")
' "${OUT}/campaign-claims.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" '
  .pack.campaign_id == $post[0].manuscript_handoff.campaign_id and
  .pack.readiness_state != null and
  (.pack.claim_ids | length) >= 1
' "${OUT}/campaign-manuscript-pack.json" >/dev/null

grep -q "BEAGLE_SUBAGENT_ROLE_TAG='experiments-analysis'" "${OUT}/experiments.env"
grep -q "BEAGLE_SUBAGENT_WORK_MODES='experiments,analysis,evaluation,evidence,results-synthesis'" "${OUT}/experiments.env"
grep -q "BEAGLE_SUBAGENT_DEFAULT_TOOLS='claude-code'" "${OUT}/experiments.env"

grep -q "BEAGLE_SUBAGENT_ROLE_TAG='manuscript-authoring'" "${OUT}/manuscript.env"
grep -q "BEAGLE_SUBAGENT_WORK_MODES='manuscript,paper,writing,editorial,claims,discussion'" "${OUT}/manuscript.env"
grep -q "BEAGLE_SUBAGENT_DEFAULT_TOOLS='claude-code,cursor'" "${OUT}/manuscript.env"

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

IFS=$'\t' read -r man_workstream man_workspace man_session man_subagent man_role_tag man_pwd < "${OUT}/manuscript-identity.txt"
[[ "${man_workstream}" == "beagle-darwin-hpc-governance" ]]
[[ "${man_workspace}" == "beagle-cluster-pilot" ]]
[[ "${man_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${man_subagent}" == "manuscript" ]]
[[ "${man_role_tag}" == "manuscript-authoring" ]]
[[ "${man_pwd}" == "/workspace/beagle/docs/darwin/hpc" ]]

IFS=$'\t' read -r _ _ exp_restart_session exp_restart_subagent exp_restart_role_tag exp_restart_pwd < "${OUT}/experiments-identity-after-restart.txt"
[[ "${exp_restart_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${exp_restart_subagent}" == "experiments" ]]
[[ "${exp_restart_role_tag}" == "experiments-analysis" ]]
[[ "${exp_restart_pwd}" == "/workspace/beagle/crates/beagle-experiments" ]]

IFS=$'\t' read -r _ _ man_restart_session man_restart_subagent man_restart_role_tag man_restart_pwd < "${OUT}/manuscript-identity-after-restart.txt"
[[ "${man_restart_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${man_restart_subagent}" == "manuscript" ]]
[[ "${man_restart_role_tag}" == "manuscript-authoring" ]]
[[ "${man_restart_pwd}" == "/workspace/beagle/docs/darwin/hpc" ]]

jq -e --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" '
  .manuscript_handoff.manuscript_handoff_id == $post[0].manuscript_handoff.manuscript_handoff_id and
  .manuscript_handoff.session_id == $post[0].manuscript_handoff.session_id and
  .manuscript_handoff.campaign_id == $post[0].manuscript_handoff.campaign_id and
  .manuscript_handoff.target_subagent_id == "manuscript" and
  .context_packet.handoff.last_handoff == .manuscript_handoff.subagent_handoff_text
' "${OUT}/workspace-manuscript-handoff-after-restart.json" >/dev/null

jq -e '
  .phase == "B21.1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "experiments" and
  .target_subagent_id == "manuscript" and
  .target_selected_subagent == "manuscript" and
  .claim_count >= 1 and
  .managed_attach_state == "coder-compatible-ready" and
  .stable_attach_alias == "beagle-cluster-pilot.coder" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "deployment.apps/beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core.*1/1" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace.*1/1" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary).*UP" "${OUT}/final-cluster-health.txt"

echo "[OK] manuscript subagent loop smoke artifacts validated"
