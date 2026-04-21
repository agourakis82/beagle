#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/collaborative-compute-experiment-workbench}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for path in \
  "${OUT}/source-summary.json" \
  "${OUT}/health-before.json" \
  "${OUT}/health-after.json" \
  "${OUT}/bootstrap-before.json" \
  "${OUT}/session-before.json" \
  "${OUT}/workbench-session.json" \
  "${OUT}/compute-selection.json" \
  "${OUT}/collaboration-access.json" \
  "${OUT}/workbench-run.json" \
  "${OUT}/collaborative-workbench.json" \
  "${OUT}/bootstrap-after-restart.json" \
  "${OUT}/session-after-restart.json" \
  "${OUT}/collaborative-workbench-after-restart.json" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  require_file "${path}"
done

jq -e '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_workspace == "beagle-cluster-pilot" and
  .expected_session == "ws-cluster-workspace-habitat" and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .session_schema_present == 1 and
  .compute_schema_present == 1 and
  .collaboration_schema_present == 1 and
  .run_schema_present == 1 and
  .collaborative_workbench_schema_present == 1 and
  .workbench_source_present == 1 and
  .workspace_tenancy_source_present == 1 and
  .workspace_subagents_source_present == 1 and
  .execution_state_source_present == 1 and
  .http_source_present == 1 and
  .prior_b251_artifacts_present == 1 and
  .prior_b242_artifacts_present == 1 and
  .prior_b2413_artifacts_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B25.2" and
  .contract_kind == "workbench-session" and
  .contract_version == "beagle-workbench-session-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true and
  .workspace_identity_owner == "beagle" and
  .workspace_tenancy_state == "shared-workspace-live-external-compatible" and
  .stable_workspace_alias == "beagle-cluster-pilot.coder" and
  .default_dev_plane == "beagle-cluster" and
  .workspace_tenancy_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-tenancy" and
  .workspace_subagents_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagents" and
  .workspace_subagent_route_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route" and
  .context_packet_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/context-packet" and
  .plan_execution_path == "/api/darwin/workstreams/beagle-darwin-hpc-governance/plan-execution" and
  (.client_access | length) == 2 and
  ((.client_access | map(.client_id) | sort) == ["cursor", "vscode-desktop"]) and
  (.client_access | all(.access_state == "ready")) and
  (.subagent_roles | length) == 3 and
  ((.subagent_roles | map(.subagent_id) | sort) == ["core", "experiments", "manuscript"]) and
  .memory_context.retrieval_ready == true and
  .memory_context.query_type != null
' "${OUT}/workbench-session.json" >/dev/null

jq -e '
  .phase == "B25.2" and
  .contract_kind == "workbench-compute-selection" and
  .contract_version == "beagle-workbench-compute-selection-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true and
  .scheduler_kind == "slurm-backed-profile-tenancy" and
  .quota_policy_kind == "typed-profile-quota-aware" and
  .selection_mode == "operator-explicit-profile-pick" and
  .default_profile_id == "cpu-short-v1" and
  .batch_profile_id == "cpu-batch-v1" and
  .gpu_ready_profile_id == "gpu-single-v1" and
  .live_gpu_access_mode == "isolated-dedicated-gpu" and
  .shared_gpu_access_state == "explicitly-modeled-nonlive" and
  (.compute_classes | length) == 3 and
  (.role_scopes | map(select(.role_id == "partner-dev"))[0].allowed_profile_ids == ["cpu-short-v1", "gpu-single-v1"]) and
  (.suggested_profile_id | length) > 0 and
  (.suggested_profile_reason | length) > 0
' "${OUT}/compute-selection.json" >/dev/null

jq -e '
  .phase == "B25.2" and
  .contract_kind == "workbench-collaboration-access" and
  .contract_version == "beagle-workbench-collaboration-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true and
  .partner_access_state == "operator-mediated-ready" and
  .workspace_sharing_mode == "shared-workspace" and
  .stable_workspace_alias == "beagle-cluster-pilot.coder" and
  .collaboration_pattern == "shared-workspace-plus-scoped-compute" and
  .direct_cluster_admin_grant == false and
  .direct_kubernetes_access_grant == false and
  .per_user_cluster_identity_live == false and
  (.roles | length) == 2 and
  (.roles | map(select(.role_id == "partner-dev"))[0].allowed_clients == ["cursor", "vscode-desktop"]) and
  (.roles | map(select(.role_id == "partner-dev"))[0].allowed_profile_ids == ["cpu-short-v1", "gpu-single-v1"])
' "${OUT}/collaboration-access.json" >/dev/null

jq -e '
  .phase == "B25.2" and
  .contract_kind == "workbench-run" and
  .contract_version == "beagle-workbench-run-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true and
  .execution_available == true and
  .current_state == "succeeded" and
  .selected_subagent_id == "experiments" and
  .result_link_count >= 1 and
  (.last_result_available == true or ((.execution_result_links_path // "") | length) > 0) and
  .top_memory_ids != null and
  .memory_hit_count >= 0 and
  (.execution_state_path | length) > 0 and
  (.execution_receipt_path | length) > 0 and
  (.execution_result_links_path | length) > 0
' "${OUT}/workbench-run.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.2" and
  .contract_kind == "collaborative-compute-experiment-workbench" and
  .contract_version == "beagle-collaborative-compute-experiment-workbench-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true and
  .session.same_beagle_owned_identity == true and
  .compute_selection.same_beagle_owned_identity == true and
  .collaboration_access.same_beagle_owned_identity == true and
  .run.same_beagle_owned_identity == true
' "${OUT}/collaborative-workbench.json" >/dev/null

jq -e '
  .workspace_id == "beagle-cluster-pilot" and
  (.recovered_session == false or .recovered_session == true)
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e '
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.2" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true
' "${OUT}/collaborative-workbench-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B25.2" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .same_beagle_owned_identity == true and
  .stable_workspace_alias == "beagle-cluster-pilot.coder" and
  .vscode_ready == true and
  .cursor_ready == true and
  (.suggested_profile_id | length) > 0 and
  .partner_access_state == "operator-mediated-ready" and
  .partner_allowed_profile_ids == ["cpu-short-v1", "gpu-single-v1"] and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -q 'Slurmctld(primary) at' "${OUT}/final-cluster-health.txt"

echo "[OK] collaborative compute experiment workbench smoke artifacts validated"
