#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-jats-assembly}"

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
  "${OUT}/manuscript-assembly-request.json" \
  "${OUT}/workspace-manuscript-assembly-post.json" \
  "${OUT}/workspace-manuscript-assembly.json" \
  "${OUT}/campaign-context-packet.json" \
  "${OUT}/campaign-evidence-pack.json" \
  "${OUT}/campaign-claims.json" \
  "${OUT}/campaign-manuscript-pack.json" \
  "${OUT}/campaign-review-bundle.json" \
  "${OUT}/campaign-jats-manuscript-pack.json" \
  "${OUT}/jats-article.xml" \
  "${OUT}/workspace-context.json" \
  "${OUT}/workspace-context-after-restart.json" \
  "${OUT}/workspace-context.env" \
  "${OUT}/manuscript.env" \
  "${OUT}/core-identity.txt" \
  "${OUT}/experiments-identity.txt" \
  "${OUT}/manuscript-identity.txt" \
  "${OUT}/manuscript-identity-after-restart.txt" \
  "${OUT}/workspace-manuscript-assembly-after-restart.json" \
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
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_section_profile == "jats-1.4-ready" and
  .assembly_source_present == 1 and
  .manuscript_handoff_source_present == 1 and
  .manuscript_pack_source_present == 1 and
  .review_bundle_source_present == 1 and
  .http_source_present == 1 and
  .contract_present == 1 and
  .jats_contract_present == 1 and
  .section_map_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B20.8" and
  (.subagents.roles | length) == 3 and
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
  .handoff.target_subagent_id == "experiments"
' "${OUT}/handoff-core-to-experiments.json" >/dev/null

jq -e '
  .phase == "B21.1" and
  .manuscript_handoff.source_subagent_id == "experiments" and
  .manuscript_handoff.target_subagent_id == "manuscript" and
  .target_route.selection.selected_subagent_id == "manuscript"
' "${OUT}/workspace-manuscript-handoff-post.json" >/dev/null

jq -e --slurpfile handoff "${OUT}/workspace-manuscript-handoff-post.json" '
  .phase == "B21.2" and
  .assembly.workstream_id == "beagle-darwin-hpc-governance" and
  .assembly.workspace_id == "beagle-cluster-pilot" and
  .assembly.session_id == "ws-cluster-workspace-habitat" and
  .assembly.source_subagent_id == "manuscript" and
  .assembly.source_role_tag == "manuscript-authoring" and
  .assembly.section_profile == "jats-1.4-ready" and
  .assembly.upstream_manuscript_handoff_id == $handoff[0].manuscript_handoff.manuscript_handoff_id and
  .assembly.program_id == .program_context.program_id and
  .assembly.campaign_id == .program_context.campaign_id and
  .assembly.evidence_pack_ref == "/api/darwin/campaigns/expedition-002-hrv-aware/evidence-pack" and
  .assembly.claims_ref == "/api/darwin/campaigns/expedition-002-hrv-aware/claims" and
  .assembly.manuscript_pack_ref == "/api/darwin/campaigns/expedition-002-hrv-aware/manuscript-pack" and
  .assembly.review_bundle_ref == "/api/darwin/campaigns/expedition-002-hrv-aware/review-bundle" and
  .assembly.jats_manuscript_pack_ref == "/api/darwin/campaigns/expedition-002-hrv-aware/jats-manuscript-pack" and
  .assembly.section_map_contract_ref == "docs/darwin/hpc/contracts/manuscript-section-map.yaml" and
  .assembly.managed_attach_state == "coder-compatible-ready" and
  .assembly.stable_attach_alias == "beagle-cluster-pilot.coder" and
  .continuity.handoff_present == true and
  .context_packet.handoff.last_handoff == $handoff[0].manuscript_handoff.subagent_handoff_text and
  .continuity.claim_count >= 1 and
  .continuity.supported_claim_count >= 1 and
  .continuity.result_ref_count >= 1 and
  .continuity.memory_ref_count >= 1 and
  .continuity.recipe_ref_count >= 1 and
  .continuity.review_payload_count >= 3 and
  .continuity.section_count >= 6 and
  ((.continuity.section_types | index("abstract")) != null) and
  ((.continuity.section_types | index("methods")) != null) and
  ((.continuity.section_types | index("results")) != null) and
  ((.continuity.section_types | index("discussion")) != null) and
  .continuity.jats_profile == "jats-1.4-ready" and
  .continuity.article_type == "research-article" and
  .continuity.readiness_state == .jats_pack.readiness_state and
  .evidence_pack.campaign_id == .assembly.campaign_id and
  .claims.campaign_id == .assembly.campaign_id and
  .manuscript_pack.campaign_id == .assembly.campaign_id and
  .review_bundle.campaign_id == .assembly.campaign_id and
  .jats_pack.campaign_id == .assembly.campaign_id and
  .jats_pack.claim_ids == .manuscript_pack.claim_ids and
  (.jats_pack.jats_xml | contains("<article ")) and
  (.jats_pack.jats_xml | contains("<front>")) and
  (.jats_pack.jats_xml | contains("<body>")) and
  (.jats_pack.jats_xml | contains("<ref-list>"))
' "${OUT}/workspace-manuscript-assembly-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .assembly.assembly_id == $post[0].assembly.assembly_id and
  .assembly.upstream_manuscript_handoff_id == $post[0].assembly.upstream_manuscript_handoff_id and
  .jats_pack.pack_id == $post[0].jats_pack.pack_id and
  .context_packet.handoff.last_handoff == $post[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-manuscript-assembly.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .packet.campaign_id == $post[0].assembly.campaign_id and
  .packet.active_workstream_id == "beagle-darwin-hpc-governance"
' "${OUT}/campaign-context-packet.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .pack.campaign_id == $post[0].assembly.campaign_id and
  (.pack.result_refs | length) >= 1 and
  (.pack.memory_refs | length) >= 1 and
  (.pack.provenance.activities | length) >= 1
' "${OUT}/campaign-evidence-pack.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .campaign_id == $post[0].assembly.campaign_id and
  (.claims | length) >= 1 and
  any(.claims[]; .claim_state == "supported")
' "${OUT}/campaign-claims.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .pack.campaign_id == $post[0].assembly.campaign_id and
  .pack.readiness_state == $post[0].assembly.readiness_state and
  (.pack.claim_ids | length) >= 1
' "${OUT}/campaign-manuscript-pack.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .bundle.campaign_id == $post[0].assembly.campaign_id and
  .bundle.readiness_state == $post[0].assembly.readiness_state and
  (.bundle.payload_manifest | length) >= 3
' "${OUT}/campaign-review-bundle.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .pack.campaign_id == $post[0].assembly.campaign_id and
  .pack.workspace_id == $post[0].assembly.workspace_id and
  .pack.session_id == $post[0].assembly.session_id and
  .pack.jats_profile == "jats-1.4-ready" and
  .pack.article_type == "research-article" and
  .pack.readiness_state == $post[0].assembly.readiness_state and
  .pack.pack_id == $post[0].assembly.jats_pack_id and
  (.pack.section_map | length) >= 6 and
  (.pack.jats_xml | contains("<article ")) and
  (.pack.jats_xml | contains("<front>")) and
  (.pack.jats_xml | contains("<body>")) and
  (.pack.jats_xml | contains("<ref-list>"))
' "${OUT}/campaign-jats-manuscript-pack.json" >/dev/null

grep -q "<article " "${OUT}/jats-article.xml"
grep -q "<front>" "${OUT}/jats-article.xml"
grep -q "<body>" "${OUT}/jats-article.xml"
grep -q "<ref-list>" "${OUT}/jats-article.xml"

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

IFS=$'\t' read -r _ _ man_restart_session man_restart_subagent man_restart_role_tag man_restart_pwd < "${OUT}/manuscript-identity-after-restart.txt"
[[ "${man_restart_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${man_restart_subagent}" == "manuscript" ]]
[[ "${man_restart_role_tag}" == "manuscript-authoring" ]]
[[ "${man_restart_pwd}" == "/workspace/beagle/docs/darwin/hpc" ]]

jq -e --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" '
  .assembly.assembly_id == $post[0].assembly.assembly_id and
  .assembly.session_id == $post[0].assembly.session_id and
  .assembly.campaign_id == $post[0].assembly.campaign_id and
  .jats_pack.pack_id == $post[0].jats_pack.pack_id and
  .continuity.jats_profile == "jats-1.4-ready" and
  .context_packet.handoff.last_handoff == $post[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-manuscript-assembly-after-restart.json" >/dev/null

jq -e '
  .phase == "B21.2" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "manuscript" and
  .route_selected_subagent == "manuscript" and
  .claim_count >= 1 and
  .section_count >= 6 and
  .jats_profile == "jats-1.4-ready" and
  .readiness_state != null and
  .managed_attach_state == "coder-compatible-ready" and
  .stable_attach_alias == "beagle-cluster-pilot.coder" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "deployment.apps/beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core.*1/1" "${OUT}/final-cluster-health.txt"
grep -q "beagle-workspace.*1/1" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary).*UP" "${OUT}/final-cluster-health.txt"

echo "[OK] manuscript jats assembly smoke artifacts validated"
