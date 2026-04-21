#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/memory-hierarchy-graphrag}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18510}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-codex}"
EXPECTED_ROLE="${EXPECTED_ROLE:-assistant}"
EXPECTED_GENERAL_DENSE="${EXPECTED_GENERAL_DENSE:-voyage-4-large}"
EXPECTED_SPARSE="${EXPECTED_SPARSE:-local-lexical}"
EXPECTED_RERANKER="${EXPECTED_RERANKER:-voyage-rank-2.5}"
TAG="${TAG:-b231-graphrag}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
RETRIEVAL_SOURCE_FILE="${RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
CORE_CONTEXT_SOURCE_FILE="${CORE_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-core/src/context.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B231_MEMORY_HIERARCHY_AND_GRAPHRAG_PILOT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B231_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B231_KNOWN_LIMITS.md}"
HIERARCHY_CONTRACT_FILE="${HIERARCHY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-hierarchy-schema.yaml}"
NODE_CONTRACT_FILE="${NODE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/graphrag-node-schema.yaml}"
EDGE_CONTRACT_FILE="${EDGE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/graphrag-edge-schema.yaml}"
QUERY_CONTRACT_FILE="${QUERY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/graphrag-query-schema.yaml}"
PRIOR_FEEDBACK_ARTIFACT_DIR="${PRIOR_FEEDBACK_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/retrieval-feedback-loop}"

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

ENGINE_SOURCE_PRESENT=0
RETRIEVAL_SOURCE_PRESENT=0
MEMORY_LIB_SOURCE_PRESENT=0
CORE_CONTEXT_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
HTTP_MEMORY_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
HIERARCHY_CONTRACT_PRESENT=0
NODE_CONTRACT_PRESENT=0
EDGE_CONTRACT_PRESENT=0
QUERY_CONTRACT_PRESENT=0
PRIOR_FEEDBACK_ARTIFACTS_PRESENT=0

if rg -q "graph_rag_query|graph_rag_from_reranked_result|classify_memory_type|memory_hierarchy_from_records" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "MEMORY_HIERARCHY_VERSION|GRAPHRAG_QUERY_VERSION|GRAPHRAG_RESULT_VERSION" "${RETRIEVAL_SOURCE_FILE}"; then
  RETRIEVAL_SOURCE_PRESENT=1
fi
if rg -q "GraphRagQuery|GraphRagResult|MemoryHierarchy" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "memory_graph_rag_query" "${CORE_CONTEXT_SOURCE_FILE}"; then
  CORE_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "graphrag_root_entity_type|memory_hierarchy_counts" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "graphrag_root_entity_type|memory_hierarchy_counts" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/graphrag/query" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
if rg -q "memory_graph_rag_query|graphrag_result" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${HIERARCHY_CONTRACT_FILE}" ]] && HIERARCHY_CONTRACT_PRESENT=1
[[ -f "${NODE_CONTRACT_FILE}" ]] && NODE_CONTRACT_PRESENT=1
[[ -f "${EDGE_CONTRACT_FILE}" ]] && EDGE_CONTRACT_PRESENT=1
[[ -f "${QUERY_CONTRACT_FILE}" ]] && QUERY_CONTRACT_PRESENT=1
if [[ -f "${PRIOR_FEEDBACK_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_FEEDBACK_ARTIFACT_DIR}/retrieval-policy.json" ]]; then
  PRIOR_FEEDBACK_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --arg expected_general_dense "${EXPECTED_GENERAL_DENSE}" \
  --arg expected_sparse "${EXPECTED_SPARSE}" \
  --arg expected_reranker "${EXPECTED_RERANKER}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson retrieval_source_present "${RETRIEVAL_SOURCE_PRESENT}" \
  --argjson memory_lib_source_present "${MEMORY_LIB_SOURCE_PRESENT}" \
  --argjson core_context_source_present "${CORE_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson hierarchy_contract_present "${HIERARCHY_CONTRACT_PRESENT}" \
  --argjson node_contract_present "${NODE_CONTRACT_PRESENT}" \
  --argjson edge_contract_present "${EDGE_CONTRACT_PRESENT}" \
  --argjson query_contract_present "${QUERY_CONTRACT_PRESENT}" \
  --argjson prior_feedback_artifacts_present "${PRIOR_FEEDBACK_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    expected_general_dense: $expected_general_dense,
    expected_sparse: $expected_sparse,
    expected_reranker: $expected_reranker,
    engine_source_present: $engine_source_present,
    retrieval_source_present: $retrieval_source_present,
    memory_lib_source_present: $memory_lib_source_present,
    core_context_source_present: $core_context_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    http_memory_source_present: $http_memory_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    hierarchy_contract_present: $hierarchy_contract_present,
    node_contract_present: $node_contract_present,
    edge_contract_present: $edge_contract_present,
    query_contract_present: $query_contract_present,
    prior_feedback_artifacts_present: $prior_feedback_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
WORKSTREAM_URL="${BASE_URL}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}"
PROGRAM_URL="${BASE_URL}/api/darwin/programs/${EXPECTED_PROGRAM}"

ingest_memory() {
  local payload_file="$1"
  curl -fsS \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data @"${payload_file}" \
    "${BASE_URL}/api/memory/ingest_chat" \
    > "${payload_file%.json}-response.json"
}

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b231-episodic" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Operator resumed the same Beagle-owned session after a bounded restart and recorded the handoff context." \
  --arg domain "darwin-hpc" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg tag "${TAG}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 1,
    role: $role,
    text: $text,
    tags: [$workstream_id, $tag, "episodic", "handoff"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id
  }' > "${OUT}/episodic-ingest.json"
ingest_memory "${OUT}/episodic-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b231-semantic" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Experiment expedition batch A produced a result that supports the HRV-aware claim now appearing in the manuscript pack." \
  --arg domain "darwin-hpc" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg tag "${TAG}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 2,
    role: $role,
    text: $text,
    tags: [$workstream_id, $tag, "semantic", "claim", "evidence"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["experiment-expedition-002-batch-a/result-hrv-aware"],
    claim_refs: ["claim-hrv-aware-improves-latency"]
  }' > "${OUT}/semantic-ingest.json"
ingest_memory "${OUT}/semantic-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b231-procedural" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Update the GraphRAG smoke script and HTTP memory route wiring for the memory hierarchy pilot." \
  --arg domain "darwin-hpc" \
  --arg repo_path "beagle/scripts/infrastructure/darwin-hpc/run_memory_hierarchy_graphrag_smoke.sh" \
  --arg file_type "shell" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg tag "${TAG}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 3,
    role: $role,
    text: $text,
    tags: [$workstream_id, $tag, "procedural", "code"],
    domain: $domain,
    repo_path: $repo_path,
    file_type: $file_type,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id
  }' > "${OUT}/procedural-ingest.json"
ingest_memory "${OUT}/procedural-ingest.json"

EPISODIC_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/episodic-ingest-response.json")"
SEMANTIC_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/semantic-ingest-response.json")"
PROCEDURAL_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/procedural-ingest-response.json")"

jq -n \
  --arg query_version "beagle-graphrag-query-v1" \
  --arg query_text "Connect the resumed session, experiment evidence, claim support, manuscript usage, and GraphRAG runbook wiring." \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "darwin-hpc" \
  --arg tag "${TAG}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  '{
    query_version: $query_version,
    query_text: $query_text,
    top_k: 6,
    max_hops: 2,
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
      tags: [$tag]
    },
    root_entity_type: "workstream",
    root_entity_id: $workstream_id,
    program_id: $program_id,
    include_memory_hierarchy: true,
    query_type_hint: "general",
    rerank_hint: "b231-graphrag"
  }' > "${OUT}/graphrag-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/graphrag-query.json" \
  "${BASE_URL}/api/memory/graphrag/query" \
  > "${OUT}/graphrag-result.json"

jq '.memory_hierarchy' "${OUT}/graphrag-result.json" > "${OUT}/memory-hierarchy.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-graphrag.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${PROGRAM_URL}/context-packet" \
  > "${OUT}/program-context-packet-with-graphrag.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/graphrag-query.json" \
  "${BASE_URL}/api/memory/graphrag/query" \
  > "${OUT}/graphrag-result-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-graphrag-after-restart.json"

jq -n \
  --arg phase "B23.1" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg episodic_id "${EPISODIC_MEMORY_ID}" \
  --arg semantic_id "${SEMANTIC_MEMORY_ID}" \
  --arg procedural_id "${PROCEDURAL_MEMORY_ID}" \
  --slurpfile graphrag "${OUT}/graphrag-result.json" \
  --slurpfile graphrag_restart "${OUT}/graphrag-result-after-restart.json" \
  --slurpfile hierarchy "${OUT}/memory-hierarchy.json" \
  --slurpfile workstream_packet "${OUT}/context-packet-with-graphrag.json" \
  --slurpfile program_packet "${OUT}/program-context-packet-with-graphrag.json" \
  --slurpfile restart_packet "${OUT}/context-packet-with-graphrag-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    routing_selected_route: $graphrag[0].routing_decision.selected_route,
    dense_backend: $graphrag[0].dense_backend,
    sparse_backend: $graphrag[0].sparse_backend,
    reranker_backend: $graphrag[0].reranker_backend,
    node_count: $graphrag[0].node_count,
    edge_count: $graphrag[0].edge_count,
    hierarchy_bucket_count: ($hierarchy[0].buckets | length),
    episodic_count: (($hierarchy[0].buckets[] | select(.memory_type == "episodic") | .count) // 0),
    semantic_count: (($hierarchy[0].buckets[] | select(.memory_type == "semantic") | .count) // 0),
    procedural_count: (($hierarchy[0].buckets[] | select(.memory_type == "procedural") | .count) // 0),
    payload_filters_preserved: (
      ($graphrag[0].support_memory_ids | length) >= 3 and
      ($graphrag[0].support_memory_ids | all(.[]; . == $episodic_id or . == $semantic_id or . == $procedural_id))
    ),
    context_packet_contains_graphrag: (
      ($workstream_packet[0].packet.retrieval_context.graphrag_node_count // 0) > 0 and
      ($workstream_packet[0].packet.retrieval_context.graphrag_edge_count // 0) > 0
    ),
    program_context_contains_graphrag: (
      ($program_packet[0].packet.retrieval_context.graphrag_node_count // 0) > 0 and
      ($program_packet[0].packet.retrieval_context.graphrag_edge_count // 0) > 0
    ),
    restart_recovered_session: (
      $graphrag_restart[0].session_id == $session_id and
      ($graphrag_restart[0].node_count // 0) > 0 and
      ($restart_packet[0].packet.session_id == $session_id) and
      (($restart_packet[0].packet.retrieval_context.graphrag_node_count // 0) > 0)
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health
