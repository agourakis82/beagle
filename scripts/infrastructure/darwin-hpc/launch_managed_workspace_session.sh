#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
CLIENT="${CLIENT:-cursor}"
OUT="${OUT:-}"
JSON_OUT="${JSON_OUT:-}"
WORKSPACE_LAUNCH_RESUME_JSON="${WORKSPACE_LAUNCH_RESUME_JSON:-}"
CONTEXT_ENV_OUT="${CONTEXT_ENV_OUT:-}"
CONTEXT_PACKET_OUT="${CONTEXT_PACKET_OUT:-}"
REMOTE_COMMAND="${REMOTE_COMMAND:-}"
REMOTE_OUTPUT="${REMOTE_OUTPUT:-}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18291}"
INSTALLER_SCRIPT="${INSTALLER_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/install_managed_workspace_attach.sh}"

usage() {
  cat <<'EOF'
Usage:
  launch_managed_workspace_session.sh [--workstream ID] [--client cursor|ssh|browser]
                                      [--out DIR] [--json-out FILE]
                                      [--context-env-out FILE] [--context-packet-out FILE]
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
    --context-env-out)
      CONTEXT_ENV_OUT="$2"
      shift 2
      ;;
    --context-packet-out)
      CONTEXT_PACKET_OUT="$2"
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

if [[ -z "${OUT}" ]]; then
  OUT="${HOME}/.beagle/managed-attach/${WORKSTREAM_ID}/launch-resume"
fi

if [[ -z "${JSON_OUT}" ]]; then
  JSON_OUT="${OUT}/launch-summary.json"
fi

if [[ -z "${WORKSPACE_LAUNCH_RESUME_JSON}" ]]; then
  WORKSPACE_LAUNCH_RESUME_JSON="${OUT}/workspace-launch-resume.json"
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

cleanup() {
  stop_port_forward BEAGLE_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(ensure_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-launch-resume" \
  > "${WORKSPACE_LAUNCH_RESUME_JSON}"

CONTEXT_ENV_PATH="$(jq -r '.launch.launch_metadata.workspace_habitat_env_path // .launch.workspace_habitat_env_path' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
CONTEXT_PACKET_PATH="$(jq -r '.launch.context_packet_path' "${WORKSPACE_LAUNCH_RESUME_JSON}")"

if [[ -n "${CONTEXT_ENV_OUT}" ]]; then
  curl -fsS \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${BEAGLE_LOCAL_PORT}${CONTEXT_ENV_PATH}" \
    > "${CONTEXT_ENV_OUT}"
fi

if [[ -n "${CONTEXT_PACKET_OUT}" ]]; then
  curl -fsS \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${BEAGLE_LOCAL_PORT}${CONTEXT_PACKET_PATH}" \
    > "${CONTEXT_PACKET_OUT}"
fi
stop_port_forward BEAGLE_PF_PID

WORKSPACE_ID="$(jq -r '.launch.workspace_id' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
SESSION_ID="$(jq -r '.launch.session_id' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
LAUNCH_METHOD="$(jq -r '.launch.launch_metadata.launch_method' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
LAUNCH_STATE="$(jq -r '.launch.launch_metadata.launch_state' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
ATTACH_METHOD="$(jq -r '.launch.launch_metadata.attach_method' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
MANAGED_ATTACH_STATE="$(jq -r '.launch.launch_metadata.managed_attach_state' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
ATTACH_HOST_ALIAS="$(jq -r '.launch.launch_metadata.stable_launch_alias' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
BROWSER_URL="$(jq -r '.launch.browser_url' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
RECOMMENDED_CLIENT="$(jq -r '.launch.launch_metadata.recommended_client' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
CURSOR_READY="$(jq -r '.launch.launch_metadata.cursor_managed_attach_ready' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
BROWSER_READY="$(jq -r '.launch.launch_metadata.browser_fallback_ready' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
CURSOR_COMMAND="$(jq -r '.launch.helper_snippets.cursor_resume_command' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
BROWSER_COMMAND="$(jq -r '.launch.helper_snippets.browser_resume_command' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
SSH_COMMAND_HINT="$(jq -r '.launch.helper_snippets.ssh_resume_command' "${WORKSPACE_LAUNCH_RESUME_JSON}")"
HELPER_COMMAND="${CURSOR_COMMAND}"

SSH_COMMAND=""
if [[ "${CLIENT}" == "cursor" || "${CLIENT}" == "ssh" ]]; then
  ATTACH_OUT="${OUT}/managed-attach"
  ATTACH_SUMMARY_JSON="${OUT}/managed-attach-install.json"
  INSTALLER_ARGS=(
    --workstream "${WORKSTREAM_ID}"
    --client "${CLIENT}"
    --out "${ATTACH_OUT}"
    --json-out "${ATTACH_SUMMARY_JSON}"
  )
  mkdir -p "${ATTACH_OUT}"
  if [[ -n "${REMOTE_COMMAND}" ]]; then
    INSTALLER_ARGS+=(--remote-command "${REMOTE_COMMAND}")
  fi
  if [[ -n "${REMOTE_OUTPUT}" ]]; then
    INSTALLER_ARGS+=(--remote-output "${REMOTE_OUTPUT}")
  fi
  KUBECTL="${KUBECTL}" bash "${INSTALLER_SCRIPT}" "${INSTALLER_ARGS[@]}"
  SSH_COMMAND="$(jq -r '.ssh_command // empty' "${ATTACH_SUMMARY_JSON}")"
elif [[ "${CLIENT}" == "browser" ]]; then
  HELPER_COMMAND="${BROWSER_COMMAND}"
  SSH_COMMAND=""
  if [[ -n "${REMOTE_COMMAND}" || -n "${REMOTE_OUTPUT}" ]]; then
    echo "[FAIL] browser launch does not support remote commands" >&2
    exit 1
  fi
else
  echo "[FAIL] unsupported client: ${CLIENT}" >&2
  exit 1
fi

jq -nc \
  --arg status "ok" \
  --arg phase "B20.5" \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg client "${CLIENT}" \
  --arg launch_method "${LAUNCH_METHOD}" \
  --arg launch_state "${LAUNCH_STATE}" \
  --arg attach_method "${ATTACH_METHOD}" \
  --arg managed_attach_state "${MANAGED_ATTACH_STATE}" \
  --arg attach_host_alias "${ATTACH_HOST_ALIAS}" \
  --arg browser_url "${BROWSER_URL}" \
  --arg recommended_client "${RECOMMENDED_CLIENT}" \
  --arg helper_command "${HELPER_COMMAND}" \
  --arg ssh_command "${SSH_COMMAND}" \
  --arg ssh_resume_command "${SSH_COMMAND_HINT}" \
  --arg workspace_launch_resume_json "${WORKSPACE_LAUNCH_RESUME_JSON}" \
  --argjson browser_fallback_ready "${BROWSER_READY}" \
  --argjson cursor_resume_ready "${CURSOR_READY}" \
  '{
    status: $status,
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    client: $client,
    launch_method: $launch_method,
    launch_state: $launch_state,
    attach_method: $attach_method,
    managed_attach_state: $managed_attach_state,
    attach_host_alias: $attach_host_alias,
    browser_url: $browser_url,
    recommended_client: $recommended_client,
    helper_command: $helper_command,
    ssh_command: (if $ssh_command == "" then null else $ssh_command end),
    ssh_resume_command: $ssh_resume_command,
    browser_fallback_ready: $browser_fallback_ready,
    cursor_resume_ready: $cursor_resume_ready,
    workspace_launch_resume_json: $workspace_launch_resume_json
  }' > "${JSON_OUT}"
