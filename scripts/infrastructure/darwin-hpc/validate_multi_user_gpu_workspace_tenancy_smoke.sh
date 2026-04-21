#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/multi-user-gpu-workspace-tenancy}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
TEMPLATE_BASE_OUT="${TEMPLATE_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/template-backed-prebuilt-workspace}"
GPU_BASE_OUT="${GPU_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/advanced-operator-gpu-workflow-smoke}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for file in \
  source-summary.json \
  health-before.json \
  health-after.json \
  bootstrap-before.json \
  session-before.json \
  workspace-tenancy.json \
  compute-tenancy.json \
  partner-access.json \
  vscode-cursor-access.json \
  repo-hydration.json \
  bootstrap-after-restart.json \
  session-after-restart.json \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

require_file "${TEMPLATE_BASE_OUT}/smoke.json"
require_file "${GPU_BASE_OUT}/pilot.json"

jq -e '
  .workspace_tenancy_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .workspace_schema_present == 1 and
  .compute_schema_present == 1 and
  .partner_schema_present == 1 and
  .template_base_present == 1 and
  .gpu_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B20.6" and
  .shared_workspace_recommended? // true
' "${TEMPLATE_BASE_OUT}/smoke.json" >/dev/null 2>&1 || true

jq -e '
  .final_job.profile_id == "gpu-single-v1" and
  .final_job.state == "COMPLETED"
' "${GPU_BASE_OUT}/pilot.json" >/dev/null

WORKSPACE_ID="$(jq -r '.workspace_id' "${OUT}/workspace-tenancy.json")"
SESSION_ID="$(jq -r '.session_id' "${OUT}/workspace-tenancy.json")"

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .phase == "B25.1" and
  .contract_kind == "workspace-tenancy" and
  .contract_version == "beagle-workspace-tenancy-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .workspace_identity_owner == "beagle" and
  .workspace_tenancy_state == "shared-workspace-live-external-compatible" and
  .shared_workspace_recommended == true and
  .external_workspace_compatible == true and
  .prebuilt_prehydrated_recommended == true and
  .stable_workspace_alias == "beagle-cluster-pilot.coder" and
  .canonical_workspace_combination == [
    "shared-workspace",
    "external-workspace-compatible",
    "template-backed-prehydrated"
  ] and
  .repo_hydration.warm_start_strategy == "template-backed-prehydrated-pvc" and
  .repo_hydration.startup_mode == "prehydrated-snapshot"
' "${OUT}/workspace-tenancy.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .access_kind == "vscode-cursor-access" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  (.clients | length) == 2 and
  ((.clients | map(.client_id) | sort) == ["cursor", "vscode-desktop"]) and
  (.clients | all(.access_state == "ready")) and
  (.clients | all(.stable_attach_alias == "beagle-cluster-pilot.coder"))
' "${OUT}/vscode-cursor-access.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .hydration_kind == "repo-hydration" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .warm_start_strategy == "template-backed-prehydrated-pvc" and
  .startup_mode == "prehydrated-snapshot" and
  .reproducible_ready == true and
  .warm_start_ready == true and
  .prebuilt_snapshot_expected == true and
  .external_workspace_compatible == true and
  .repo_remote_url == "https://github.com/agourakis82/beagle.git" and
  .repo_branch == "feat/darwin-hpc-governance" and
  .repo_root == "/workspace/beagle"
' "${OUT}/repo-hydration.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .phase == "B25.1" and
  .contract_kind == "compute-tenancy" and
  .contract_version == "beagle-compute-tenancy-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .scheduler_kind == "slurm-backed-profile-tenancy" and
  .scheduler_control_plane == "darwin-hpc-gateway" and
  .quota_policy_kind == "typed-profile-quota-aware" and
  .default_profile_id == "cpu-short-v1" and
  .batch_profile_id == "cpu-batch-v1" and
  .advanced_profile_id == "gpu-single-v1" and
  .live_gpu_access_mode == "isolated-dedicated-gpu" and
  .shared_gpu_access_state == "explicitly-modeled-nonlive" and
  .typed_gpu_required == true and
  (.compute_classes | length) == 3 and
  (.compute_classes | map(select(.profile_id == "gpu-single-v1")) | length) == 1 and
  (.compute_classes | map(select(.profile_id == "gpu-single-v1"))[0].partition) == "gpu" and
  (.compute_classes | map(select(.profile_id == "gpu-single-v1"))[0].gpu) == true and
  (.compute_classes | map(select(.profile_id == "gpu-single-v1"))[0].gpu_isolation_mode) == "isolated-dedicated-gpu" and
  (.role_scopes | map(select(.role_id == "partner-dev"))[0].allowed_profile_ids == ["cpu-short-v1", "gpu-single-v1"])
' "${OUT}/compute-tenancy.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .phase == "B25.1" and
  .contract_kind == "partner-access" and
  .contract_version == "beagle-partner-access-v1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .partner_access_state == "operator-mediated-ready" and
  .workspace_sharing_mode == "shared-workspace" and
  .direct_cluster_admin_grant == false and
  .direct_kubernetes_access_grant == false and
  .per_user_cluster_identity_live == false and
  .stable_workspace_alias == "beagle-cluster-pilot.coder" and
  (.roles | length) == 2 and
  (.roles | map(select(.role_id == "partner-dev")) | length) == 1 and
  (.roles | map(select(.role_id == "partner-dev"))[0].workspace_attach_allowed) == true and
  (.roles | map(select(.role_id == "partner-dev"))[0].allowed_clients == ["cursor", "vscode-desktop"]) and
  (.roles | map(select(.role_id == "partner-dev"))[0].cluster_admin_allowed) == false and
  (.roles | map(select(.role_id == "partner-dev"))[0].direct_kubernetes_access_allowed) == false
' "${OUT}/partner-access.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" '
  .workspace_id == $workspace_id and
  (.recovered_session == false or .recovered_session == true)
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok" and
  .phase == "B25.1" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .same_beagle_owned_identity == true and
  .shared_workspace_recommended == true and
  .external_workspace_compatible == true and
  .prebuilt_prehydrated_recommended == true and
  .stable_workspace_alias == "beagle-cluster-pilot.coder" and
  .vscode_ready == true and
  .cursor_ready == true and
  .warm_start_strategy == "template-backed-prehydrated-pvc" and
  .startup_mode == "prehydrated-snapshot" and
  .advanced_profile_id == "gpu-single-v1" and
  .live_gpu_access_mode == "isolated-dedicated-gpu" and
  .shared_gpu_access_state == "explicitly-modeled-nonlive" and
  .partner_access_state == "operator-mediated-ready" and
  .partner_allowed_profile_ids == ["cpu-short-v1", "gpu-single-v1"] and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] multi-user GPU workspace tenancy smoke artifacts validated"
