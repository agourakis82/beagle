#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
SSH_SECRET_NAME="${SSH_SECRET_NAME:-}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
CLIENT="${CLIENT:-cursor}"
OUT="${OUT:-}"
JSON_OUT="${JSON_OUT:-}"
WORKSPACE_ATTACH_JSON="${WORKSPACE_ATTACH_JSON:-}"
REMOTE_COMMAND="${REMOTE_COMMAND:-}"
REMOTE_OUTPUT="${REMOTE_OUTPUT:-}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18291}"
STATE_DIR="${STATE_DIR:-}"

usage() {
  cat <<'EOF'
Usage:
  install_managed_workspace_attach.sh [--workstream ID] [--client cursor|ssh|browser]
                                      [--out DIR] [--json-out FILE]
                                      [--remote-command CMD] [--remote-output FILE]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workstream)
      WORKSTREAM_ID="$2"
      shift 2
      ;;
    --client)
      CLIENT="$2"
      shift 2
      ;;
    --out)
      OUT="$2"
      shift 2
      ;;
    --json-out)
      JSON_OUT="$2"
      shift 2
      ;;
    --remote-command)
      REMOTE_COMMAND="$2"
      shift 2
      ;;
    --remote-output)
      REMOTE_OUTPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[FAIL] unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${STATE_DIR}" ]]; then
  STATE_DIR="${HOME}/.beagle/managed-attach/${WORKSTREAM_ID}"
fi

if [[ -z "${OUT}" ]]; then
  OUT="${STATE_DIR}"
fi

if [[ -z "${JSON_OUT}" ]]; then
  JSON_OUT="${OUT}/managed-attach-summary.json"
fi

if [[ -z "${WORKSPACE_ATTACH_JSON}" ]]; then
  WORKSPACE_ATTACH_JSON="${OUT}/workspace-attach.json"
fi

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require base64
require curl
require jq
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

  if [[ -f /etc/kubernetes/admin.conf ]]; then
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
  # shellcheck disable=SC2086
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

wait_for_ssh_attach() {
  local ssh_config="$1"
  local attach_alias="$2"

  for _ in $(seq 1 30); do
    if ssh \
      -F "${ssh_config}" \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      "${attach_alias}" \
      "true" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done

  echo "[FAIL] managed SSH attach did not become ready for host ${attach_alias}" >&2
  exit 1
}

ensure_operator_api_token() {
  local encoded_token=""
  # shellcheck disable=SC2086
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    # shellcheck disable=SC2086
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token in secret ${SECRET_NAME}" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

ensure_ssh_keypair() {
  local key_dir="${STATE_DIR}/ssh"
  local key_path="${key_dir}/id_ed25519"
  mkdir -p "${key_dir}"
  if [[ ! -f "${key_path}" ]]; then
    ssh-keygen -t ed25519 -N "" -C "beagle-managed-attach-${WORKSTREAM_ID}" -f "${key_path}" >/dev/null
  fi
  printf '%s\n' "${key_path}"
}

cleanup() {
  stop_port_forward BEAGLE_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
mkdir -p "${STATE_DIR}"
SSH_KEY_PATH="$(ensure_ssh_keypair)"
KNOWN_HOSTS_PATH="${STATE_DIR}/known_hosts"
SSH_CONFIG_PATH="${STATE_DIR}/ssh_config"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
PROXY_SCRIPT_PATH="${ROOT}/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh"

OPERATOR_API_TOKEN="$(ensure_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/managed-attach" \
  > "${WORKSPACE_ATTACH_JSON}"
stop_port_forward BEAGLE_PF_PID

WORKSPACE_ID="$(jq -r '.attach.workspace_id' "${WORKSPACE_ATTACH_JSON}")"
SESSION_ID="$(jq -r '.attach.session_id' "${WORKSPACE_ATTACH_JSON}")"
ATTACH_ALIAS="$(jq -r '.attach.attach_metadata.stable_attach_host_alias' "${WORKSPACE_ATTACH_JSON}")"
ATTACH_METHOD="$(jq -r '.attach.attach_metadata.attach_method' "${WORKSPACE_ATTACH_JSON}")"
MANAGED_ATTACH_STATE="$(jq -r '.attach.attach_metadata.managed_attach_state' "${WORKSPACE_ATTACH_JSON}")"
RECOMMENDED_CLIENT="$(jq -r '.attach.attach_metadata.recommended_client' "${WORKSPACE_ATTACH_JSON}")"
SSH_USER="$(jq -r '.attach.attach_metadata.ssh_user // empty' "${WORKSPACE_ATTACH_JSON}")"
SSH_PORT="$(jq -r '.attach.attach_metadata.ssh_port // .attach.attach_metadata.suggested_local_ssh_port // empty' "${WORKSPACE_ATTACH_JSON}")"
BROWSER_URL="$(jq -r '.attach.attach_metadata.browser_url // .attach.attach_metadata.browser_internal_url' "${WORKSPACE_ATTACH_JSON}")"
REPO_ROOT="$(jq -r '.attach.attach_metadata.repo_root' "${WORKSPACE_ATTACH_JSON}")"
ATTACH_TRANSPORT="$(jq -r '.attach.attach_metadata.attach_transport' "${WORKSPACE_ATTACH_JSON}")"
HELPER_COMMAND="$(jq -r '.attach.helper_snippets.helper_command' "${WORKSPACE_ATTACH_JSON}")"
SSH_CONFIG_TEMPLATE="$(jq -r '.attach.helper_snippets.ssh_config_snippet' "${WORKSPACE_ATTACH_JSON}")"
WORKSPACE_SERVICE_NAME="$(jq -r '.attach.attach_metadata.workspace_service_name' "${WORKSPACE_ATTACH_JSON}")"

if [[ -z "${SSH_SECRET_NAME}" ]]; then
  SSH_SECRET_NAME="${WORKSPACE_SERVICE_NAME}-ssh-authorized-keys"
fi

# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" create secret generic "${SSH_SECRET_NAME}" \
  --from-file=authorized_keys="${SSH_KEY_PATH}.pub" \
  --dry-run=client -o yaml | ${KUBECTL} apply -f - >/dev/null

if [[ "${SSH_CONFIG_TEMPLATE}" == "null" || -z "${SSH_CONFIG_TEMPLATE}" ]]; then
  echo "[FAIL] managed attach response did not include an SSH config snippet" >&2
  exit 1
fi

printf '%s' "${SSH_CONFIG_TEMPLATE}" \
  | sed "s#__BEAGLE_REPO_ROOT__#${ROOT}#g" \
  > "${SSH_CONFIG_PATH}"

touch "${KNOWN_HOSTS_PATH}"
if [[ -n "${SSH_PORT}" ]]; then
  ssh-keygen -f "${KNOWN_HOSTS_PATH}" -R "[127.0.0.1]:${SSH_PORT}" >/dev/null 2>&1 || true
fi

wait_for_ssh_attach "${SSH_CONFIG_PATH}" "${ATTACH_ALIAS}"

if [[ -n "${REMOTE_COMMAND}" && -n "${REMOTE_OUTPUT}" ]]; then
  ssh -F "${SSH_CONFIG_PATH}" "${ATTACH_ALIAS}" "${REMOTE_COMMAND}" > "${REMOTE_OUTPUT}"
elif [[ -n "${REMOTE_COMMAND}" || -n "${REMOTE_OUTPUT}" ]]; then
  echo "[FAIL] --remote-command and --remote-output must be provided together" >&2
  exit 1
fi

SSH_COMMAND="ssh -F ${SSH_CONFIG_PATH} ${ATTACH_ALIAS}"

jq -nc \
  --arg status "ok" \
  --arg phase "B20.4" \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg client "${CLIENT}" \
  --arg recommended_client "${RECOMMENDED_CLIENT}" \
  --arg attach_host_alias "${ATTACH_ALIAS}" \
  --arg attach_method "${ATTACH_METHOD}" \
  --arg managed_attach_state "${MANAGED_ATTACH_STATE}" \
  --arg attach_transport "${ATTACH_TRANSPORT}" \
  --arg helper_command "${HELPER_COMMAND}" \
  --arg ssh_config_path "${SSH_CONFIG_PATH}" \
  --arg ssh_command "${SSH_COMMAND}" \
  --arg proxy_script_path "${PROXY_SCRIPT_PATH}" \
  --arg browser_url "${BROWSER_URL}" \
  --arg repo_root "${REPO_ROOT}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    client: $client,
    recommended_client: $recommended_client,
    attach_host_alias: $attach_host_alias,
    attach_method: $attach_method,
    managed_attach_state: $managed_attach_state,
    attach_transport: $attach_transport,
    helper_command: $helper_command,
    ssh_config_path: $ssh_config_path,
    ssh_command: $ssh_command,
    proxy_script_path: $proxy_script_path,
    browser_url: $browser_url,
    repo_root: $repo_root
  }' > "${JSON_OUT}"
