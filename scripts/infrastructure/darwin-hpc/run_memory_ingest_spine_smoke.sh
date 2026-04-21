#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18103}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/memory-ingest-spine}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
CONVERSATION_ID="${CONVERSATION_ID:-b171-memory-${STAMP}}"
QUERY_TEXT="${QUERY_TEXT:-repo-native memory spine bounded ingest query}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-chatgpt}"
EXPECTED_DOMAIN="${EXPECTED_DOMAIN:-beagle-engine}"
EXPECTED_TAG="${EXPECTED_TAG:-memory-spine}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
MCP_SOURCE_FILE="${MCP_SOURCE_FILE:-${ROOT}/beagle-mcp-server/src/tools/memory.ts}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B171_MEMORY_INGEST_SPINE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B171_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B171_KNOWN_LIMITS.md}"
CONTRACT_INGEST_FILE="${CONTRACT_INGEST_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-ingest-chat-request.json}"
CONTRACT_QUERY_FILE="${CONTRACT_QUERY_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-query-request.json}"
CONTRACT_RESPONSE_FILE="${CONTRACT_RESPONSE_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-query-response.json}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require base64
require curl
require jq
require node
require npm
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

resolve_operator_api_token() {
  if [[ -n "${OPERATOR_API_TOKEN}" ]]; then
    printf '%s\n' "${OPERATOR_API_TOKEN}"
    return 0
  fi

  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi

  if [[ -n "${encoded_token}" ]]; then
    printf '%s' "${encoded_token}" | base64 -d
    return 0
  fi

  echo "[FAIL] missing operator token locally and in secret ${SECRET_NAME}" >&2
  exit 1
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
      echo "[FAIL] port-forward exited early" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind" >&2
  cat "${pf_log}" >&2 || true
  exit 1
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

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
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

rollout_service() {
  local restart_log="$1"
  local rollout_log="$2"
  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${rollout_log}"
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
mkdir -p "${OUT}"
LOCAL_PORT="$(choose_local_port)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

HTTP_SOURCE_PRESENT=0
ENGINE_SOURCE_PRESENT=0
MCP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
INGEST_CONTRACT_PRESENT=0
QUERY_CONTRACT_PRESENT=0
RESPONSE_CONTRACT_PRESENT=0

if rg -q "/api/memory/ingest_chat|/api/memory/query|latest_physio_snapshot|build_experiment_flags" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if rg -q "MemoryRecord|PhysioSnapshot|ExperimentFlags|search_records|upsert_record" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "beagle_memory_ingest_chat|beagle_memory_query|include_recent_physio|domain" "${MCP_SOURCE_FILE}"; then
  MCP_SOURCE_PRESENT=1
fi
[[ -s "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -s "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -s "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -s "${CONTRACT_INGEST_FILE}" ]] && INGEST_CONTRACT_PRESENT=1
[[ -s "${CONTRACT_QUERY_FILE}" ]] && QUERY_CONTRACT_PRESENT=1
[[ -s "${CONTRACT_RESPONSE_FILE}" ]] && RESPONSE_CONTRACT_PRESENT=1

jq -nc \
  --arg expected_source "${EXPECTED_SOURCE}" \
  --arg expected_domain "${EXPECTED_DOMAIN}" \
  --arg expected_tag "${EXPECTED_TAG}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson mcp_source_present "${MCP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson ingest_contract_present "${INGEST_CONTRACT_PRESENT}" \
  --argjson query_contract_present "${QUERY_CONTRACT_PRESENT}" \
  --argjson response_contract_present "${RESPONSE_CONTRACT_PRESENT}" \
  '{
    expected_source: $expected_source,
    expected_domain: $expected_domain,
    expected_tag: $expected_tag,
    http_source_present: $http_source_present,
    engine_source_present: $engine_source_present,
    mcp_source_present: $mcp_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    ingest_contract_present: $ingest_contract_present,
    query_contract_present: $query_contract_present,
    response_contract_present: $response_contract_present
  }' > "${OUT}/source-summary.json"

echo "${CONVERSATION_ID}" > "${OUT}/conversation-id.txt"
echo "${EXPECTED_SOURCE}" > "${OUT}/expected-source.txt"
echo "${EXPECTED_DOMAIN}" > "${OUT}/expected-domain.txt"
echo "${EXPECTED_TAG}" > "${OUT}/expected-tag.txt"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_service "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"

cat > "${OUT}/physio-request.json" <<EOF
{
  "source": "b171-smoke",
  "session_id": "${CONVERSATION_ID}",
  "hrv_ms": 82,
  "heart_rate_bpm": 63,
  "spo2_percent": 98
}
EOF
curl_json POST "/api/observer/physio" "${OUT}/observer-physio-response.json" "${OUT}/physio-request.json"

cat > "${OUT}/ingest-request.json" <<EOF
{
  "source": "${EXPECTED_SOURCE}",
  "conversation_id": "${CONVERSATION_ID}",
  "turn_index": 0,
  "role": "assistant",
  "text": "${QUERY_TEXT}",
  "tags": ["${EXPECTED_TAG}", "darwin-hpc"],
  "domain": "${EXPECTED_DOMAIN}",
  "provider": "chatgpt",
  "model": "gpt-5"
}
EOF
curl_json POST "/api/memory/ingest_chat" "${OUT}/ingest-response.json" "${OUT}/ingest-request.json"
MEMORY_ID="$(jq -r '.memory_id' "${OUT}/ingest-response.json")"
echo "${MEMORY_ID}" > "${OUT}/memory-id.txt"

cat > "${OUT}/query-request.json" <<EOF
{
  "query": "${QUERY_TEXT}",
  "limit": 5,
  "domain": "${EXPECTED_DOMAIN}",
  "tags": ["${EXPECTED_TAG}"],
  "include_recent_physio": true
}
EOF
curl_json POST "/api/memory/query" "${OUT}/query-response.json" "${OUT}/query-request.json"
jq '.results[0].physio_snapshot // .recent_physio' "${OUT}/query-response.json" > "${OUT}/physio-attachment.json"

pushd "${ROOT}/beagle-mcp-server" >/dev/null
npm ci > "${OUT}/mcp-npm-ci.log" 2>&1
npm run build > "${OUT}/mcp-build.log" 2>&1
BEAGLE_BASE_URL="http://127.0.0.1:${LOCAL_PORT}" \
BEAGLE_TOKEN="${OPERATOR_API_TOKEN}" \
BEAGLE_CONVERSATION_ID="${CONVERSATION_ID}" \
BEAGLE_QUERY_TEXT="${QUERY_TEXT}" \
BEAGLE_EXPECTED_DOMAIN="${EXPECTED_DOMAIN}" \
BEAGLE_EXPECTED_TAG="${EXPECTED_TAG}" \
node --input-type=module > "${OUT}/mcp-tool-results.json" <<'EOF'
import { BeagleClient } from "./dist/beagle-client.js";
import { memoryTools } from "./dist/tools/memory.js";

const client = new BeagleClient(process.env.BEAGLE_BASE_URL, process.env.BEAGLE_TOKEN);
const tools = memoryTools(client);
const ingestTool = tools.find((tool) => tool.name === "beagle_memory_ingest_chat");
const queryTool = tools.find((tool) => tool.name === "beagle_memory_query");

const ingest = await ingestTool.handler({
  source: "codex",
  conversation_id: process.env.BEAGLE_CONVERSATION_ID,
  turn_index: 1,
  role: "assistant",
  text: `${process.env.BEAGLE_QUERY_TEXT} via MCP tool`,
  domain: process.env.BEAGLE_EXPECTED_DOMAIN,
  tags: [process.env.BEAGLE_EXPECTED_TAG, "mcp"],
  provider: "codex",
  model: "gpt-5-codex"
});

const query = await queryTool.handler({
  query: process.env.BEAGLE_QUERY_TEXT,
  limit: 5,
  domain: process.env.BEAGLE_EXPECTED_DOMAIN,
  tags: [process.env.BEAGLE_EXPECTED_TAG],
  include_recent_physio: true
});

console.log(JSON.stringify({ ingest, query }, null, 2));
EOF
popd >/dev/null

jq '.ingest' "${OUT}/mcp-tool-results.json" > "${OUT}/mcp-ingest-response.json"
jq '.query' "${OUT}/mcp-tool-results.json" > "${OUT}/mcp-query-response.json"

stop_port_forward
capture_cluster_health

jq -nc \
  --arg conversation_id "${CONVERSATION_ID}" \
  --arg memory_id "${MEMORY_ID}" \
  --arg expected_source "${EXPECTED_SOURCE}" \
  --arg expected_domain "${EXPECTED_DOMAIN}" \
  --arg expected_tag "${EXPECTED_TAG}" \
  --slurpfile ingest "${OUT}/ingest-response.json" \
  --slurpfile query "${OUT}/query-response.json" \
  --slurpfile physio "${OUT}/physio-attachment.json" \
  --slurpfile mcp_ingest "${OUT}/mcp-ingest-response.json" \
  --slurpfile mcp_query "${OUT}/mcp-query-response.json" \
  '{
    status: (
      if (
        ($ingest[0].status // "") == "ok"
        and ($query[0].results | length) >= 1
        and (($query[0].results[0].conversation_id // "") == $conversation_id)
        and (($query[0].results[0].memory_id // "") == $memory_id)
        and (($query[0].results[0].source // "") == $expected_source)
        and (($query[0].results[0].domain // "") == $expected_domain)
        and (($query[0].results[0].tags | index($expected_tag)) != null)
        and ($physio[0] != null)
        and (($mcp_ingest[0].status // "") == "ok")
        and (($mcp_query[0].results | length) >= 1)
      ) then "ok" else "unexpected" end
    ),
    conversation_id: $conversation_id,
    memory_id: $memory_id,
    expected_source: $expected_source,
    expected_domain: $expected_domain,
    expected_tag: $expected_tag,
    http_query_result_count: ($query[0].results | length),
    http_physio_present: ($physio[0] != null),
    mcp_query_result_count: ($mcp_query[0].results | length)
  }' > "${OUT}/smoke.json"

echo "[OK] memory ingest spine smoke completed"
