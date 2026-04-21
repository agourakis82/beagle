#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/dense-backend-promotion}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18474}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-codex}"
EXPECTED_ROLE="${EXPECTED_ROLE:-assistant}"
EXPECTED_DOMAIN="${EXPECTED_DOMAIN:-beagle-engine}"
PROMOTED_BACKEND="${PROMOTED_BACKEND:-voyage-4-large}"
CODE_CANDIDATE_BACKEND="${CODE_CANDIDATE_BACKEND:-voyage-code-3}"
SOVEREIGN_CANDIDATE_BACKEND="${SOVEREIGN_CANDIDATE_BACKEND:-bge-m3}"
MEMORY_ENGINE_SOURCE_FILE="${MEMORY_ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
MEMORY_RETRIEVAL_SOURCE_FILE="${MEMORY_RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_HTTP_SOURCE_FILE="${MEMORY_HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
DARWIN_HTTP_SOURCE_FILE="${DARWIN_HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/embedding-backend-contract.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B223_DENSE_BACKEND_PROMOTION.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B223_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B223_KNOWN_LIMITS.md}"
QUERY_TEXT="${QUERY_TEXT:-B22.3 dense backend promotion voyage-4-large beagle retrieval spine}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require base64
require curl
require jq
require rg
require ss

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

resolve_operator_api_token() {
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

rollout_deployment() {
  local deployment="$1"
  local restart_log="$2"
  local rollout_log="$3"
  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${deployment}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${deployment}" --timeout=900s > "${rollout_log}"
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -l app.kubernetes.io/part-of=beagle -o wide || true
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
  stop_port_forward BEAGLE_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"

MEMORY_ENGINE_PRESENT=0
MEMORY_RETRIEVAL_PRESENT=0
MEMORY_HTTP_PRESENT=0
DARWIN_HTTP_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "embedding_backend_contract|dense_backend_id|voyage-4-large" "${MEMORY_ENGINE_SOURCE_FILE}"; then
  MEMORY_ENGINE_PRESENT=1
fi
if rg -q "EmbeddingBackendContract|EMBEDDING_BACKEND_CONTRACT_VERSION" "${MEMORY_RETRIEVAL_SOURCE_FILE}"; then
  MEMORY_RETRIEVAL_PRESENT=1
fi
if rg -q "/api/memory/retrieval/dense-backend" "${MEMORY_HTTP_SOURCE_FILE}"; then
  MEMORY_HTTP_PRESENT=1
fi
if rg -q "context-packet" "${DARWIN_HTTP_SOURCE_FILE}"; then
  DARWIN_HTTP_PRESENT=1
fi
[[ -f "${CONTRACT_FILE}" ]] && CONTRACT_PRESENT=1
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1

jq -n \
  --arg promoted_backend "${PROMOTED_BACKEND}" \
  --arg code_candidate_backend "${CODE_CANDIDATE_BACKEND}" \
  --arg sovereign_candidate_backend "${SOVEREIGN_CANDIDATE_BACKEND}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson memory_engine_present "${MEMORY_ENGINE_PRESENT}" \
  --argjson memory_retrieval_present "${MEMORY_RETRIEVAL_PRESENT}" \
  --argjson memory_http_present "${MEMORY_HTTP_PRESENT}" \
  --argjson darwin_http_present "${DARWIN_HTTP_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    promoted_backend: $promoted_backend,
    code_candidate_backend: $code_candidate_backend,
    sovereign_candidate_backend: $sovereign_candidate_backend,
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    memory_engine_present: $memory_engine_present,
    memory_retrieval_present: $memory_retrieval_present,
    memory_http_present: $memory_http_present,
    darwin_http_present: $darwin_http_present,
    contract_present: $contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/dense-backend" \
  > "${OUT}/dense-backend-contract.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/collection" \
  > "${OUT}/retrieval-collection.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/backend-matrix" \
  > "${OUT}/backend-matrix.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b223-dense-backend-canonical" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B223 dense backend promotion canonical memory point. ${QUERY_TEXT}. ${EXPECTED_WORKSTREAM}. ${EXPECTED_CAMPAIGN}. ${EXPECTED_PROGRAM}. ${EXPECTED_WORKSPACE}. ${EXPECTED_SESSION}." \
  --arg domain "${EXPECTED_DOMAIN}" \
  --arg provider "codex" \
  --arg model "gpt-5" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 0,
    role: $role,
    text: $text,
    tags: ["dense-backend-promotion", "b223", $workstream_id],
    domain: $domain,
    provider: $provider,
    model: $model,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b223-dense-backend"],
    claim_refs: ["claim:b223-dense-backend"]
  }' > "${OUT}/canonical-memory-point.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/canonical-memory-point.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/canonical-memory-point-response.json"

jq -n \
  --arg source "cursor" \
  --arg conversation_id "b223-dense-backend-decoy" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B223 dense backend promotion decoy memory point unrelated to the canonical workstream." \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 0,
    role: $role,
    text: $text,
    tags: ["dense-backend-promotion", "b223", "decoy"],
    domain: $domain,
    workstream_id: "other-workstream",
    campaign_id: "other-campaign",
    program_id: "other-program",
    workspace_id: "other-workspace",
    session_id: "other-session"
  }' > "${OUT}/decoy-memory-point.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/decoy-memory-point.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/decoy-memory-point-response.json"

jq -n \
  --arg query_text "${QUERY_TEXT}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    query_version: "beagle-retrieval-query-v1",
    query_text: $query_text,
    top_k: 4,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      workstream_id: $workstream_id,
      domain: $domain,
      tags: ["dense-backend-promotion", "b223"]
    },
    rerank_hint: "b223-dense-backend-promotion"
  }' > "${OUT}/retrieval-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/retrieval-query.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/query" \
  > "${OUT}/retrieval-result.json"

jq -n \
  --arg query_text "${QUERY_TEXT}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg source "${EXPECTED_SOURCE}" \
  '{
    query_version: "beagle-retrieval-query-v1",
    query_text: $query_text,
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      workstream_id: $workstream_id,
      source: $source,
      tags: ["dense-backend-promotion", "b223"]
    },
    rerank_hint: "b223-dense-backend-filtered"
  }' > "${OUT}/filtered-retrieval-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/filtered-retrieval-query.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/query" \
  > "${OUT}/filtered-retrieval-result.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" \
  > "${OUT}/context-packet-with-retrieval.json"

cp "${OUT}/context-packet-with-retrieval.json" "${OUT}/context-packet-with-promoted-dense.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"
stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/dense-backend" \
  > "${OUT}/dense-backend-contract-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/filtered-retrieval-query.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/query" \
  > "${OUT}/filtered-retrieval-result-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" \
  > "${OUT}/context-packet-with-retrieval-after-restart.json"

jq -n \
  --slurpfile contract "${OUT}/dense-backend-contract.json" \
  --slurpfile collection "${OUT}/retrieval-collection.json" \
  --slurpfile matrix "${OUT}/backend-matrix.json" \
  '{
    promoted_dense_backend: $contract[0].promoted_dense_backend,
    active_dense_backend: $contract[0].active_dense_backend,
    runtime_state: $contract[0].runtime_state,
    authentication_mode: $contract[0].authentication_mode,
    endpoint_ref: $contract[0].endpoint_ref,
    store_direction: $contract[0].store_direction,
    collection_name: $collection[0].collection_name,
    collection_dense_backend: $collection[0].dense_backend,
    sparse_backend: $collection[0].sparse_backend,
    matrix_current_dense_backend: $matrix[0].current_dense_backend
  }' > "${OUT}/promotion-summary.json"

jq -n \
  --arg phase "B22.3" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --slurpfile contract "${OUT}/dense-backend-contract.json" \
  --slurpfile contract_restart "${OUT}/dense-backend-contract-after-restart.json" \
  --slurpfile collection "${OUT}/retrieval-collection.json" \
  --slurpfile retrieval "${OUT}/retrieval-result.json" \
  --slurpfile filtered "${OUT}/filtered-retrieval-result.json" \
  --slurpfile filtered_restart "${OUT}/filtered-retrieval-result-after-restart.json" \
  --slurpfile context_packet "${OUT}/context-packet-with-retrieval.json" \
  --slurpfile context_packet_restart "${OUT}/context-packet-with-retrieval-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    promoted_dense_backend: $contract[0].promoted_dense_backend,
    active_dense_backend: $contract[0].active_dense_backend,
    runtime_state: $contract[0].runtime_state,
    collection_name: $collection[0].collection_name,
    collection_dense_backend: $collection[0].dense_backend,
    sparse_backend: $collection[0].sparse_backend,
    retrieval_hit_count: ($retrieval[0].hits | length),
    filtered_hit_count: ($filtered[0].hits | length),
    filtered_workstream_match_count: ($filtered[0].hits | map(select(.point.payload.workstream_id == $workstream_id)) | length),
    context_packet_memory_hit_count: ($context_packet[0].packet.memory_hits | length),
    context_packet_contains_filtered_memory: (
      ($context_packet[0].packet.memory_hits | map(.memory_id) | unique) as $ids
      | any($filtered[0].hits[]; (.point.payload.memory_id as $id | $ids | index($id)))
    ),
    restart_recovered_session: (
      $context_packet[0].packet.session_id == $context_packet_restart[0].packet.session_id and
      $contract[0].runtime_state == $contract_restart[0].runtime_state and
      (($filtered[0].hits | map(.point.payload.memory_id)) == ($filtered_restart[0].hits | map(.point.payload.memory_id)))
    ),
    bounded_top_k: $filtered[0].top_k
  }' > "${OUT}/smoke.json"

capture_cluster_health
