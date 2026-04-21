#!/usr/bin/env bash
set -euo pipefail

KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
DEPLOYMENT="${DEPLOYMENT:-beagle-workspace}"
CONTAINER="${CONTAINER:-workspace-ssh}"
SERVICE="${SERVICE:-}"
LOCAL_PORT="${LOCAL_PORT:-}"
REMOTE_PORT="${REMOTE_PORT:-}"
STATE_DIR="${STATE_DIR:-}"
TARGET_HOST="${TARGET_HOST:-127.0.0.1}"
TARGET_PORT="${TARGET_PORT:-2222}"

usage() {
  cat <<'EOF'
Usage:
  workspace_exec_proxy.sh [--namespace NAME] [--deployment NAME] [--container NAME]
                          [--target-host HOST] [--target-port PORT]
  workspace_exec_proxy.sh [--namespace NAME] [--service NAME] [--local-port PORT]
                          [--remote-port PORT] [--state-dir DIR]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --deployment)
      DEPLOYMENT="$2"
      shift 2
      ;;
    --container)
      CONTAINER="$2"
      shift 2
      ;;
    --service)
      SERVICE="$2"
      shift 2
      ;;
    --local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    --remote-port)
      REMOTE_PORT="$2"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="$2"
      shift 2
      ;;
    --target-host)
      TARGET_HOST="$2"
      shift 2
      ;;
    --target-port)
      TARGET_PORT="$2"
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

KUBECTL="$(resolve_kubectl)"

if [[ -n "${SERVICE}" ]]; then
  if [[ -z "${LOCAL_PORT}" || -z "${REMOTE_PORT}" || -z "${STATE_DIR}" ]]; then
    echo "[FAIL] managed proxy mode requires --service, --local-port, --remote-port, and --state-dir" >&2
    exit 1
  fi

  command -v nc >/dev/null 2>&1 || {
    echo "[FAIL] missing command: nc" >&2
    exit 1
  }
  command -v ss >/dev/null 2>&1 || {
    echo "[FAIL] missing command: ss" >&2
    exit 1
  }

  mkdir -p "${STATE_DIR}"
  PF_PID_FILE="${STATE_DIR}/port-forward-${SERVICE}-${LOCAL_PORT}.pid"
  PF_LOG_FILE="${STATE_DIR}/port-forward-${SERVICE}-${LOCAL_PORT}.log"

  port_ready() {
    ss -ltn "( sport = :${LOCAL_PORT} )" | tail -n +2 | grep -q .
  }

  cleanup_conflicting_port_forwards() {
    command -v pgrep >/dev/null 2>&1 || return 0

    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      pid="${line%% *}"
      [[ -n "${pid}" ]] || continue

      if [[ -f "${PF_PID_FILE}" ]] && [[ "$(cat "${PF_PID_FILE}" 2>/dev/null)" == "${pid}" ]]; then
        continue
      fi

      if [[ "${line}" == *"kubectl"* && "${line}" == *"port-forward"* && "${line}" == *"${LOCAL_PORT}:"* ]]; then
        kill "${pid}" >/dev/null 2>&1 || true
      fi
    done < <(pgrep -af "kubectl.*port-forward.*${LOCAL_PORT}:" || true)
  }

  if port_ready; then
    if [[ -f "${PF_PID_FILE}" ]]; then
      EXISTING_PID="$(cat "${PF_PID_FILE}")"
      if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" >/dev/null 2>&1; then
        exec nc 127.0.0.1 "${LOCAL_PORT}"
      fi
    fi

    cleanup_conflicting_port_forwards

    for _ in $(seq 1 10); do
      if ! port_ready; then
        break
      fi
      sleep 1
    done

    if port_ready; then
      echo "[FAIL] local port ${LOCAL_PORT} is already occupied by an unrelated listener" >&2
      exit 1
    fi
  fi

  if [[ -f "${PF_PID_FILE}" ]]; then
    EXISTING_PID="$(cat "${PF_PID_FILE}")"
    if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" >/dev/null 2>&1 && port_ready; then
      exec nc 127.0.0.1 "${LOCAL_PORT}"
    fi
    kill "${EXISTING_PID:-}" >/dev/null 2>&1 || true
    rm -f "${PF_PID_FILE}"
  fi

  : > "${PF_LOG_FILE}"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE}" "${LOCAL_PORT}:${REMOTE_PORT}" >"${PF_LOG_FILE}" 2>&1 &
  PF_PID=$!
  echo "${PF_PID}" > "${PF_PID_FILE}"

  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${PF_LOG_FILE}" 2>/dev/null && port_ready; then
      exec nc 127.0.0.1 "${LOCAL_PORT}"
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] managed port-forward exited before attach became ready" >&2
      cat "${PF_LOG_FILE}" >&2 || true
      rm -f "${PF_PID_FILE}"
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] managed port-forward did not become ready for ${SERVICE}:${REMOTE_PORT}" >&2
  cat "${PF_LOG_FILE}" >&2 || true
  rm -f "${PF_PID_FILE}"
  exit 1
fi

# shellcheck disable=SC2086
exec ${KUBECTL} -n "${NAMESPACE}" exec -i deployment/"${DEPLOYMENT}" -c "${CONTAINER}" -- \
  nc "${TARGET_HOST}" "${TARGET_PORT}"
