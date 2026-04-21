#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/template-backed-prebuilt-workspace}"
BASE_OUT="${OUT}/launch-resume-plane"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
BASE_VALIDATOR="${BASE_VALIDATOR:-/home/devsounio/beagle/scripts/infrastructure/darwin-hpc/validate_managed_workspace_launch_resume_smoke.sh}"
EXPECTED_WARM_SENTINEL_FILE="${EXPECTED_WARM_SENTINEL_FILE:-/workspace/beagle/.beagle/context/template-backed-warm-sentinel.txt}"

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
  workspace-template.json \
  workspace-template-file.json \
  workspace-template-file-after-restart.json \
  external-workspace-registration.json \
  external-workspace-registration-after-restart.json \
  workspace-hydration.json \
  workspace-hydration-after-restart.json \
  warm-sentinel-after-restart.txt \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

EXPECTED_WORKSPACE_ID="$(jq -r '.launch.workspace_id' "${BASE_OUT}/workspace-launch-resume.json")"
EXPECTED_SESSION_ID="$(jq -r '.launch.session_id' "${BASE_OUT}/workspace-launch-resume.json")"
EXPECTED_ALIAS="${EXPECTED_WORKSPACE_ID}.coder"

jq -e '
  .template_source_present == 1 and
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
  .phase == "B20.6" and
  .template.workstream_id == $workstream_id and
  .template.workspace_id == $workspace_id and
  .template.session_id == $session_id and
  .template.workspace_template_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-template") and
  .template.workspace_launch_resume_path == ("/api/darwin/workstreams/" + $workstream_id + "/workspace-launch-resume") and
  .template.managed_attach_path == ("/api/darwin/workstreams/" + $workstream_id + "/managed-attach") and
  .template.context_packet_path == ("/api/darwin/workstreams/" + $workstream_id + "/context-packet") and
  .template.metadata.template_id == ("beagle-template-" + $workspace_id) and
  .template.metadata.template_version == "beagle-template-backed-prebuilt-workspace-v1" and
  .template.metadata.template_contract_kind == "template-backed-external-workspace-contract" and
  .template.metadata.reproducibility_mode == "template-backed-prehydrated-pvc" and
  .template.metadata.external_workspace_compatible == true and
  .template.metadata.attach_method == "managed-coder-compatible-remote-ssh" and
  .template.metadata.managed_attach_state == "coder-compatible-ready" and
  .template.metadata.stable_attach_alias == $alias and
  .template.metadata.browser_fallback_ready == true and
  .template.metadata.cursor_managed_attach_ready == true and
  .template.metadata.template_file == "/workspace/beagle/.beagle/context/workspace-template.json" and
  .template.metadata.registration_file == "/workspace/beagle/.beagle/context/external-workspace-registration.json" and
  .template.metadata.hydration_file == "/workspace/beagle/.beagle/context/workspace-hydration.json" and
  .template.hydration.warm_start_strategy == "template-backed-prehydrated-pvc" and
  .template.hydration.startup_mode == "prehydrated-snapshot" and
  .template.hydration.warm_start_ready == true and
  .template.hydration.reproducible_ready == true and
  .template.hydration.prebuilt_snapshot_expected == true and
  .template.external_registration.registration_kind == "coder-compatible-external-workspace" and
  .template.external_registration.registration_state == "template-backed-registered" and
  .template.external_registration.stable_workspace_alias == $alias and
  .launch.launch_metadata.launch_state == "resume-ready" and
  .habitat.workstream_id == $workstream_id and
  .habitat.workspace_id == $workspace_id and
  .habitat.session_id == $session_id and
  .context_packet.workstream_id == $workstream_id and
  .context_packet.workspace_id == $workspace_id and
  .context_packet.session_id == $session_id
' "${OUT}/workspace-template.json" >/dev/null

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .template_contract_kind == "template-backed-external-workspace-contract" and
  .reproducibility_mode == "template-backed-prehydrated-pvc" and
  .warm_start_strategy == "template-backed-prehydrated-pvc"
' "${OUT}/workspace-template-file.json" >/dev/null

jq -e '
  .registration_kind == "coder-compatible-external-workspace" and
  .registration_state == "template-backed-registered" and
  .recommended_client == "cursor"
' "${OUT}/external-workspace-registration.json" >/dev/null

jq -e '
  .startup_mode == "prehydrated-snapshot" and
  .warm_start_used == true and
  .prebuilt_snapshot_expected == true and
  .warm_start_strategy == "template-backed-prehydrated-pvc" and
  .hydrated_startup_path == "pvc-hydrated-workspace-snapshot"
' "${OUT}/workspace-hydration-after-restart.json" >/dev/null

IFS=$'\t' read -r sentinel_workstream sentinel_workspace sentinel_session sentinel_mode < "${OUT}/warm-sentinel-after-restart.txt"
[[ "${sentinel_workstream}" == "${EXPECTED_WORKSTREAM}" ]] || {
  echo "[FAIL] warm sentinel workstream mismatch: ${sentinel_workstream}" >&2
  exit 1
}
[[ "${sentinel_workspace}" == "${EXPECTED_WORKSPACE_ID}" ]] || {
  echo "[FAIL] warm sentinel workspace mismatch: ${sentinel_workspace}" >&2
  exit 1
}
[[ "${sentinel_session}" == "${EXPECTED_SESSION_ID}" ]] || {
  echo "[FAIL] warm sentinel session mismatch: ${sentinel_session}" >&2
  exit 1
}
[[ "${sentinel_mode}" == "template-backed-warm" ]] || {
  echo "[FAIL] warm sentinel mode mismatch: ${sentinel_mode}" >&2
  exit 1
}

jq -e \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --arg alias "${EXPECTED_ALIAS}" \
  --arg sentinel_file "${EXPECTED_WARM_SENTINEL_FILE}" '
  .status == "ok" and
  .phase == "B20.6" and
  .workstream_id == $workstream_id and
  .workspace_id == $workspace_id and
  .session_id == $session_id and
  .template_id == ("beagle-template-" + $workspace_id) and
  .template_version == "beagle-template-backed-prebuilt-workspace-v1" and
  .registration_state == "template-backed-registered" and
  .hydration_mode == "prehydrated-snapshot" and
  .warm_sentinel_file == $sentinel_file and
  .warm_start_used == true and
  .managed_attach_state == "coder-compatible-ready" and
  .attach_host_alias == $alias and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -q "beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "Slurmctld(primary) at" "${OUT}/final-cluster-health.txt"

echo "[OK] template-backed prebuilt workspace smoke artifacts validated"
