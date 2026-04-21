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
  constitution-normalized.json \
  current-state-summary.json \
  lineage-summary.json \
  consistency-summary.json; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

jq -e '
  .status == "ok"
  and (.files.charter.present == true and .files.charter.non_empty == true)
  and (.files.go_no_go.present == true and .files.go_no_go.non_empty == true)
  and (.files.known_limits.present == true and .files.known_limits.non_empty == true)
  and (.files.lineage.present == true and .files.lineage.non_empty == true)
  and (.files.constitution.present == true and .files.constitution.non_empty == true)
  and (.files.registry.present == true and .files.registry.non_empty == true)
  and (.files.workstream_spec.present == true and .files.workstream_spec.non_empty == true)
  and (.files.tool_bridge_policy.present == true and .files.tool_bridge_policy.non_empty == true)
  and (.files.configmap.present == true and .files.configmap.non_empty == true)
  and (.files.deployment.present == true and .files.deployment.non_empty == true)
  and (.files.service.present == true and .files.service.non_empty == true)
  and (.files.control_room.present == true and .files.control_room.non_empty == true)
  and (.files.workspace_plane.present == true and .files.workspace_plane.non_empty == true)
  and (.files.http_darwin_hpc.present == true and .files.http_darwin_hpc.non_empty == true)
  and (.files.core_server.present == true and .files.core_server.non_empty == true)
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok"
  and .mentions.darwin_v2 == true
  and .mentions.B14_1 == true
  and .mentions.B14_2 == true
  and .mentions.B14_3 == true
  and .mentions.B14_4 == true
  and .mentions.B15_1 == true
  and .mentions.B15_2 == true
  and .mentions.workstream_os == true
' "${OUT}/lineage-summary.json" >/dev/null

jq -e '
  .status == "ok"
  and .workstream_id == "beagle-darwin-hpc-governance"
  and .registry_state == "canonical"
  and .registry_last_transition == "resume"
  and .deployment_name == "beagle-core"
  and .service_name == "beagle-core"
  and .bind_addr == "0.0.0.0:8080"
  and .profile == "cluster"
  and .default_dev_plane == "beagle-cluster"
  and .vm_fallback_role == "fallback-only"
  and .promotion_scope == "beagle-darwin-hpc-general-noninfra"
  and .cutover_workstream == "beagle-darwin-hpc-governance"
  and .cutover_state == "canonical"
  and .last_transition == "resume"
  and .compute_profiles.default == "cpu-short-v1"
  and .compute_profiles.batch == "cpu-batch-v1"
  and .compute_profiles.advanced == "gpu-single-v1"
  and .result_plane.publication == "object-backed"
  and .result_plane.retrieval == "object-backed"
  and .result_plane.retention_policy == "active"
  and .consumer_policy.operator == "full"
  and .consumer_policy.darwin_research == "bounded"
  and .cheap_lane_status == "effectively_closed"
  and (.cheap_lane_live_providers | index("deepseek") != null)
  and (.cheap_lane_live_providers | index("glm5") != null)
  and (.cheap_lane_live_providers | index("minimax") != null)
  and (.cheap_lane_live_providers | index("grok_fast") != null)
  and (.cheap_lane_live_providers | index("kimi") != null)
  and .cheap_lane_defaults.deepseek == "deepseek-chat"
  and .cheap_lane_defaults.glm5 == "glm-5"
  and .cheap_lane_defaults.minimax == "MiniMax-M2.7"
  and .cheap_lane_defaults.grok_fast == "grok-4-1-fast-reasoning"
  and .cheap_lane_defaults.kimi == "moonshotai/kimi-k2-instruct-0905"
' "${OUT}/current-state-summary.json" >/dev/null

jq -e '
  .phase == "B15.2"
  and .mode == "aspirational-beagle-charter"
  and .status == "ok"
  and .north_star_present == true
  and .operational_beagle_status == "proven"
  and .aspirational_beagle_status == "declared"
  and .matched_default_dev_plane == true
  and .matched_vm_fallback_role == true
  and .matched_promotion_scope == true
  and .matched_canonical_workstream == true
  and .matched_governance_state == true
  and .matched_governance_last_transition == true
  and .matched_compute_profiles == true
  and .matched_result_plane == true
  and .matched_cheap_lane_status == true
  and .matched_cheap_lane_live_providers == true
  and .matched_cheap_lane_defaults == true
  and .matched_live_service == true
  and .matched_governance_model == true
  and .matched_registry_root == true
  and .matched_recipe_root == true
  and .matched_canonical_workstreams == true
  and .matched_governance_states == true
  and .matched_governance_transitions == true
  and .matched_proven_phases == true
  and .lineage_ok == true
  and .plane_authorities_present == true
' "${OUT}/consistency-summary.json" >/dev/null

echo "[OK] project constitution consistency validation passed"
