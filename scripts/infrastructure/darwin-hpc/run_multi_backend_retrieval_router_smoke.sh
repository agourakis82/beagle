#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/multi-backend-retrieval-router}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18481}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-codex}"
EXPECTED_ROLE="${EXPECTED_ROLE:-assistant}"
EXPECTED_GENERAL_DENSE="${EXPECTED_GENERAL_DENSE:-voyage-4-large}"
EXPECTED_CODE_DENSE="${EXPECTED_CODE_DENSE:-voyage-code-3}"
EXPECTED_SOVEREIGN_DENSE="${EXPECTED_SOVEREIGN_DENSE:-bge-m3}"
EXPECTED_SPARSE="${EXPECTED_SPARSE:-local-lexical}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
RETRIEVAL_SOURCE_FILE="${RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
CORE_CONTEXT_SOURCE_FILE="${CORE_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-core/src/context.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B227_MULTI_BACKEND_RETRIEVAL_ROUTER.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B227_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B227_KNOWN_LIMITS.md}"
ROUTER_CONTRACT_FILE="${ROUTER_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-router-schema.yaml}"
QUERY_TYPE_CONTRACT_FILE="${QUERY_TYPE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/query-type-schema.yaml}"
ROUTING_DECISION_CONTRACT_FILE="${ROUTING_DECISION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-routing-decision-schema.yaml}"
TAG="${TAG:-b227-multi-backend-router}"

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
ROUTER_CONTRACT_PRESENT=0
QUERY_TYPE_CONTRACT_PRESENT=0
ROUTING_DECISION_CONTRACT_PRESENT=0

if rg -q "classify_retrieval_query|retrieval_routing_decision|routed_retrieve" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "RetrievalQueryType|RetrievalRoutingDecision|RoutedRetrievalResult|ROUTED_RETRIEVAL_RESULT_VERSION" "${RETRIEVAL_SOURCE_FILE}"; then
  RETRIEVAL_SOURCE_PRESENT=1
fi
if rg -q "RetrievalQueryType|RetrievalRoutingDecision|RoutedRetrievalResult" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "memory_classify_retrieval_query|memory_retrieval_routing_decision|memory_routed_retrieve" "${CORE_CONTEXT_SOURCE_FILE}"; then
  CORE_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "query_type: String|routing_source: String|routing_reason: String" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "query_type: String|routing_source: String" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/retrieval/router/query-type|/api/memory/retrieval/router/decision|/api/memory/retrieval/router/query" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
if rg -q "memory_routed_retrieve|ROUTED_RETRIEVAL_QUERY_VERSION|query_type: result.query_type" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${ROUTER_CONTRACT_FILE}" ]] && ROUTER_CONTRACT_PRESENT=1
[[ -f "${QUERY_TYPE_CONTRACT_FILE}" ]] && QUERY_TYPE_CONTRACT_PRESENT=1
[[ -f "${ROUTING_DECISION_CONTRACT_FILE}" ]] && ROUTING_DECISION_CONTRACT_PRESENT=1

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --arg expected_general_dense "${EXPECTED_GENERAL_DENSE}" \
  --arg expected_code_dense "${EXPECTED_CODE_DENSE}" \
  --arg expected_sovereign_dense "${EXPECTED_SOVEREIGN_DENSE}" \
  --arg expected_sparse "${EXPECTED_SPARSE}" \
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
  --argjson router_contract_present "${ROUTER_CONTRACT_PRESENT}" \
  --argjson query_type_contract_present "${QUERY_TYPE_CONTRACT_PRESENT}" \
  --argjson routing_decision_contract_present "${ROUTING_DECISION_CONTRACT_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    expected_general_dense: $expected_general_dense,
    expected_code_dense: $expected_code_dense,
    expected_sovereign_dense: $expected_sovereign_dense,
    expected_sparse: $expected_sparse,
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
    router_contract_present: $router_contract_present,
    query_type_contract_present: $query_type_contract_present,
    routing_decision_contract_present: $routing_decision_contract_present
  }' > "${OUT}/source-summary.json"

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
WORKSTREAM_URL="${BASE_URL}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}"
PROGRAM_URL="${BASE_URL}/api/darwin/programs/${EXPECTED_PROGRAM}"

ingest_memory() {
  local output_file="$1"
  curl -fsS \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data @"${output_file}" \
    "${BASE_URL}/api/memory/ingest_chat" \
    > "${output_file%.json}-response.json"
}

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b227-general-memory" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B22.7 canonical general retrieval memory for workstream launch resume campaign context evidence governance and operator rhythm." \
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
    tags: [$workstream_id, $tag, "general", "context"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b227-general"],
    claim_refs: ["claim:b227-general"]
  }' > "${OUT}/general-memory-ingest.json"
ingest_memory "${OUT}/general-memory-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b227-code-memory" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "fn workspace_attach_router() { route_query_type(\"code\"); } // beagle/crates/beagle-darwin/src/workspace_attach.rs" \
  --arg domain "beagle-engine" \
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
    tags: [$workstream_id, $tag, "code", "repo"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    repo_path: "beagle/crates/beagle-darwin/src/workspace_attach.rs",
    file_type: "rust",
    result_refs: ["result:b227-code"],
    claim_refs: ["claim:b227-code"]
  }' > "${OUT}/code-memory-ingest.json"
ingest_memory "${OUT}/code-memory-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b227-sovereign-memory" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Consulta multilingue sobre privacidade, memoria soberana e recuperacao offline para o mesmo workstream canônico." \
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
    turn_index: 3,
    role: $role,
    text: $text,
    tags: [$workstream_id, $tag, "sovereign", "multilingual"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b227-sovereign"],
    claim_refs: ["claim:b227-sovereign"]
  }' > "${OUT}/sovereign-memory-ingest.json"
ingest_memory "${OUT}/sovereign-memory-ingest.json"

jq -n \
  --arg query "consulta multilingue sobre privacidade e memoria soberana offline" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg tag "${TAG}" \
  '{
    query_text: $query,
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.7,
    sparse_weight: 0.3,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      role: $role,
      tags: [$tag, "sovereign"]
    }
  }' > "${OUT}/query-type-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/query-type-request.json" \
  "${BASE_URL}/api/memory/retrieval/router/query-type" \
  > "${OUT}/query-type.json"

jq -n \
  --arg query "find workspace_attach implementation in the repo" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg tag "${TAG}" \
  '{
    query_text: $query,
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.75,
    sparse_weight: 0.25,
    compare_against_general: true,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      role: $role,
      repo_path: "beagle/crates/beagle-darwin/src/workspace_attach.rs",
      file_type: "rust",
      tags: [$tag, "code"]
    }
  }' > "${OUT}/routing-decision-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/routing-decision-request.json" \
  "${BASE_URL}/api/memory/retrieval/router/decision" \
  > "${OUT}/routing-decision.json"

jq -n \
  --arg query "resume campaign context and operator governance memory" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "darwin-hpc" \
  --arg tag "${TAG}" \
  '{
    query_text: $query,
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
      tags: [$tag, "general"]
    }
  }' > "${OUT}/routed-retrieval-query.json"

cp "${OUT}/routed-retrieval-query.json" "${OUT}/general-routing-decision-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/general-routing-decision-request.json" \
  "${BASE_URL}/api/memory/retrieval/router/decision" \
  > "${OUT}/general-routing-decision.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/routed-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/router/query" \
  > "${OUT}/routed-retrieval-result.json"

cp "${OUT}/routing-decision-request.json" "${OUT}/filtered-routed-retrieval-query.json"
curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/filtered-routed-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/router/query" \
  > "${OUT}/filtered-routed-retrieval-result.json"

cp "${OUT}/query-type-request.json" "${OUT}/sovereign-routed-retrieval-query.json"
curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/sovereign-routed-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/router/query" \
  > "${OUT}/sovereign-routed-retrieval-result.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-routed-retrieval.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${PROGRAM_URL}/context-packet" \
  > "${OUT}/program-context-packet-with-routed-retrieval.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/routed-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/router/query" \
  > "${OUT}/routed-retrieval-result-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-routed-retrieval-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${PROGRAM_URL}/context-packet" \
  > "${OUT}/program-context-packet-with-routed-retrieval-after-restart.json"

jq -n \
  --arg phase "B22.7" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg general_backend "${EXPECTED_GENERAL_DENSE}" \
  --arg code_backend "${EXPECTED_CODE_DENSE}" \
  --arg sovereign_backend "${EXPECTED_SOVEREIGN_DENSE}" \
  --arg sparse_backend "${EXPECTED_SPARSE}" \
  --slurpfile query_type "${OUT}/query-type.json" \
  --slurpfile code_decision "${OUT}/routing-decision.json" \
  --slurpfile general_decision "${OUT}/general-routing-decision.json" \
  --slurpfile general_result "${OUT}/routed-retrieval-result.json" \
  --slurpfile filtered_result "${OUT}/filtered-routed-retrieval-result.json" \
  --slurpfile sovereign_result "${OUT}/sovereign-routed-retrieval-result.json" \
  --slurpfile workstream_packet "${OUT}/context-packet-with-routed-retrieval.json" \
  --slurpfile program_packet "${OUT}/program-context-packet-with-routed-retrieval.json" \
  --slurpfile restart_result "${OUT}/routed-retrieval-result-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    general_backend: $general_backend,
    code_backend: $code_backend,
    sovereign_backend: $sovereign_backend,
    sparse_backend: $sparse_backend,
    general_query_type: $general_result[0].query_type,
    code_query_type: $code_decision[0].query_type,
    sovereign_query_type: $query_type[0].selected_query_type,
    general_selected_backend: $general_result[0].routing_decision.selected_dense_backend,
    code_selected_backend: $code_decision[0].selected_dense_backend,
    sovereign_selected_backend: $sovereign_result[0].routing_decision.selected_dense_backend,
    retrieval_query_type_works: (
      $general_result[0].query_type == "general" and
      $code_decision[0].query_type == "code" and
      $query_type[0].selected_query_type == "sovereign"
    ),
    routing_decision_works: (
      $general_decision[0].selected_dense_backend == $general_backend and
      $code_decision[0].selected_dense_backend == $code_backend and
      $sovereign_result[0].routing_decision.selected_dense_backend == $sovereign_backend
    ),
    general_hit_count: ($general_result[0].hits | length),
    code_hit_count: ($filtered_result[0].hits | length),
    sovereign_hit_count: ($sovereign_result[0].hits | length),
    filtered_hit_count: ($filtered_result[0].hits | length),
    filtered_repo_match_count: ($filtered_result[0].hits | map(select(.point.payload.repo_path == "beagle/crates/beagle-darwin/src/workspace_attach.rs")) | length),
    filtered_file_type_match_count: ($filtered_result[0].hits | map(select(.point.payload.file_type == "rust")) | length),
    workstream_context_present: ($workstream_packet[0].packet.retrieval_context != null),
    workstream_query_type: $workstream_packet[0].packet.retrieval_context.query_type,
    program_context_present: ($program_packet[0].packet.retrieval_context != null),
    program_query_type: $program_packet[0].packet.retrieval_context.query_type,
    restart_recovered_session: (
      ($restart_result[0].hits | length) >= 1 and
      ($restart_result[0].hits[0].point.payload.session_id == $session_id)
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health
