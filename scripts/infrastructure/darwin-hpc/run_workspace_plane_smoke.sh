#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-kubectl}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18084}"
PROFILE_ID="${PROFILE_ID:-cpu-short-v1}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/workspace-plane-smoke}"
API_TOKEN="${BEAGLE_API_TOKEN:?BEAGLE_API_TOKEN is required}"
WORKSPACE_ID="${WORKSPACE_ID:-b124-$(date +%m%d%H%M%S)}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require jq
require ss
require "${KUBECTL%% *}"

mkdir -p "${OUT}"

choose_local_port() {
  local port="${LOCAL_PORT}"
  local max_tries=20
  local try=0

  while (( try < max_tries )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    try=$((try + 1))
  done

  echo "[FAIL] unable to find a free local port starting at ${LOCAL_PORT}" >&2
  exit 1
}

start_port_forward() {
  local port="$1"
  local pf_log="$2"

  : > "${pf_log}"
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${port}:8080" >"${pf_log}" 2>&1 &
  PF_PID=$!

  for _ in $(seq 1 20); do
    if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

wait_for_health() {
  local port="$1"
  local target="$2"
  local ready=0

  for _ in $(seq 1 20); do
    if curl -fsS -H "${AUTH_HEADER}" "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      ready=1
      break
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before Beagle health became ready" >&2
      cat "${PF_LOG}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  if [[ "${ready}" != "1" ]]; then
    echo "[FAIL] Beagle health endpoint did not become ready on local port ${port}" >&2
    cat "${PF_LOG}" >&2 || true
    exit 1
  fi
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

LOCAL_PORT="$(choose_local_port)"
echo "${LOCAL_PORT}" > "${OUT}/selected-port.txt"
echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-before.json"

cat > "${OUT}/pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${PROFILE_ID}"
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/pilot-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/pilot/execute" \
  > "${OUT}/pilot.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-before-restart.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

PF_LOG="${OUT}/port-forward-after.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-after-restart.json"

{
  echo "captured_at=$(date -Iseconds)"
  echo
  echo "## beagle"
  ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
  echo
  echo "## darwin-gateway"
  ${KUBECTL} -n darwin-platform get deploy,svc,pods -l app.kubernetes.io/name=darwin-hpc-gateway -o wide || true
  echo
  echo "## nodes"
  ${KUBECTL} get nodes -o wide || true
  echo
  if command -v scontrol >/dev/null 2>&1; then
    echo "## scontrol-ping"
    scontrol ping || true
    echo
  fi
  if command -v sinfo >/dev/null 2>&1; then
    echo "## sinfo"
    sinfo -N -l || true
    echo
  fi
} > "${OUT}/final-cluster-health.txt"

echo "[OK] workspace plane smoke artifacts written to ${OUT}"
