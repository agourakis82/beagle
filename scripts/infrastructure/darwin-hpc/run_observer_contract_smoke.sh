#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18121}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/observer-contract}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
SESSION_ID="${SESSION_ID:-b172-observer-${STAMP}}"
QUERY_TEXT="${QUERY_TEXT:-observer contract canonical snapshot}"

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
  printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
}

KUBECTL="$(resolve_kubectl)"

resolve_operator_api_token() {
  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

choose_local_port() {
  local port="${LOCAL_PORT}"
  local tries=0
  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done
  echo "[FAIL] unable to find free local port" >&2
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
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done
  cat "${pf_log}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

wait_for_health() {
  local port="$1"
  local target="$2"
  for _ in $(seq 1 20); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    sleep 1
  done
  echo "[FAIL] health endpoint did not become ready" >&2
  exit 1
}

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
      "http://127.0.0.1:${LOCAL_PORT}${path}" > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" > "${target}"
  fi
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
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
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

mkdir -p "${OUT}"
LOCAL_PORT="$(choose_local_port)"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

jq -nc \
  --arg session_id "${SESSION_ID}" \
  --arg query_text "${QUERY_TEXT}" \
  '{session_id:$session_id,query_text:$query_text}' > "${OUT}/source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1
${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-for-deploy.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/deploy-rollout.log"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"

cat > "${OUT}/physio-ingest-request.json" <<EOF
{
  "source": "observer-smoke",
  "session_id": "${SESSION_ID}",
  "timestamp": "$(date -Iseconds)",
  "hr": 61,
  "hrv_ms": 84,
  "spo2": 98
}
EOF
curl_json POST "/api/observer/physio" "${OUT}/physio-ingest-response.json" "${OUT}/physio-ingest-request.json"
curl_json GET "/api/observer/physio/latest" "${OUT}/physio-latest.json"

cat > "${OUT}/memory-ingest-request.json" <<EOF
{
  "source": "chatgpt",
  "conversation_id": "${SESSION_ID}",
  "turn_index": 0,
  "role": "assistant",
  "text": "${QUERY_TEXT}",
  "tags": ["observer-contract", "memory-spine"],
  "domain": "beagle-engine",
  "provider": "chatgpt",
  "model": "gpt-5"
}
EOF
curl_json POST "/api/memory/ingest_chat" "${OUT}/memory-ingest-response.json" "${OUT}/memory-ingest-request.json"
cat > "${OUT}/memory-query-request.json" <<EOF
{
  "query": "${QUERY_TEXT}",
  "limit": 5,
  "domain": "beagle-engine",
  "tags": ["observer-contract"],
  "include_recent_physio": true
}
EOF
curl_json POST "/api/memory/query" "${OUT}/memory-query-response.json" "${OUT}/memory-query-request.json"

capture_cluster_health

jq -nc \
  --arg session_id "${SESSION_ID}" \
  --slurpfile ingest "${OUT}/physio-ingest-response.json" \
  --slurpfile latest "${OUT}/physio-latest.json" \
  --slurpfile mem_ingest "${OUT}/memory-ingest-response.json" \
  --slurpfile mem_query "${OUT}/memory-query-response.json" \
  '{
    status: (
      if (
        ($ingest[0].status // "") == "ok"
        and ($latest[0].status // "") == "ok"
        and (($latest[0].snapshot.session_id // "") == $session_id)
        and (($mem_ingest[0].status // "") == "ok")
        and (($mem_query[0].results | length) >= 1)
        and ($mem_query[0].results[0].physio_snapshot != null)
        and ($mem_query[0].recent_physio != null)
      ) then "ok" else "unexpected" end
    ),
    session_id: $session_id,
    latest_snapshot_session_id: ($latest[0].snapshot.session_id // null),
    memory_query_result_count: ($mem_query[0].results | length),
    memory_physio_present: ($mem_query[0].results[0].physio_snapshot != null),
    recent_physio_present: ($mem_query[0].recent_physio != null)
  }' > "${OUT}/smoke.json"

echo "[OK] observer contract smoke completed"
