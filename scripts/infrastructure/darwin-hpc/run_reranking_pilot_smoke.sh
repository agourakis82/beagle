#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/reranking-pilot}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18482}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-codex}"
EXPECTED_ROLE="${EXPECTED_ROLE:-assistant}"
EXPECTED_GENERAL_DENSE="${EXPECTED_GENERAL_DENSE:-voyage-4-large}"
EXPECTED_SOVEREIGN_DENSE="${EXPECTED_SOVEREIGN_DENSE:-bge-m3}"
EXPECTED_SPARSE="${EXPECTED_SPARSE:-local-lexical}"
EXPECTED_GENERAL_RERANKER="${EXPECTED_GENERAL_RERANKER:-voyage-rerank-2.5}"
EXPECTED_SOVEREIGN_RERANKER="${EXPECTED_SOVEREIGN_RERANKER:-Alibaba-NLP/gte-reranker-modernbert-base}"
RERANK_RATE_LIMIT_RESET_SECONDS="${RERANK_RATE_LIMIT_RESET_SECONDS:-65}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
RETRIEVAL_SOURCE_FILE="${RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
CORE_CONTEXT_SOURCE_FILE="${CORE_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-core/src/context.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
K8S_CONFIGMAP_FILE="${K8S_CONFIGMAP_FILE:-${ROOT}/k8s/beagle/configmap.yaml}"
K8S_KUSTOMIZATION_FILE="${K8S_KUSTOMIZATION_FILE:-${ROOT}/k8s/beagle/kustomization.yaml}"
SOVEREIGN_RERANKER_DEPLOYMENT_FILE="${SOVEREIGN_RERANKER_DEPLOYMENT_FILE:-${ROOT}/k8s/beagle/sovereign-reranker-deployment.yaml}"
SOVEREIGN_RERANKER_SERVICE_FILE="${SOVEREIGN_RERANKER_SERVICE_FILE:-${ROOT}/k8s/beagle/sovereign-reranker-service.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B228_LATE_INTERACTION_RERANKING_PILOT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B228_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B228_KNOWN_LIMITS.md}"
RERANKING_PROFILE_CONTRACT_FILE="${RERANKING_PROFILE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/reranking-profile-schema.yaml}"
RERANKED_RESULT_CONTRACT_FILE="${RERANKED_RESULT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/reranked-result-schema.yaml}"
PRIOR_ROUTER_ARTIFACT_DIR="${PRIOR_ROUTER_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/multi-backend-retrieval-router}"
TAG="${TAG:-b228-reranking-pilot}"

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
K8S_CONFIGMAP_PRESENT=0
K8S_KUSTOMIZATION_PRESENT=0
SOVEREIGN_RERANKER_DEPLOYMENT_PRESENT=0
SOVEREIGN_RERANKER_SERVICE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
RERANKING_PROFILE_CONTRACT_PRESENT=0
RERANKED_RESULT_CONTRACT_PRESENT=0
PRIOR_ROUTER_ARTIFACTS_PRESENT=0

if rg -q "reranked_routed_retrieve|rerank_hits_for_lane|RerankerClient" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "RerankedResult|RERANKED_RESULT_VERSION|RerankingLatencyComparison|RerankingRecommendation" "${RETRIEVAL_SOURCE_FILE}"; then
  RETRIEVAL_SOURCE_PRESENT=1
fi
if rg -q "RerankedResult|RerankingLatencyComparison|RerankingRecommendation" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "memory_reranked_routed_retrieve" "${CORE_CONTEXT_SOURCE_FILE}"; then
  CORE_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "reranking_applied: bool|reranker_backend: Option<String>|reranking_latency_ms: Option<u64>" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "reranking_applied: bool|reranker_backend: Option<String>|reranking_latency_ms: Option<u64>" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/retrieval/reranking-profile|/api/memory/retrieval/rerank/pilot|memory_reranked_retrieval_query_handler" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
if rg -q "memory_reranked_routed_retrieve|context_packet_memory_hit_from_reranked_hit|retrieval_guidance_from_reranked_hits" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if rg -q "BEAGLE_MEMORY_RERANKING_URL|BEAGLE_MEMORY_SOVEREIGN_RERANKING_URL" "${K8S_CONFIGMAP_FILE}"; then
  K8S_CONFIGMAP_PRESENT=1
fi
if rg -q "sovereign-reranker-deployment.yaml|sovereign-reranker-service.yaml" "${K8S_KUSTOMIZATION_FILE}"; then
  K8S_KUSTOMIZATION_PRESENT=1
fi
[[ -f "${SOVEREIGN_RERANKER_DEPLOYMENT_FILE}" ]] && SOVEREIGN_RERANKER_DEPLOYMENT_PRESENT=1
[[ -f "${SOVEREIGN_RERANKER_SERVICE_FILE}" ]] && SOVEREIGN_RERANKER_SERVICE_PRESENT=1
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${RERANKING_PROFILE_CONTRACT_FILE}" ]] && RERANKING_PROFILE_CONTRACT_PRESENT=1
[[ -f "${RERANKED_RESULT_CONTRACT_FILE}" ]] && RERANKED_RESULT_CONTRACT_PRESENT=1
if [[ -f "${PRIOR_ROUTER_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_ROUTER_ARTIFACT_DIR}/routed-retrieval-result.json" ]]; then
  PRIOR_ROUTER_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --arg expected_general_dense "${EXPECTED_GENERAL_DENSE}" \
  --arg expected_sovereign_dense "${EXPECTED_SOVEREIGN_DENSE}" \
  --arg expected_sparse "${EXPECTED_SPARSE}" \
  --arg expected_general_reranker "${EXPECTED_GENERAL_RERANKER}" \
  --arg expected_sovereign_reranker "${EXPECTED_SOVEREIGN_RERANKER}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson retrieval_source_present "${RETRIEVAL_SOURCE_PRESENT}" \
  --argjson memory_lib_source_present "${MEMORY_LIB_SOURCE_PRESENT}" \
  --argjson core_context_source_present "${CORE_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson k8s_configmap_present "${K8S_CONFIGMAP_PRESENT}" \
  --argjson k8s_kustomization_present "${K8S_KUSTOMIZATION_PRESENT}" \
  --argjson sovereign_reranker_deployment_present "${SOVEREIGN_RERANKER_DEPLOYMENT_PRESENT}" \
  --argjson sovereign_reranker_service_present "${SOVEREIGN_RERANKER_SERVICE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson reranking_profile_contract_present "${RERANKING_PROFILE_CONTRACT_PRESENT}" \
  --argjson reranked_result_contract_present "${RERANKED_RESULT_CONTRACT_PRESENT}" \
  --argjson prior_router_artifacts_present "${PRIOR_ROUTER_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    expected_general_dense: $expected_general_dense,
    expected_sovereign_dense: $expected_sovereign_dense,
    expected_sparse: $expected_sparse,
    expected_general_reranker: $expected_general_reranker,
    expected_sovereign_reranker: $expected_sovereign_reranker,
    engine_source_present: $engine_source_present,
    retrieval_source_present: $retrieval_source_present,
    memory_lib_source_present: $memory_lib_source_present,
    core_context_source_present: $core_context_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    http_memory_source_present: $http_memory_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    k8s_configmap_present: $k8s_configmap_present,
    k8s_kustomization_present: $k8s_kustomization_present,
    sovereign_reranker_deployment_present: $sovereign_reranker_deployment_present,
    sovereign_reranker_service_present: $sovereign_reranker_service_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    reranking_profile_contract_present: $reranking_profile_contract_present,
    reranked_result_contract_present: $reranked_result_contract_present,
    prior_router_artifacts_present: $prior_router_artifacts_present
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
  --arg conversation_id "b228-general-primary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B22.8 canonical operator workstream context packet memory for campaign governance cadence and launch rhythm." \
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
    tags: [$workstream_id, $tag, "general", "rerank"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b228-general-primary"],
    claim_refs: ["claim:b228-general-primary"]
  }' > "${OUT}/general-primary-ingest.json"
ingest_memory "${OUT}/general-primary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b228-general-secondary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B22.8 latency comparison note for the same campaign context with evidence handoff and reviewer pacing." \
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
    tags: [$workstream_id, $tag, "general", "rerank"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b228-general-secondary"],
    claim_refs: ["claim:b228-general-secondary"]
  }' > "${OUT}/general-secondary-ingest.json"
ingest_memory "${OUT}/general-secondary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b228-sovereign-primary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Consulta multilíngue sobre memória soberana, privacidade do workspace e contexto offline do mesmo workstream canônico." \
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
    result_refs: ["result:b228-sovereign-primary"],
    claim_refs: ["claim:b228-sovereign-primary"]
  }' > "${OUT}/sovereign-primary-ingest.json"
ingest_memory "${OUT}/sovereign-primary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b228-sovereign-secondary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Memoria soberana multilanguage para auditoria privada, recuperação offline e contexto do operador em português e español." \
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
    turn_index: 4,
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
    result_refs: ["result:b228-sovereign-secondary"],
    claim_refs: ["claim:b228-sovereign-secondary"]
  }' > "${OUT}/sovereign-secondary-ingest.json"
ingest_memory "${OUT}/sovereign-secondary-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${BASE_URL}/api/memory/retrieval/reranking-profile" \
  > "${OUT}/reranking-profile.json"

jq -n \
  --arg query "operator governance cadence for the current campaign context packet" \
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
    query_type_hint: "general",
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      role: $role,
      domain: $domain,
      tags: [$tag, "general"]
    },
    rerank_hint: "workstream-context-packet"
  }' > "${OUT}/general-rerank-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/general-rerank-query.json" \
  "${BASE_URL}/api/memory/retrieval/router/query" \
  > "${OUT}/prerank-result.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/general-rerank-query.json" \
  "${BASE_URL}/api/memory/retrieval/rerank/pilot" \
  > "${OUT}/postrank-result.json"

jq -n \
  --arg query "consulta multilíngue sobre privacidade e memória soberana do workspace" \
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
    dense_weight: 0.7,
    sparse_weight: 0.3,
    query_type_hint: "sovereign",
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      role: $role,
      domain: $domain,
      tags: [$tag, "sovereign"]
    },
    rerank_hint: "sovereign-multilingual"
  }' > "${OUT}/sovereign-rerank-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/sovereign-rerank-query.json" \
  "${BASE_URL}/api/memory/retrieval/router/query" \
  > "${OUT}/sovereign-prerank-result.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/sovereign-rerank-query.json" \
  "${BASE_URL}/api/memory/retrieval/rerank/pilot" \
  > "${OUT}/sovereign-postrank-result.json"

jq -n \
  --slurpfile general "${OUT}/postrank-result.json" \
  --slurpfile sovereign "${OUT}/sovereign-postrank-result.json" \
  '{
    general: $general[0].latency,
    sovereign: $sovereign[0].latency
  }' > "${OUT}/latency-comparison.json"

jq -n \
  --slurpfile general "${OUT}/postrank-result.json" \
  --slurpfile sovereign "${OUT}/sovereign-postrank-result.json" \
  '{
    general: $general[0].recommendation,
    sovereign: $sovereign[0].recommendation,
    note: "B22.8 keeps reranking bounded and compares general versus sovereign lane behavior explicitly."
  }' > "${OUT}/reranking-recommendation.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-reranked-retrieval.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${PROGRAM_URL}/context-packet" \
  > "${OUT}/program-context-packet-with-reranked-retrieval.json"

# The live Voyage key on this cluster is still in the low-RPM bucket.
# Give the minute window time to reset before exercising the same general
# reranker again after restart so the pilot proves runtime coherence
# instead of tripping provider throttling.
sleep "${RERANK_RATE_LIMIT_RESET_SECONDS}"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/general-rerank-query.json" \
  "${BASE_URL}/api/memory/retrieval/rerank/pilot" \
  > "${OUT}/postrank-result-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-reranked-retrieval-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${PROGRAM_URL}/context-packet" \
  > "${OUT}/program-context-packet-with-reranked-retrieval-after-restart.json"

jq -n \
  --arg phase "B22.8" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg general_dense_backend "${EXPECTED_GENERAL_DENSE}" \
  --arg sovereign_dense_backend "${EXPECTED_SOVEREIGN_DENSE}" \
  --arg sparse_backend "${EXPECTED_SPARSE}" \
  --arg general_reranker_backend "${EXPECTED_GENERAL_RERANKER}" \
  --arg sovereign_reranker_backend "${EXPECTED_SOVEREIGN_RERANKER}" \
  --slurpfile prerank "${OUT}/prerank-result.json" \
  --slurpfile postrank "${OUT}/postrank-result.json" \
  --slurpfile sovereign_prerank "${OUT}/sovereign-prerank-result.json" \
  --slurpfile sovereign_postrank "${OUT}/sovereign-postrank-result.json" \
  --slurpfile workstream_packet "${OUT}/context-packet-with-reranked-retrieval.json" \
  --slurpfile program_packet "${OUT}/program-context-packet-with-reranked-retrieval.json" \
  --slurpfile restart_postrank "${OUT}/postrank-result-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    general_dense_backend: $general_dense_backend,
    sovereign_dense_backend: $sovereign_dense_backend,
    sparse_backend: $sparse_backend,
    general_reranker_backend: $general_reranker_backend,
    sovereign_reranker_backend: $sovereign_reranker_backend,
    general_reranking_applied: $postrank[0].reranking_applied,
    sovereign_reranking_applied: $sovereign_postrank[0].reranking_applied,
    general_prerank_hit_count: ($prerank[0].hits | length),
    general_postrank_hit_count: $postrank[0].postrank_hit_count,
    sovereign_prerank_hit_count: ($sovereign_prerank[0].hits | length),
    sovereign_postrank_hit_count: $sovereign_postrank[0].postrank_hit_count,
    payload_filters_preserved: (
      ($postrank[0].hits | all(.[]; .point.payload.workstream_id == $workstream_id and .point.payload.campaign_id == $campaign_id and .point.payload.session_id == $session_id)) and
      ($sovereign_postrank[0].hits | all(.[]; .point.payload.workstream_id == $workstream_id and .point.payload.campaign_id == $campaign_id and .point.payload.session_id == $session_id))
    ),
    workstream_context_reranking_applied: $workstream_packet[0].packet.retrieval_context.reranking_applied,
    workstream_context_reranker_backend: $workstream_packet[0].packet.retrieval_context.reranker_backend,
    program_context_reranking_applied: $program_packet[0].packet.retrieval_context.reranking_applied,
    program_context_reranker_backend: $program_packet[0].packet.retrieval_context.reranker_backend,
    restart_recovered_session: (
      $restart_postrank[0].reranking_applied == true and
      ($restart_postrank[0].hits | length) >= 1 and
      ($restart_postrank[0].hits[0].point.payload.session_id == $session_id)
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health
