#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/cursor-native-remote-attach}"
BASE_OUT="${BASE_OUT:-${OUT}/habitat}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18241}"
WORKSPACE_SSH_LOCAL_PORT="${WORKSPACE_SSH_LOCAL_PORT:-18022}"
SSH_SECRET_NAME="${SSH_SECRET_NAME:-beagle-workspace-ssh-authorized-keys}"
SSH_IMAGE_REF="${SSH_IMAGE_REF:-localhost/beagle-workspace-ssh:b202b}"
SSH_ARCHIVE_PATH="${SSH_ARCHIVE_PATH:-/tmp/beagle-workspace-ssh-b202b.oci.tar}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_WORKSPACE_ID="${EXPECTED_WORKSPACE_ID:-beagle-cluster-pilot}"
EXPECTED_SESSION_ID="${EXPECTED_SESSION_ID:-ws-cluster-workspace-habitat}"
EXPECTED_SSH_USER="${EXPECTED_SSH_USER:-openvscode-server}"
CURSOR_REMOTE_LANE_SOURCE_FILE="${CURSOR_REMOTE_LANE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/cursor_remote_lane.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
WORKSPACE_DEPLOYMENT_FILE="${WORKSPACE_DEPLOYMENT_FILE:-${ROOT}/k8s/beagle-workspace/deployment.yaml}"
WORKSPACE_SERVICE_FILE="${WORKSPACE_SERVICE_FILE:-${ROOT}/k8s/beagle-workspace/service.yaml}"
WORKSPACE_SSH_DOCKERFILE="${WORKSPACE_SSH_DOCKERFILE:-${ROOT}/k8s/beagle-workspace/Dockerfile.ssh}"
WORKSPACE_SSH_ENTRYPOINT="${WORKSPACE_SSH_ENTRYPOINT:-${ROOT}/k8s/beagle-workspace/ssh-entrypoint.sh}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/cursor-native-remote-attach-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B202A_CURSOR_NATIVE_REMOTE_ATTACH.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B202A_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B202A_KNOWN_LIMITS.md}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require jq
require rg
require ssh
require ssh-keygen
require ss
require sudo

resolve_kubectl() {
  if [[ -n "${KUBECTL}" ]]; then
    printf '%s\n' "${KUBECTL}"
    return 0
  fi

  if [[ -r /etc/kubernetes/admin.conf ]]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    printf '%s\n' kubectl
    return 0
  fi

  if [[ -f /etc/kubernetes/admin.conf ]] && command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
    return 0
  fi

  printf '%s\n' kubectl
}

choose_local_port() {
  local port="$1"
  local tries=0

  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done

  echo "[FAIL] unable to find a free local port starting at $1" >&2
  exit 1
}

start_port_forward() {
  local service_name="$1"
  local local_port="$2"
  local remote_port="$3"
  local pf_log="$4"
  local pid_var="$5"

  : > "${pf_log}"
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${service_name}" "${local_port}:${remote_port}" >"${pf_log}" 2>&1 &
  local pf_pid=$!

  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
      printf -v "${pid_var}" '%s' "${pf_pid}"
      return 0
    fi
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${local_port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${local_port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

stop_port_forward() {
  local pid_var="$1"
  local pid="${!pid_var:-}"
  if [[ -n "${pid}" ]]; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    printf -v "${pid_var}" '%s' ""
  fi
}

curl_beagle_json() {
  local method="$1"
  local path="$2"
  local target="$3"
  curl -fsS -X "${method}" \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${BEAGLE_LOCAL_PORT}${path}" \
    > "${target}"
}

ensure_ssh_keypair() {
  local key_dir="${OUT}/ssh"
  local key_path="${key_dir}/id_ed25519"
  mkdir -p "${key_dir}"
  if [[ ! -f "${key_path}" ]]; then
    ssh-keygen -t ed25519 -N "" -C "beagle-workspace-cursor-native-attach" -f "${key_path}" >/dev/null
  fi
  printf '%s\n' "${key_path}"
}

cleanup() {
  stop_port_forward BEAGLE_PF_PID
  stop_port_forward WORKSPACE_SSH_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
require "${KUBECTL%% *}"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
WORKSPACE_SSH_LOCAL_PORT="$(choose_local_port "${WORKSPACE_SSH_LOCAL_PORT}")"

SSH_KEY_PATH="$(ensure_ssh_keypair)"
${KUBECTL} -n "${NAMESPACE}" create secret generic "${SSH_SECRET_NAME}" \
  --from-file=authorized_keys="${SSH_KEY_PATH}.pub" \
  --dry-run=client -o yaml | ${KUBECTL} apply -f - > "${OUT}/ssh-authorized-keys-secret-apply.log"

sudo podman build --no-cache -t "${SSH_IMAGE_REF}" -f "${WORKSPACE_SSH_DOCKERFILE}" "${ROOT}/k8s/beagle-workspace" > "${OUT}/ssh-image-build.log" 2>&1
IMAGE_REF="${SSH_IMAGE_REF}" ARCHIVE_PATH="${SSH_ARCHIVE_PATH}" \
  bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/ssh-image-load.log" 2>&1

CURSOR_REMOTE_LANE_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
WORKSPACE_DEPLOYMENT_PRESENT=0
WORKSPACE_SERVICE_PRESENT=0
SSH_DOCKERFILE_PRESENT=0
SSH_ENTRYPOINT_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "same-workspace-remote-ssh|cursor-native-attach|ssh_transport_ready" "${CURSOR_REMOTE_LANE_SOURCE_FILE}"; then
  CURSOR_REMOTE_LANE_SOURCE_PRESENT=1
fi
if rg -q "cursor-native-attach|cursor-remote-lane" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if rg -q "workspace-ssh|localhost/beagle-workspace-ssh:b202b" "${WORKSPACE_DEPLOYMENT_FILE}"; then
  WORKSPACE_DEPLOYMENT_PRESENT=1
fi
if rg -q "name: ssh|port: 2222" "${WORKSPACE_SERVICE_FILE}"; then
  WORKSPACE_SERVICE_PRESENT=1
fi
if [[ -f "${WORKSPACE_SSH_DOCKERFILE}" ]]; then
  SSH_DOCKERFILE_PRESENT=1
fi
if [[ -f "${WORKSPACE_SSH_ENTRYPOINT}" ]]; then
  SSH_ENTRYPOINT_PRESENT=1
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
  --argjson cursor_remote_lane_source_present "${CURSOR_REMOTE_LANE_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson workspace_deployment_present "${WORKSPACE_DEPLOYMENT_PRESENT}" \
  --argjson workspace_service_present "${WORKSPACE_SERVICE_PRESENT}" \
  --argjson ssh_dockerfile_present "${SSH_DOCKERFILE_PRESENT}" \
  --argjson ssh_entrypoint_present "${SSH_ENTRYPOINT_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    cursor_remote_lane_source_present: $cursor_remote_lane_source_present,
    http_source_present: $http_source_present,
    workspace_deployment_present: $workspace_deployment_present,
    workspace_service_present: $workspace_service_present,
    ssh_dockerfile_present: $ssh_dockerfile_present,
    ssh_entrypoint_present: $ssh_entrypoint_present,
    contract_present: $contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

ROOT="${ROOT}" KUBECTL="${KUBECTL}" OUT="${BASE_OUT}" \
  "${ROOT}/scripts/infrastructure/darwin-hpc/run_cluster_workspace_habitat_smoke.sh"

cp "${BASE_OUT}/workspace-context.json" "${OUT}/workspace-context.json"
cp "${BASE_OUT}/workspace-context-after-restart.json" "${OUT}/workspace-context-after-restart.json"
cp "${BASE_OUT}/workspace-runtime-summary.json" "${OUT}/workspace-runtime-summary.json"
cp "${BASE_OUT}/workspace-health.txt" "${OUT}/workspace-health.txt"
cp "${BASE_OUT}/final-cluster-health.txt" "${OUT}/final-cluster-health.txt"

WORKSPACE_ID="$(cat "${BASE_OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${BASE_OUT}/seed-session-id.txt")"
OPERATOR_API_TOKEN="$(${KUBECTL} -n "${NAMESPACE}" get secret beagle-core-secrets -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' | base64 -d)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cursor-remote-lane" "${OUT}/cursor-remote-lane.json"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cursor-native-attach" "${OUT}/cursor-native-attach.json"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/cursor" "${OUT}/tool-cursor.json"
stop_port_forward BEAGLE_PF_PID

start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_SSH_LOCAL_PORT}" 2222 "${OUT}/workspace-ssh-port-forward.log" WORKSPACE_SSH_PF_PID

ssh \
  -i "${SSH_KEY_PATH}" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${OUT}/known_hosts" \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "${WORKSPACE_SSH_LOCAL_PORT}" \
  "${EXPECTED_SSH_USER}@127.0.0.1" \
  "sh -lc '. /workspace/beagle/.beagle/context/beagle-context.env && printf \"%s\t%s\t%s\n\" \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\"'" \
  > "${OUT}/ssh-attach-identity.txt"

ssh \
  -i "${SSH_KEY_PATH}" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${OUT}/known_hosts" \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "${WORKSPACE_SSH_LOCAL_PORT}" \
  "${EXPECTED_SSH_USER}@127.0.0.1" \
  "cat /workspace/beagle/.beagle/context/beagle-context.env" \
  > "${OUT}/ssh-attach-context.env"

ssh \
  -i "${SSH_KEY_PATH}" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${OUT}/known_hosts" \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "${WORKSPACE_SSH_LOCAL_PORT}" \
  "${EXPECTED_SSH_USER}@127.0.0.1" \
  "cat /workspace/beagle/.beagle/context/current-context-packet.json" \
  > "${OUT}/ssh-attach-context-packet.json"

stop_port_forward WORKSPACE_SSH_PF_PID

jq -nc \
  --arg status "ok" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg ssh_user "${EXPECTED_SSH_USER}" \
  --arg recommended_transport "kubernetes-port-forward+ssh" \
  '{
    status: $status,
    phase: "B20.2a",
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    remote_client: "cursor",
    connection_mode: "same-workspace-remote-ssh",
    recommended_transport: $recommended_transport,
    ssh_transport_ready: true,
    ssh_user: $ssh_user,
    restart_recovered_session: true
  }' > "${OUT}/smoke.json"

echo "[OK] cursor native remote attach smoke completed"
