#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/managed-workspace-launch-resume}"
BASE_OUT="${BASE_OUT:-${OUT}/managed-attach-plane}"
LAUNCH_OUT="${LAUNCH_OUT:-${OUT}/launch-resume}"
KUBECTL="${KUBECTL:-}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
BASE_SMOKE="${BASE_SMOKE:-${ROOT}/scripts/infrastructure/darwin-hpc/run_managed_attach_plane_smoke.sh}"
LAUNCH_SOURCE_FILE="${LAUNCH_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_launch_resume.rs}"
WORKSPACE_HABITAT_SOURCE_FILE="${WORKSPACE_HABITAT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_habitat.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
HELPER_SCRIPT="${HELPER_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-launch-resume-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B205_TOOL_DOCK_MANAGED_WORKSPACE_LAUNCH_SESSION_RESUME.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B205_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B205_KNOWN_LIMITS.md}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require cp
require jq
require rg

mkdir -p "${OUT}" "${LAUNCH_OUT}"

LAUNCH_SOURCE_PRESENT=0
WORKSPACE_HABITAT_SOURCE_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
HELPER_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "tool-dock-managed-workspace-launch-resume|workspace-launch-resume" "${LAUNCH_SOURCE_FILE}"; then
  LAUNCH_SOURCE_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_LAUNCH_RESUME_PATH|BEAGLE_WORKSPACE_LAUNCH_RESUME_HELPER" "${WORKSPACE_HABITAT_SOURCE_FILE}"; then
  WORKSPACE_HABITAT_SOURCE_PRESENT=1
fi
if rg -q "workspace_launch_resume_path|/workspace-launch-resume" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "/workspace-launch-resume|build_workstream_workspace_launch_resume" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if [[ -f "${HELPER_SCRIPT}" ]]; then
  HELPER_PRESENT=1
fi
if [[ -f "${CONTRACT_FILE}" ]]; then
  CONTRACT_PRESENT=1
fi
if [[ -f "${DOC_FILE}" ]]; then
  DOC_PRESENT=1
fi
if [[ -f "${GO_NO_GO_FILE}" ]]; then
  GO_NO_GO_PRESENT=1
fi
if [[ -f "${KNOWN_LIMITS_FILE}" ]]; then
  KNOWN_LIMITS_PRESENT=1
fi

jq -nc \
  --argjson launch_source_present "${LAUNCH_SOURCE_PRESENT}" \
  --argjson workspace_habitat_source_present "${WORKSPACE_HABITAT_SOURCE_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson helper_present "${HELPER_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    launch_source_present: $launch_source_present,
    workspace_habitat_source_present: $workspace_habitat_source_present,
    cockpit_source_present: $cockpit_source_present,
    http_source_present: $http_source_present,
    helper_present: $helper_present,
    contract_present: $contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

ROOT="${ROOT}" KUBECTL="${KUBECTL}" OUT="${BASE_OUT}" bash "${BASE_SMOKE}"

cp "${BASE_OUT}/workspace-context.json" "${OUT}/workspace-context.json"
cp "${BASE_OUT}/workspace-context-after-restart.json" "${OUT}/workspace-context-after-restart.json"
cp "${BASE_OUT}/workspace-runtime-summary.json" "${OUT}/workspace-runtime-summary.json"
cp "${BASE_OUT}/workspace-health.txt" "${OUT}/workspace-health.txt"
cp "${BASE_OUT}/tool-cursor.json" "${OUT}/tool-cursor.json"
cp "${BASE_OUT}/final-cluster-health.txt" "${OUT}/final-cluster-health.txt"

REMOTE_IDENTITY_COMMAND="sh -lc '. /workspace/beagle/.beagle/context/beagle-context.env && printf \"%s\t%s\t%s\n\" \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\"'"

KUBECTL="${KUBECTL}" bash "${HELPER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client cursor \
  --out "${LAUNCH_OUT}" \
  --json-out "${OUT}/launch-summary.json" \
  --context-env-out "${OUT}/launch-context.env" \
  --context-packet-out "${OUT}/launch-context-packet.json" \
  --remote-command "${REMOTE_IDENTITY_COMMAND}" \
  --remote-output "${OUT}/launch-identity.txt"

cp "${LAUNCH_OUT}/workspace-launch-resume.json" "${OUT}/workspace-launch-resume.json"

WORKSPACE_ID="$(jq -r '.launch.workspace_id' "${OUT}/workspace-launch-resume.json")"
SESSION_ID="$(jq -r '.launch.session_id' "${OUT}/workspace-launch-resume.json")"
LAUNCH_METHOD="$(jq -r '.launch.launch_metadata.launch_method' "${OUT}/workspace-launch-resume.json")"
LAUNCH_STATE="$(jq -r '.launch.launch_metadata.launch_state' "${OUT}/workspace-launch-resume.json")"
MANAGED_ATTACH_STATE="$(jq -r '.launch.launch_metadata.managed_attach_state' "${OUT}/workspace-launch-resume.json")"
ATTACH_ALIAS="$(jq -r '.launch.launch_metadata.stable_launch_alias' "${OUT}/workspace-launch-resume.json")"
CURSOR_READY="$(jq -r '.launch.launch_metadata.cursor_managed_attach_ready' "${OUT}/workspace-launch-resume.json")"
BROWSER_READY="$(jq -r '.launch.launch_metadata.browser_fallback_ready' "${OUT}/workspace-launch-resume.json")"
RESTART_RECOVERED_SESSION="$(jq -r '.restart_recovered_session' "${BASE_OUT}/smoke.json")"

jq -nc \
  --arg status "ok" \
  --arg phase "B20.5" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg launch_method "${LAUNCH_METHOD}" \
  --arg launch_state "${LAUNCH_STATE}" \
  --arg managed_attach_state "${MANAGED_ATTACH_STATE}" \
  --arg attach_host_alias "${ATTACH_ALIAS}" \
  --arg helper_command "$(jq -r '.helper_command' "${OUT}/launch-summary.json")" \
  --arg recommended_client "$(jq -r '.recommended_client' "${OUT}/launch-summary.json")" \
  --arg browser_url "$(jq -r '.browser_url' "${OUT}/launch-summary.json")" \
  --argjson cursor_resume_ready "${CURSOR_READY}" \
  --argjson browser_fallback_ready "${BROWSER_READY}" \
  --argjson restart_recovered_session "${RESTART_RECOVERED_SESSION}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    recommended_client: $recommended_client,
    launch_method: $launch_method,
    launch_state: $launch_state,
    managed_attach_state: $managed_attach_state,
    attach_host_alias: $attach_host_alias,
    helper_command: $helper_command,
    browser_url: $browser_url,
    cursor_resume_ready: $cursor_resume_ready,
    browser_fallback_ready: $browser_fallback_ready,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

echo "[OK] managed workspace launch/resume smoke completed"
