#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18098}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/minimax-bridge-smoke}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
REAL_PROVIDER="${REAL_PROVIDER:-minimax}"
REAL_MODEL="${REAL_MODEL:-MiniMax-M2.7}"
REQUEST_ID="${REQUEST_ID:-b122c2-minimax-$(date +%m%d%H%M%S)}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
SOURCE_FILE="${SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/tool_bridge.rs}"
SECRET_FILE="${SECRET_FILE:-${ROOT}/k8s/beagle/secret.example.yaml}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require base64
require curl
require jq
require podman
require rg
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

KUBECTL="$(resolve_kubectl)"
require "${KUBECTL%% *}"

resolve_secret_value() {
  local key="$1"
  local encoded=""

  encoded="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o "jsonpath={.data.${key}}" 2>/dev/null || true)"
  if [[ -n "${encoded}" ]]; then
    printf '%s' "${encoded}" | base64 -d
    return 0
  fi

  return 1
}

resolve_operator_api_token() {
  if [[ -n "${OPERATOR_API_TOKEN}" ]]; then
    printf '%s\n' "${OPERATOR_API_TOKEN}"
    return 0
  fi

  resolve_secret_value "BEAGLE_OPERATOR_API_TOKEN" \
    || resolve_secret_value "BEAGLE_API_TOKEN" \
    || {
      echo "[FAIL] BEAGLE operator auth token not found locally or in ${SECRET_NAME}" >&2
      exit 1
    }
}

ensure_minimax_secret() {
  if resolve_secret_value "MINIMAX_API_KEY" >/dev/null; then
    return 0
  fi

  echo "[FAIL] MINIMAX_API_KEY is not materialized in ${SECRET_NAME}" >&2
  exit 1
}

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
ensure_minimax_secret

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
      echo "[FAIL] port-forward exited before health became ready" >&2
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

echo "${REQUEST_ID}" > "${OUT}/request-id.txt"
echo "${REAL_PROVIDER}" > "${OUT}/expected-provider.txt"
echo "${REAL_MODEL}" > "${OUT}/expected-model.txt"

SOURCE_EXECUTE_PRESENT=0
SOURCE_PROVIDER_PRESENT=0
SECRET_TEMPLATE_PRESENT=0

if rg -q "execute_minimax|MINIMAX_API_KEY|minimax request failed|minimax returned|anthropic-version" "${SOURCE_FILE}"; then
  SOURCE_EXECUTE_PRESENT=1
fi
if rg -q 'provider: BridgeProvider::Minimax|implemented: true|cheap API lane via MiniMax Anthropic-compatible API' "${SOURCE_FILE}"; then
  SOURCE_PROVIDER_PRESENT=1
fi
if rg -q 'MINIMAX_API_KEY' "${SECRET_FILE}"; then
  SECRET_TEMPLATE_PRESENT=1
fi

jq -nc \
  --arg source_file "${SOURCE_FILE}" \
  --arg secret_file "${SECRET_FILE}" \
  --arg expected_provider "${REAL_PROVIDER}" \
  --arg expected_model "${REAL_MODEL}" \
  --argjson source_execute_present "${SOURCE_EXECUTE_PRESENT}" \
  --argjson source_provider_present "${SOURCE_PROVIDER_PRESENT}" \
  --argjson secret_template_present "${SECRET_TEMPLATE_PRESENT}" \
  '{
    source_file: $source_file,
    secret_file: $secret_file,
    expected_provider: $expected_provider,
    expected_model: $expected_model,
    source_execute_present: $source_execute_present,
    source_provider_present: $source_provider_present,
    secret_template_present: $secret_template_present
  }' > "${OUT}/provider-summary.json"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-for-deploy.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/deploy-rollout.log"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"
curl_json GET "/api/darwin/bridge/health" "${OUT}/health.json"
curl_json GET "/api/darwin/bridge/providers" "${OUT}/providers.json"

cat > "${OUT}/execute-minimax-request.json" <<EOF
{
  "request_id": "${REQUEST_ID}",
  "bridge_kind": "cheap_api",
  "bridge_mode": "api_optional",
  "provider": "${REAL_PROVIDER}",
  "model": "${REAL_MODEL}",
  "task_type": "structured_extract",
  "payload": {
    "input": "Extract the single core architectural rule from this sentence in one short bullet: Beagle should add MiniMax through the existing cheap provider bridge path without redesigning the bridge foundation."
  },
  "metadata": {
    "source": "run_minimax_bridge_smoke"
  }
}
EOF

curl_json POST "/api/darwin/bridge/execute" "${OUT}/execute-minimax.json" "${OUT}/execute-minimax-request.json"

${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
  'test -s "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl" && tail -n 40 "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl"' \
  > "${OUT}/ledger-tail.jsonl"

EXECUTE_STATUS="$(jq -r '.status // empty' "${OUT}/execute-minimax.json")"
EXECUTE_PROVIDER="$(jq -r '.provider // empty' "${OUT}/execute-minimax.json")"
EXECUTE_MODEL="$(jq -r '.model // empty' "${OUT}/execute-minimax.json")"
EXECUTE_ERROR="$(jq -r '.error // empty' "${OUT}/execute-minimax.json")"

jq -nc \
  --arg request_id "${REQUEST_ID}" \
  --arg expected_provider "${REAL_PROVIDER}" \
  --arg expected_model "${REAL_MODEL}" \
  --arg execute_status "${EXECUTE_STATUS}" \
  --arg execute_provider "${EXECUTE_PROVIDER}" \
  --arg execute_model "${EXECUTE_MODEL}" \
  --arg execute_error "${EXECUTE_ERROR}" \
  '{
    request_id: $request_id,
    expected_provider: $expected_provider,
    expected_model: $expected_model,
    execute_status: $execute_status,
    execute_provider: $execute_provider,
    execute_model: $execute_model,
    execute_error: $execute_error
  }' > "${OUT}/smoke.json"

stop_port_forward

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
} > "${OUT}/final-cluster-health.txt"

echo "[OK] minimax bridge smoke artifacts written to ${OUT}"
