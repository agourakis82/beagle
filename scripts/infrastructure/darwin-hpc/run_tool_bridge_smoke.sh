#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-kubectl}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18081}"
RUN_REAL_PROVIDER="${RUN_REAL_PROVIDER:-0}"
REAL_PROVIDER="${REAL_PROVIDER:-deepseek}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/tool-bridge-smoke}"
API_TOKEN="${BEAGLE_API_TOKEN:?BEAGLE_API_TOKEN is required}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require date
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

LOCAL_PORT="$(choose_local_port)"
echo "${LOCAL_PORT}" > "${OUT}/selected-port.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout.txt"

PF_LOG="${OUT}/port-forward.log"
${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${LOCAL_PORT}:8080" >"${PF_LOG}" 2>&1 &
PF_PID=$!

cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
ready=0
for _ in $(seq 1 20); do
  if curl -fsS -H "${AUTH_HEADER}" \
    "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/health" \
    > "${OUT}/health.json.tmp"; then
    mv "${OUT}/health.json.tmp" "${OUT}/health.json"
    ready=1
    break
  fi
  if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
    echo "[FAIL] port-forward exited before health became ready" >&2
    cat "${PF_LOG}" >&2 || true
    exit 1
  fi
  sleep 1
done

if [[ "${ready}" != "1" ]]; then
  echo "[FAIL] bridge health endpoint did not become ready on local port ${LOCAL_PORT}" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
fi

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/providers" \
  > "${OUT}/providers.json"

cat > "${OUT}/execute-human-request.json" <<'EOF'
{
  "request_id": "b122b-human-smoke",
  "bridge_kind": "human_premium",
  "bridge_mode": "human_session",
  "provider": "codex_human",
  "task_type": "repo_audit",
  "payload": {
    "input": "Record a human-session bridge request without executing it."
  },
  "metadata": {
    "source": "run_tool_bridge_smoke"
  }
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/execute-human-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/execute" \
  > "${OUT}/execute-human.json"

${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
  'test -s "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl" && tail -n 20 "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl"' \
  > "${OUT}/ledger-tail.jsonl"

if [[ "${RUN_REAL_PROVIDER}" == "1" ]]; then
  cat > "${OUT}/execute-cheap-request.json" <<EOF
{
  "request_id": "b122b-cheap-smoke",
  "bridge_kind": "cheap_api",
  "bridge_mode": "api_optional",
  "provider": "${REAL_PROVIDER}",
  "task_type": "structured_extract",
  "payload": {
    "input": "Extract the core architectural decision from this sentence: Beagle must keep human premium sessions separate from cluster-executed cheap APIs."
  },
  "metadata": {
    "source": "run_tool_bridge_smoke"
  }
}
EOF

  curl -fsS -H "${AUTH_HEADER}" -H 'Content-Type: application/json' \
    --data @"${OUT}/execute-cheap-request.json" \
    "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/execute" \
    > "${OUT}/execute-cheap.json"

  ${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
    'tail -n 40 "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl"' \
    > "${OUT}/ledger-tail-after-cheap.jsonl"
fi

echo "[OK] tool bridge smoke artifacts written to ${OUT}"
