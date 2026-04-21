#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/managed-attach-plane}"
BASE_OUT="${BASE_OUT:-${OUT}/habitat}"
ATTACH_OUT="${ATTACH_OUT:-${OUT}/managed-attach}"
KUBECTL="${KUBECTL:-}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
WORKSPACE_ATTACH_SOURCE_FILE="${WORKSPACE_ATTACH_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_attach.rs}"
WORKSPACE_HABITAT_SOURCE_FILE="${WORKSPACE_HABITAT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_habitat.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
INSTALLER_SCRIPT="${INSTALLER_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/install_managed_workspace_attach.sh}"
PROXY_SCRIPT="${PROXY_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh}"
SSH_IMAGE_REF="${SSH_IMAGE_REF:-localhost/beagle-workspace-ssh:b204}"
SSH_ARCHIVE_PATH="${SSH_ARCHIVE_PATH:-/tmp/beagle-workspace-ssh-b204.oci.tar}"
SSH_DOCKERFILE="${SSH_DOCKERFILE:-${ROOT}/k8s/beagle-workspace/Dockerfile.ssh}"
PREVIOUS_ATTACH_FILE="${PREVIOUS_ATTACH_FILE:-${ROOT}/.artifacts/darwin-hpc/operator-friendly-attach-plane/workspace-attach.json}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-attach-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B204_MANAGED_ATTACH_PLANE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B204_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B204_KNOWN_LIMITS.md}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require cp
require jq
require podman
require rg
require sudo

mkdir -p "${OUT}" "${ATTACH_OUT}"

WORKSPACE_ATTACH_SOURCE_PRESENT=0
WORKSPACE_HABITAT_SOURCE_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
INSTALLER_PRESENT=0
PROXY_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "managed_attach_state|managed-coder-compatible-remote-ssh|workspace_exec_proxy.sh" "${WORKSPACE_ATTACH_SOURCE_FILE}"; then
  WORKSPACE_ATTACH_SOURCE_PRESENT=1
fi
if rg -q "BEAGLE_MANAGED_ATTACH_PATH|BEAGLE_MANAGED_ATTACH_INSTALLER|BEAGLE_MANAGED_ATTACH_PROXY" "${WORKSPACE_HABITAT_SOURCE_FILE}"; then
  WORKSPACE_HABITAT_SOURCE_PRESENT=1
fi
if rg -q "managed_attach_path|/managed-attach" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if [[ -f "${INSTALLER_SCRIPT}" ]]; then
  INSTALLER_PRESENT=1
fi
if [[ -f "${PROXY_SCRIPT}" ]]; then
  PROXY_PRESENT=1
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
  --argjson workspace_attach_source_present "${WORKSPACE_ATTACH_SOURCE_PRESENT}" \
  --argjson workspace_habitat_source_present "${WORKSPACE_HABITAT_SOURCE_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson installer_present "${INSTALLER_PRESENT}" \
  --argjson proxy_present "${PROXY_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    workspace_attach_source_present: $workspace_attach_source_present,
    workspace_habitat_source_present: $workspace_habitat_source_present,
    cockpit_source_present: $cockpit_source_present,
    installer_present: $installer_present,
    proxy_present: $proxy_present,
    contract_present: $contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

sudo podman build --no-cache -t "${SSH_IMAGE_REF}" -f "${SSH_DOCKERFILE}" "${ROOT}/k8s/beagle-workspace" > "${OUT}/ssh-image-build.log" 2>&1
IMAGE_REF="${SSH_IMAGE_REF}" ARCHIVE_PATH="${SSH_ARCHIVE_PATH}" \
  bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/ssh-image-load.log" 2>&1

ROOT="${ROOT}" KUBECTL="${KUBECTL}" OUT="${BASE_OUT}" \
  "${ROOT}/scripts/infrastructure/darwin-hpc/run_cluster_workspace_habitat_smoke.sh"

cp "${BASE_OUT}/workspace-context.json" "${OUT}/workspace-context.json"
cp "${BASE_OUT}/workspace-context-after-restart.json" "${OUT}/workspace-context-after-restart.json"
cp "${BASE_OUT}/workspace-runtime-summary.json" "${OUT}/workspace-runtime-summary.json"
cp "${BASE_OUT}/workspace-health.txt" "${OUT}/workspace-health.txt"
cp "${BASE_OUT}/tool-cursor.json" "${OUT}/tool-cursor.json"
cp "${BASE_OUT}/final-cluster-health.txt" "${OUT}/final-cluster-health.txt"

REMOTE_IDENTITY_COMMAND="sh -lc '. /workspace/beagle/.beagle/context/beagle-context.env && printf \"%s\t%s\t%s\n\" \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\"'"
REMOTE_CONTEXT_ENV_COMMAND="cat /workspace/beagle/.beagle/context/beagle-context.env"
REMOTE_CONTEXT_PACKET_COMMAND="cat /workspace/beagle/.beagle/context/current-context-packet.json"

bash "${INSTALLER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client cursor \
  --out "${ATTACH_OUT}" \
  --json-out "${OUT}/managed-attach-summary.json" \
  --remote-command "${REMOTE_IDENTITY_COMMAND}" \
  --remote-output "${OUT}/attach-identity.txt"

cp "${ATTACH_OUT}/workspace-attach.json" "${OUT}/workspace-attach.json"
cp "$(jq -r '.ssh_config_path' "${OUT}/managed-attach-summary.json")" "${OUT}/attach-ssh-config"

bash "${INSTALLER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client ssh \
  --out "${ATTACH_OUT}" \
  --json-out "${OUT}/managed-attach-summary-ssh.json" \
  --remote-command "${REMOTE_CONTEXT_ENV_COMMAND}" \
  --remote-output "${OUT}/attach-context.env"

bash "${INSTALLER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client ssh \
  --out "${ATTACH_OUT}" \
  --json-out "${OUT}/managed-attach-summary-context.json" \
  --remote-command "${REMOTE_CONTEXT_PACKET_COMMAND}" \
  --remote-output "${OUT}/attach-context-packet.json"

WORKSPACE_ID="$(jq -r '.attach.workspace_id' "${OUT}/workspace-attach.json")"
SESSION_ID="$(jq -r '.attach.session_id' "${OUT}/workspace-attach.json")"
ATTACH_METHOD="$(jq -r '.attach.attach_metadata.attach_method' "${OUT}/workspace-attach.json")"
MANAGED_ATTACH_STATE="$(jq -r '.attach.attach_metadata.managed_attach_state' "${OUT}/workspace-attach.json")"
ATTACH_HOST_ALIAS="$(jq -r '.attach.attach_metadata.stable_attach_host_alias' "${OUT}/workspace-attach.json")"
RESTART_RECOVERED_SESSION="$(jq -r '.restart_recovered_session' "${BASE_OUT}/smoke.json")"
PREVIOUS_ATTACH_METHOD="unknown"
if [[ -f "${PREVIOUS_ATTACH_FILE}" ]]; then
  PREVIOUS_ATTACH_METHOD="$(jq -r '.attach.attach_metadata.attach_method // "unknown"' "${PREVIOUS_ATTACH_FILE}")"
fi

jq -nc \
  --arg status "ok" \
  --arg phase "B20.4" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg attach_method "${ATTACH_METHOD}" \
  --arg managed_attach_state "${MANAGED_ATTACH_STATE}" \
  --arg attach_host_alias "${ATTACH_HOST_ALIAS}" \
  --arg helper_command "$(jq -r '.helper_command' "${OUT}/managed-attach-summary.json")" \
  --arg recommended_client "$(jq -r '.recommended_client' "${OUT}/managed-attach-summary.json")" \
  --arg ssh_command "$(jq -r '.ssh_command' "${OUT}/managed-attach-summary.json")" \
  --arg browser_url "$(jq -r '.browser_url // empty' "${OUT}/managed-attach-summary.json")" \
  --arg previous_attach_method "${PREVIOUS_ATTACH_METHOD}" \
  --argjson restart_recovered_session "${RESTART_RECOVERED_SESSION}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    recommended_client: $recommended_client,
    attach_method: $attach_method,
    managed_attach_state: $managed_attach_state,
    attach_host_alias: $attach_host_alias,
    helper_command: $helper_command,
    ssh_command: $ssh_command,
    browser_url: (if $browser_url == "" then null else $browser_url end),
    previous_attach_method: $previous_attach_method,
    managed_attach_ready: true,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

echo "[OK] managed attach plane smoke completed"
