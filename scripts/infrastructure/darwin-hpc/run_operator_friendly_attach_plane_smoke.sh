#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/operator-friendly-attach-plane}"
BASE_OUT="${BASE_OUT:-${OUT}/habitat}"
ATTACH_HELPER_OUT="${ATTACH_HELPER_OUT:-${OUT}/attach-helper}"
KUBECTL="${KUBECTL:-}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
WORKSPACE_ATTACH_SOURCE_FILE="${WORKSPACE_ATTACH_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_attach.rs}"
WORKSPACE_HABITAT_SOURCE_FILE="${WORKSPACE_HABITAT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_habitat.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
HELPER_SCRIPT="${HELPER_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh}"
SSH_IMAGE_REF="${SSH_IMAGE_REF:-localhost/beagle-workspace-ssh:b202b}"
SSH_ARCHIVE_PATH="${SSH_ARCHIVE_PATH:-/tmp/beagle-workspace-ssh-b203.oci.tar}"
SSH_DOCKERFILE="${SSH_DOCKERFILE:-${ROOT}/k8s/beagle-workspace/Dockerfile.ssh}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-attach-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B203_OPERATOR_FRIENDLY_ATTACH_PLANE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B203_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B203_KNOWN_LIMITS.md}"

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

mkdir -p "${OUT}" "${ATTACH_HELPER_OUT}"

WORKSPACE_ATTACH_SOURCE_PRESENT=0
WORKSPACE_HABITAT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
HELPER_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "workspace-attach|helper-managed-native-remote-ssh|launch_workspace_attach.sh" "${WORKSPACE_ATTACH_SOURCE_FILE}"; then
  WORKSPACE_ATTACH_SOURCE_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_ATTACH_PATH|BEAGLE_WORKSPACE_ATTACH_HELPER" "${WORKSPACE_HABITAT_SOURCE_FILE}"; then
  WORKSPACE_HABITAT_SOURCE_PRESENT=1
fi
if rg -q "/workspace-attach|WorkspaceAttachResponse|build_workstream_workspace_attach" "${HTTP_SOURCE_FILE}"; then
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
  --argjson workspace_attach_source_present "${WORKSPACE_ATTACH_SOURCE_PRESENT}" \
  --argjson workspace_habitat_source_present "${WORKSPACE_HABITAT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson helper_present "${HELPER_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    workspace_attach_source_present: $workspace_attach_source_present,
    workspace_habitat_source_present: $workspace_habitat_source_present,
    http_source_present: $http_source_present,
    helper_present: $helper_present,
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

bash "${HELPER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client cursor \
  --out "${ATTACH_HELPER_OUT}" \
  --json-out "${OUT}/attach-helper-summary.json" \
  --remote-command "${REMOTE_IDENTITY_COMMAND}" \
  --remote-output "${OUT}/attach-identity.txt"

cp "${ATTACH_HELPER_OUT}/workspace-attach.json" "${OUT}/workspace-attach.json"
cp "$(jq -r '.ssh_config_path' "${OUT}/attach-helper-summary.json")" "${OUT}/attach-ssh-config"

bash "${HELPER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client ssh \
  --out "${ATTACH_HELPER_OUT}" \
  --json-out "${OUT}/attach-helper-summary-ssh.json" \
  --remote-command "${REMOTE_CONTEXT_ENV_COMMAND}" \
  --remote-output "${OUT}/attach-context.env"

bash "${HELPER_SCRIPT}" \
  --workstream "${EXPECTED_WORKSTREAM}" \
  --client ssh \
  --out "${ATTACH_HELPER_OUT}" \
  --json-out "${OUT}/attach-helper-summary-context.json" \
  --remote-command "${REMOTE_CONTEXT_PACKET_COMMAND}" \
  --remote-output "${OUT}/attach-context-packet.json"

WORKSPACE_ID="$(jq -r '.attach.workspace_id' "${OUT}/workspace-attach.json")"
SESSION_ID="$(jq -r '.attach.session_id' "${OUT}/workspace-attach.json")"
ATTACH_METHOD="$(jq -r '.attach.attach_metadata.attach_method' "${OUT}/workspace-attach.json")"
ATTACH_HOST_ALIAS="$(jq -r '.attach.attach_metadata.stable_attach_host_alias' "${OUT}/workspace-attach.json")"
RESTART_RECOVERED_SESSION="$(jq -r '.restart_recovered_session' "${BASE_OUT}/smoke.json")"

jq -nc \
  --arg status "ok" \
  --arg phase "B20.3" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg attach_method "${ATTACH_METHOD}" \
  --arg attach_host_alias "${ATTACH_HOST_ALIAS}" \
  --arg helper_command "$(jq -r '.helper_command' "${OUT}/attach-helper-summary.json")" \
  --arg recommended_client "$(jq -r '.attach.attach_metadata.recommended_client' "${OUT}/workspace-attach.json")" \
  --arg ssh_command "$(jq -r '.ssh_command' "${OUT}/attach-helper-summary.json")" \
  --arg browser_local_url "$(jq -r '.browser_local_url // empty' "${OUT}/attach-helper-summary.json")" \
  --argjson restart_recovered_session "${RESTART_RECOVERED_SESSION}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    recommended_client: $recommended_client,
    attach_method: $attach_method,
    attach_host_alias: $attach_host_alias,
    helper_command: $helper_command,
    ssh_command: $ssh_command,
    browser_local_url: (if $browser_local_url == "" then null else $browser_local_url end),
    helper_managed_attach_ready: true,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

echo "[OK] operator-friendly attach plane smoke completed"
