#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18090}"
PROFILE_ID="${PROFILE_ID:-cpu-short-v1}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/canonical-dev-cutover-smoke}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:?BEAGLE_OPERATOR_API_TOKEN or BEAGLE_API_TOKEN is required}}"
WORKSPACE_ID="${WORKSPACE_ID:-b131-$(date +%m%d%H%M%S)}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)}"
RUN_LABEL="${RUN_LABEL:-b131-$(date +%m%d%H%M%S)-dev-cutover}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
BRIDGE_PROVIDER="${BRIDGE_PROVIDER:-deepseek}"
BRIDGE_MODEL="${BRIDGE_MODEL:-deepseek-chat}"
BRIDGE_REQUEST_ID="${BRIDGE_REQUEST_ID:-b131-dev-cutover-$(date +%m%d%H%M%S)}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require jq
require ss
require git

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

KUBECTL="$(resolve_kubectl)"
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

  for _ in $(seq 1 20); do
    if curl -fsS \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" \
      > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before Beagle health became ready" >&2
      cat "${PF_LOG}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] Beagle health endpoint did not become ready on local port ${port}" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
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

curl_json() {
  local method="$1"
  local path="$2"
  local target="$3"
  local body="${4:-}"

  if [[ -n "${body}" ]]; then
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      -H 'Content-Type: application/json' \
      --data @"${body}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  fi
}

LOCAL_PORT="$(choose_local_port)"
PF_LOG="${OUT}/port-forward.log"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${LOCAL_PORT}" > "${OUT}/selected-port.txt"
echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_REPO}" > "${OUT}/expected-repo.txt"
echo "${EXPECTED_BRANCH}" > "${OUT}/expected-branch.txt"
echo "${RUN_LABEL}" > "${OUT}/run-label.txt"
echo "${BRIDGE_REQUEST_ID}" > "${OUT}/bridge-request-id.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"

curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-before.json"
curl_json GET "/api/darwin/hpc/control" "${OUT}/control-before.json"
curl_json GET "/api/darwin/hpc/results?profile_id=${PROFILE_ID}&state=COMPLETED" "${OUT}/results-before.json"
curl_json GET "/api/darwin/bridge/health" "${OUT}/bridge-health.json"
curl_json GET "/api/darwin/bridge/providers" "${OUT}/bridge-providers.json"

cat > "${OUT}/bridge-execute-request.json" <<EOF
{
  "request_id": "${BRIDGE_REQUEST_ID}",
  "bridge_kind": "cheap_api",
  "bridge_mode": "api_optional",
  "provider": "${BRIDGE_PROVIDER}",
  "model": "${BRIDGE_MODEL}",
  "task_type": "canonical_dev_cutover_note",
  "payload": {
    "input": "Repo=${EXPECTED_REPO}. Branch=${EXPECTED_BRANCH}. Workspace=${WORKSPACE_ID}. Summarize a clean canonical dev-plane cutover loop for Beagle in 3 short bullets: bootstrap session, run one live workflow, recover after restart."
  },
  "metadata": {
    "source": "run_canonical_dev_cutover_smoke",
    "workspace_id": "${WORKSPACE_ID}",
    "repo": "${EXPECTED_REPO}",
    "branch": "${EXPECTED_BRANCH}"
  }
}
EOF

curl_json POST "/api/darwin/bridge/execute" "${OUT}/bridge-execute.json" "${OUT}/bridge-execute-request.json"

${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
  'test -s "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl" && tail -n 40 "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl"' \
  > "${OUT}/bridge-ledger-tail.jsonl"

cat > "${OUT}/pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${PROFILE_ID}",
  "run_label": "${RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF

curl_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/pilot.json" "${OUT}/pilot-request.json"

PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/pilot.json")"
if [[ -z "${PUBLISHED_RESULT_JOB_ID}" || "${PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${PUBLISHED_RESULT_JOB_ID}" > "${OUT}/published-result-job-id.txt"

curl_json GET "/api/darwin/hpc/results/${PUBLISHED_RESULT_JOB_ID}" "${OUT}/result-after.json"
curl_json GET "/api/darwin/hpc/results/${PUBLISHED_RESULT_JOB_ID}/manifest" "${OUT}/result-manifest-after.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-before-restart.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

PF_LOG="${OUT}/port-forward-after.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after.json"

curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"

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

echo "[OK] canonical dev cutover smoke artifacts written to ${OUT}"
