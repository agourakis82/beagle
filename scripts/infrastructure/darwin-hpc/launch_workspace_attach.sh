#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
SSH_SECRET_NAME="${SSH_SECRET_NAME:-beagle-workspace-ssh-authorized-keys}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
CLIENT="${CLIENT:-cursor}"
OUT="${OUT:-}"
JSON_OUT="${JSON_OUT:-}"
WORKSPACE_ATTACH_JSON="${WORKSPACE_ATTACH_JSON:-}"
REMOTE_COMMAND="${REMOTE_COMMAND:-}"
REMOTE_OUTPUT="${REMOTE_OUTPUT:-}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18261}"
HOLD_OPEN="${HOLD_OPEN:-}"

usage() {
  cat <<'EOF'
Usage:
  launch_workspace_attach.sh [--workstream ID] [--client cursor|ssh|browser]
                            [--out DIR] [--json-out FILE]
                            [--remote-command CMD] [--remote-output FILE]
                            [--hold-open]

Examples:
  scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh --workstream beagle-darwin-hpc-governance --client cursor
  scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh --workstream beagle-darwin-hpc-governance --client ssh --remote-command 'hostname'
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
    --hold-open)
      HOLD_OPEN="true"
      shift
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

if [[ -z "${OUT}" ]]; then
  OUT="${HOME}/.beagle/workspace-attach/${WORKSTREAM_ID}"
fi

if [[ -z "${JSON_OUT}" ]]; then
  JSON_OUT="${OUT}/attach-summary.json"
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

  for _ in $(seq 1 20); do
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

  echo "[FAIL] workspace SSH attach did not become ready for host ${attach_alias}" >&2
  exit 1
}

ensure_operator_api_token() {
  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token in secret ${SECRET_NAME}" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

ensure_ssh_keypair() {
  local key_dir="${OUT}/ssh"
  local key_path="${key_dir}/id_ed25519"
  mkdir -p "${key_dir}"
  if [[ ! -f "${key_path}" ]]; then
    ssh-keygen -t ed25519 -N "" -C "beagle-workspace-attach-${WORKSTREAM_ID}" -f "${key_path}" >/dev/null
  fi
  printf '%s\n' "${key_path}"
}

cleanup() {
  stop_port_forward BEAGLE_PF_PID
  stop_port_forward WORKSPACE_BROWSER_PF_PID
  stop_port_forward WORKSPACE_SSH_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
SSH_KEY_PATH="$(ensure_ssh_keypair)"
KNOWN_HOSTS_PATH="${OUT}/known_hosts"
SSH_CONFIG_PATH="${OUT}/ssh_config"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"

${KUBECTL} -n "${NAMESPACE}" create secret generic "${SSH_SECRET_NAME}" \
  --from-file=authorized_keys="${SSH_KEY_PATH}.pub" \
  --dry-run=client -o yaml | ${KUBECTL} apply -f - >/dev/null

OPERATOR_API_TOKEN="$(ensure_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-attach" \
  > "${WORKSPACE_ATTACH_JSON}"
stop_port_forward BEAGLE_PF_PID

WORKSPACE_ID="$(jq -r '.attach.workspace_id' "${WORKSPACE_ATTACH_JSON}")"
SESSION_ID="$(jq -r '.attach.session_id' "${WORKSPACE_ATTACH_JSON}")"
ATTACH_ALIAS="$(jq -r '.attach.attach_metadata.stable_attach_host_alias' "${WORKSPACE_ATTACH_JSON}")"
SSH_USER="$(jq -r '.attach.attach_metadata.ssh_user // empty' "${WORKSPACE_ATTACH_JSON}")"
SSH_SERVICE_PORT="$(jq -r '.attach.attach_metadata.ssh_service_port // empty' "${WORKSPACE_ATTACH_JSON}")"
SUGGESTED_BROWSER_PORT="$(jq -r '.attach.attach_metadata.suggested_local_browser_port' "${WORKSPACE_ATTACH_JSON}")"
SUGGESTED_SSH_PORT="$(jq -r '.attach.attach_metadata.suggested_local_ssh_port // empty' "${WORKSPACE_ATTACH_JSON}")"
WORKSPACE_SERVICE_NAME="$(jq -r '.attach.attach_metadata.workspace_service_name' "${WORKSPACE_ATTACH_JSON}")"
WORKSPACE_BROWSER_INTERNAL_URL="$(jq -r '.attach.attach_metadata.browser_internal_url' "${WORKSPACE_ATTACH_JSON}")"
REPO_ROOT="$(jq -r '.attach.attach_metadata.repo_root' "${WORKSPACE_ATTACH_JSON}")"
HELPER_COMMAND="$(jq -r '.attach.helper_snippets.helper_command' "${WORKSPACE_ATTACH_JSON}")"
CURSOR_REMOTE_HINT="$(jq -r '.attach.helper_snippets.cursor_remote_hint' "${WORKSPACE_ATTACH_JSON}")"
ATTACH_METHOD="$(jq -r '.attach.attach_metadata.attach_method' "${WORKSPACE_ATTACH_JSON}")"

BROWSER_LOCAL_PORT="$(choose_local_port "${SUGGESTED_BROWSER_PORT}")"
if [[ -n "${SUGGESTED_SSH_PORT}" ]]; then
  SSH_LOCAL_PORT="$(choose_local_port "${SUGGESTED_SSH_PORT}")"
else
  SSH_LOCAL_PORT=""
fi

if [[ "${CLIENT}" == "browser" || "${CLIENT}" == "cursor" ]]; then
  start_port_forward "${WORKSPACE_SERVICE_NAME}" "${BROWSER_LOCAL_PORT}" 8080 "${OUT}/workspace-browser-port-forward.log" WORKSPACE_BROWSER_PF_PID
fi

if [[ "${CLIENT}" == "ssh" || "${CLIENT}" == "cursor" || -n "${REMOTE_COMMAND}" ]]; then
  if [[ -z "${SSH_LOCAL_PORT}" || -z "${SSH_SERVICE_PORT}" || -z "${SSH_USER}" ]]; then
    echo "[FAIL] workspace attach metadata does not expose SSH attach" >&2
    exit 1
  fi
  start_port_forward "${WORKSPACE_SERVICE_NAME}" "${SSH_LOCAL_PORT}" "${SSH_SERVICE_PORT}" "${OUT}/workspace-ssh-port-forward.log" WORKSPACE_SSH_PF_PID
fi

cat > "${SSH_CONFIG_PATH}" <<EOF
Host ${ATTACH_ALIAS}
  HostName 127.0.0.1
  Port ${SSH_LOCAL_PORT}
  User ${SSH_USER}
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile ${KNOWN_HOSTS_PATH}
EOF

SSH_COMMAND="ssh -F ${SSH_CONFIG_PATH} ${ATTACH_ALIAS}"
if [[ -n "${SSH_LOCAL_PORT}" ]]; then
  wait_for_ssh_attach "${SSH_CONFIG_PATH}" "${ATTACH_ALIAS}"
fi
if [[ -n "${WORKSPACE_BROWSER_INTERNAL_URL}" && "${CLIENT}" != "ssh" ]]; then
  BROWSER_LOCAL_URL="http://127.0.0.1:${BROWSER_LOCAL_PORT}"
else
  BROWSER_LOCAL_URL=""
fi

jq -nc \
  --arg status "ok" \
  --arg phase "B20.3" \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg client "${CLIENT}" \
  --arg attach_host_alias "${ATTACH_ALIAS}" \
  --arg attach_method "${ATTACH_METHOD}" \
  --arg helper_command "${HELPER_COMMAND}" \
  --arg cursor_remote_hint "${CURSOR_REMOTE_HINT}" \
  --arg ssh_config_path "${SSH_CONFIG_PATH}" \
  --arg ssh_command "${SSH_COMMAND}" \
  --arg browser_local_url "${BROWSER_LOCAL_URL}" \
  --arg workspace_attach_json "${WORKSPACE_ATTACH_JSON}" \
  --arg repo_root "${REPO_ROOT}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    client: $client,
    attach_host_alias: $attach_host_alias,
    attach_method: $attach_method,
    helper_command: $helper_command,
    cursor_remote_hint: $cursor_remote_hint,
    ssh_config_path: $ssh_config_path,
    ssh_command: $ssh_command,
    browser_local_url: (if $browser_local_url == "" then null else $browser_local_url end),
    workspace_attach_json: $workspace_attach_json,
    repo_root: $repo_root
  }' > "${JSON_OUT}"

if [[ -n "${REMOTE_COMMAND}" ]]; then
  if [[ -n "${REMOTE_OUTPUT}" ]]; then
    ssh -F "${SSH_CONFIG_PATH}" "${ATTACH_ALIAS}" "${REMOTE_COMMAND}" > "${REMOTE_OUTPUT}"
  else
    ssh -F "${SSH_CONFIG_PATH}" "${ATTACH_ALIAS}" "${REMOTE_COMMAND}"
  fi
  exit 0
fi

case "${CLIENT}" in
  ssh)
    exec ssh -F "${SSH_CONFIG_PATH}" "${ATTACH_ALIAS}"
    ;;
  cursor|browser)
    echo "[OK] attach plane ready"
    echo "workstream: ${WORKSTREAM_ID}"
    echo "workspace: ${WORKSPACE_ID}"
    echo "session: ${SESSION_ID}"
    echo "attach host alias: ${ATTACH_ALIAS}"
    echo "ssh config: ${SSH_CONFIG_PATH}"
    if [[ -n "${BROWSER_LOCAL_URL}" ]]; then
      echo "browser url: ${BROWSER_LOCAL_URL}"
    fi
    if [[ "${CLIENT}" == "cursor" ]]; then
      echo "cursor hint: ${CURSOR_REMOTE_HINT}"
    fi
    echo "press Ctrl-C to stop the attach plane"
    if [[ -n "${HOLD_OPEN}" || "${CLIENT}" != "ssh" ]]; then
      while true; do sleep 60; done
    fi
    ;;
  *)
    echo "[FAIL] unsupported client: ${CLIENT}" >&2
    exit 1
    ;;
esac
