#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/hybrid-retrieval-spine}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18472}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-codex}"
EXPECTED_ROLE="${EXPECTED_ROLE:-assistant}"
EXPECTED_DOMAIN="${EXPECTED_DOMAIN:-beagle-engine}"
MEMORY_ENGINE_SOURCE_FILE="${MEMORY_ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
MEMORY_HTTP_SOURCE_FILE="${MEMORY_HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
DARWIN_HTTP_SOURCE_FILE="${DARWIN_HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
COLLECTION_CONTRACT_FILE="${COLLECTION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-collection-schema.yaml}"
POINT_CONTRACT_FILE="${POINT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-point-schema.yaml}"
QUERY_CONTRACT_FILE="${QUERY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-query-schema.yaml}"
RESULT_CONTRACT_FILE="${RESULT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-result-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B221_HYBRID_RETRIEVAL_SPINE_EMBEDDINGS_RAG_ELEVATION.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B221_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B221_KNOWN_LIMITS.md}"
QUERY_TEXT="${QUERY_TEXT:-B22.1 hybrid retrieval spine agourakis82/beagle main}"
CANONICAL_MARKER="${CANONICAL_MARKER:-B221 hybrid retrieval spine canonical memory point}"
DECOY_MARKER="${DECOY_MARKER:-B221 hybrid retrieval spine decoy memory point}"

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
MEMORY_HTTP_PRESENT=0
DARWIN_HTTP_PRESENT=0
COLLECTION_CONTRACT_PRESENT=0
POINT_CONTRACT_PRESENT=0
QUERY_CONTRACT_PRESENT=0
RESULT_CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "hybrid_retrieve|retrieval_collection|RetrievalQuery" "${MEMORY_ENGINE_SOURCE_FILE}"; then
  MEMORY_ENGINE_PRESENT=1
fi
if rg -q "/api/memory/retrieval/collection|/api/memory/retrieval/query" "${MEMORY_HTTP_SOURCE_FILE}"; then
  MEMORY_HTTP_PRESENT=1
fi
if rg -q "memory_hybrid_retrieve|context-packet" "${DARWIN_HTTP_SOURCE_FILE}"; then
  DARWIN_HTTP_PRESENT=1
fi
[[ -f "${COLLECTION_CONTRACT_FILE}" ]] && COLLECTION_CONTRACT_PRESENT=1
[[ -f "${POINT_CONTRACT_FILE}" ]] && POINT_CONTRACT_PRESENT=1
[[ -f "${QUERY_CONTRACT_FILE}" ]] && QUERY_CONTRACT_PRESENT=1
[[ -f "${RESULT_CONTRACT_FILE}" ]] && RESULT_CONTRACT_PRESENT=1
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --arg expected_source "${EXPECTED_SOURCE}" \
  --arg expected_role "${EXPECTED_ROLE}" \
  --arg expected_domain "${EXPECTED_DOMAIN}" \
  --argjson memory_engine_present "${MEMORY_ENGINE_PRESENT}" \
  --argjson memory_http_present "${MEMORY_HTTP_PRESENT}" \
  --argjson darwin_http_present "${DARWIN_HTTP_PRESENT}" \
  --argjson collection_contract_present "${COLLECTION_CONTRACT_PRESENT}" \
  --argjson point_contract_present "${POINT_CONTRACT_PRESENT}" \
  --argjson query_contract_present "${QUERY_CONTRACT_PRESENT}" \
  --argjson result_contract_present "${RESULT_CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    expected_source: $expected_source,
    expected_role: $expected_role,
    expected_domain: $expected_domain,
    memory_engine_present: $memory_engine_present,
    memory_http_present: $memory_http_present,
    darwin_http_present: $darwin_http_present,
    collection_contract_present: $collection_contract_present,
    point_contract_present: $point_contract_present,
    query_contract_present: $query_contract_present,
    result_contract_present: $result_contract_present,
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
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/collection" \
  > "${OUT}/retrieval-collection.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b221-hybrid-retrieval-canonical" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "${CANONICAL_MARKER}. ${QUERY_TEXT}. ${EXPECTED_WORKSTREAM}. ${EXPECTED_CAMPAIGN}. ${EXPECTED_PROGRAM}. ${EXPECTED_WORKSPACE}. ${EXPECTED_SESSION}." \
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
    turn_index: 1,
    role: $role,
    text: $text,
    tags: [$workstream_id, "hybrid-retrieval", "b221"],
    domain: $domain,
    provider: $provider,
    model: $model,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    physio_snapshot_ref: "physio:latest",
    result_refs: ["result:b221-hybrid-retrieval"],
    claim_refs: ["claim:b221-hybrid-retrieval"]
  }' > "${OUT}/canonical-memory-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/canonical-memory-ingest.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/canonical-memory-ingest-response.json"

jq -n \
  --arg text "${DECOY_MARKER}. ${QUERY_TEXT}. decoy-workstream." \
  '{
    source: "claude",
    conversation_id: "b221-hybrid-retrieval-decoy",
    turn_index: 1,
    role: "assistant",
    text: $text,
    tags: ["hybrid-retrieval", "b221", "decoy"],
    domain: "beagle-engine",
    provider: "claude-code",
    model: "sonnet",
    workstream_id: "decoy-workstream",
    campaign_id: "decoy-campaign",
    program_id: "decoy-program",
    workspace_id: "decoy-workspace",
    session_id: "decoy-session",
    result_refs: ["result:decoy"],
    claim_refs: ["claim:decoy"]
  }' > "${OUT}/decoy-memory-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/decoy-memory-ingest.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/decoy-memory-ingest-response.json"

jq -n \
  --arg query_text "${QUERY_TEXT}" \
  '{
    query_text: $query_text,
    top_k: 5,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      domain: "beagle-engine",
      tags: ["hybrid-retrieval", "b221"]
    },
    rerank_hint: "b221-hybrid-retrieval-spine"
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
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    query_text: $query_text,
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      role: $role,
      domain: $domain,
      tags: ["hybrid-retrieval", "b221"]
    },
    rerank_hint: "b221-hybrid-retrieval-spine-filtered"
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

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"
stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID

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
  --arg phase "B22.1" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
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
    collection_name: $collection[0].collection_name,
    dense_backend: $collection[0].dense_backend,
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
      (($filtered[0].hits | map(.point.payload.memory_id)) == ($filtered_restart[0].hits | map(.point.payload.memory_id)))
    ),
    payload_filter_state: "workstream+campaign+session+source+role+domain+tags",
    bounded_top_k: $filtered[0].top_k
  }' > "${OUT}/smoke.json"

capture_cluster_health
