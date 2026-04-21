#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/retrieval-benchmark-harness}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18473}"
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
MEMORY_RETRIEVAL_SOURCE_FILE="${MEMORY_RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_HTTP_SOURCE_FILE="${MEMORY_HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
BENCHMARK_CONTRACT_FILE="${BENCHMARK_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-benchmark-schema.yaml}"
BACKEND_MATRIX_CONTRACT_FILE="${BACKEND_MATRIX_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/embedding-backend-matrix.yaml}"
RERANKING_CONTRACT_FILE="${RERANKING_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/reranking-profile-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B222_RETRIEVAL_TECH_AUDIT_AND_BENCHMARK_HARNESS.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B222_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B222_KNOWN_LIMITS.md}"

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
BENCHMARK_CONTRACT_PRESENT=0
BACKEND_MATRIX_CONTRACT_PRESENT=0
RERANKING_CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "benchmark_retrieval|embedding_backend_matrix|reranking_profile" "${MEMORY_ENGINE_SOURCE_FILE}"; then
  MEMORY_ENGINE_PRESENT=1
fi
if rg -q "RetrievalBenchmark|EmbeddingBackendMatrix|RerankingProfile" "${MEMORY_RETRIEVAL_SOURCE_FILE}"; then
  MEMORY_RETRIEVAL_PRESENT=1
fi
if rg -q "/api/memory/retrieval/backend-matrix|/api/memory/retrieval/reranking-profile|/api/memory/retrieval/benchmark" "${MEMORY_HTTP_SOURCE_FILE}"; then
  MEMORY_HTTP_PRESENT=1
fi
[[ -f "${BENCHMARK_CONTRACT_FILE}" ]] && BENCHMARK_CONTRACT_PRESENT=1
[[ -f "${BACKEND_MATRIX_CONTRACT_FILE}" ]] && BACKEND_MATRIX_CONTRACT_PRESENT=1
[[ -f "${RERANKING_CONTRACT_FILE}" ]] && RERANKING_CONTRACT_PRESENT=1
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson memory_engine_present "${MEMORY_ENGINE_PRESENT}" \
  --argjson memory_retrieval_present "${MEMORY_RETRIEVAL_PRESENT}" \
  --argjson memory_http_present "${MEMORY_HTTP_PRESENT}" \
  --argjson benchmark_contract_present "${BENCHMARK_CONTRACT_PRESENT}" \
  --argjson backend_matrix_contract_present "${BACKEND_MATRIX_CONTRACT_PRESENT}" \
  --argjson reranking_contract_present "${RERANKING_CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    memory_engine_present: $memory_engine_present,
    memory_retrieval_present: $memory_retrieval_present,
    memory_http_present: $memory_http_present,
    benchmark_contract_present: $benchmark_contract_present,
    backend_matrix_contract_present: $backend_matrix_contract_present,
    reranking_contract_present: $reranking_contract_present,
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
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/backend-matrix" \
  > "${OUT}/backend-matrix.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/reranking-profile" \
  > "${OUT}/reranking-profile.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b222-benchmark-prose" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 1,
    role: $role,
    text: "B222 retrieval benchmark harness canonical prose memory point. hybrid retrieval benchmark beagle spine. beagle-darwin-hpc-governance expedition-002-hrv-aware beagle-cluster-pilot ws-cluster-workspace-habitat.",
    tags: ["retrieval-benchmark", "b222", "prose"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    physio_snapshot_ref: "physio:latest",
    result_refs: ["result:b222-prose"],
    claim_refs: ["claim:b222-prose"]
  }' > "${OUT}/canonical-prose-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/canonical-prose-ingest.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/canonical-prose-ingest-response.json"

jq -n \
  --arg workstream_id "other-workstream" \
  --arg campaign_id "other-campaign" \
  --arg program_id "other-program" \
  --arg workspace_id "other-workspace" \
  --arg session_id "other-session" \
  '{
    source: "claude",
    conversation_id: "b222-benchmark-decoy",
    turn_index: 1,
    role: "assistant",
    text: "B222 retrieval benchmark harness decoy memory point. hybrid retrieval benchmark beagle spine. other-workstream other-session.",
    tags: ["retrieval-benchmark", "b222", "decoy"],
    domain: "beagle-engine",
    provider: "claude",
    model: "sonnet",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b222-decoy"],
    claim_refs: ["claim:b222-decoy"]
  }' > "${OUT}/decoy-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/decoy-ingest.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/decoy-ingest-response.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    source: $source,
    conversation_id: "b222-benchmark-code",
    turn_index: 1,
    role: $role,
    text: "fn benchmark_retrieval(query: RetrievalQuery) -> RetrievalBenchmarkReport { hybrid_retrieve(query) } // B222 code retrieval benchmark",
    tags: ["retrieval-benchmark", "b222", "code"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b222-code"],
    claim_refs: ["claim:b222-code"]
  }' > "${OUT}/code-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/code-ingest.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/code-ingest-response.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    source: $source,
    conversation_id: "b222-benchmark-multilingual",
    turn_index: 1,
    role: $role,
    text: "Espinha de recuperacao hibrida B222 para o Beagle. Hybrid retrieval benchmark spine for multilingual readiness.",
    tags: ["retrieval-benchmark", "b222", "multilingual"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b222-multilingual"],
    claim_refs: ["claim:b222-multilingual"]
  }' > "${OUT}/multilingual-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/multilingual-ingest.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/ingest_chat" \
  > "${OUT}/multilingual-ingest-response.json"

CANONICAL_ID="$(jq -r '.memory_id' "${OUT}/canonical-prose-ingest-response.json")"
DECOY_ID="$(jq -r '.memory_id' "${OUT}/decoy-ingest-response.json")"
CODE_ID="$(jq -r '.memory_id' "${OUT}/code-ingest-response.json")"
MULTILINGUAL_ID="$(jq -r '.memory_id' "${OUT}/multilingual-ingest-response.json")"

jq -n \
  '{
    query_text: "B22.2 retrieval benchmark harness beagle hybrid retrieval spine",
    top_k: 5,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      domain: "beagle-engine",
      tags: ["retrieval-benchmark", "b222"]
    },
    rerank_hint: "b222-baseline"
  }' > "${OUT}/retrieval-baseline-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/retrieval-baseline-query.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/query" \
  > "${OUT}/retrieval-baseline.json"

jq -n \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  '{
    query_text: "B22.2 retrieval benchmark harness canonical prose beagle",
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
      tags: ["retrieval-benchmark", "b222", "prose"]
    },
    rerank_hint: "b222-filtered"
  }' > "${OUT}/filtered-retrieval-baseline-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/filtered-retrieval-baseline-query.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/query" \
  > "${OUT}/filtered-retrieval-baseline.json"

jq -n \
  --arg benchmark_version "beagle-retrieval-benchmark-v1" \
  --arg reranking_profile_id "b222-late-interaction-hook" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "${EXPECTED_DOMAIN}" \
  --arg canonical_id "${CANONICAL_ID}" \
  --arg decoy_id "${DECOY_ID}" \
  --arg code_id "${CODE_ID}" \
  --arg multilingual_id "${MULTILINGUAL_ID}" \
  '{
    benchmark_version: $benchmark_version,
    top_k_stability_runs: 2,
    reranking_profile_id: $reranking_profile_id,
    cases: [
      {
        case_id: "baseline-prose",
        case_kind: "prose",
        description: "Current prose retrieval baseline",
        query_text: "B22.2 retrieval benchmark harness beagle hybrid retrieval spine",
        top_k: 5,
        dense_enabled: true,
        sparse_enabled: true,
        dense_weight: 0.65,
        sparse_weight: 0.35,
        filters: {
          domain: $domain,
          tags: ["retrieval-benchmark", "b222"]
        },
        expected_memory_ids: [$canonical_id, $decoy_id, $code_id, $multilingual_id]
      },
      {
        case_id: "filtered-prose",
        case_kind: "filtered-prose",
        description: "Payload-filtered prose retrieval",
        query_text: "B22.2 retrieval benchmark harness canonical prose beagle",
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
          tags: ["retrieval-benchmark", "b222", "prose"]
        },
        expected_memory_ids: [$canonical_id]
      },
      {
        case_id: "code-lane",
        case_kind: "code",
        description: "Code retrieval behavior",
        query_text: "fn benchmark_retrieval hybrid_retrieve RetrievalBenchmarkReport",
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
          tags: ["retrieval-benchmark", "b222", "code"]
        },
        expected_memory_ids: [$code_id]
      },
      {
        case_id: "multilingual-proxy",
        case_kind: "multilingual",
        description: "Bounded multilingual proxy behavior",
        query_text: "espinha de recuperacao hibrida benchmark beagle",
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
          tags: ["retrieval-benchmark", "b222", "multilingual"]
        },
        expected_memory_ids: [$multilingual_id]
      }
    ]
  }' > "${OUT}/benchmark-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/benchmark-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/benchmark" \
  > "${OUT}/benchmark-summary.json"

jq '.recommendation' "${OUT}/benchmark-summary.json" > "${OUT}/recommendation.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"
stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/benchmark-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/memory/retrieval/benchmark" \
  > "${OUT}/benchmark-summary-after-restart.json"

jq -n \
  --arg phase "B22.2" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --slurpfile matrix "${OUT}/backend-matrix.json" \
  --slurpfile reranking "${OUT}/reranking-profile.json" \
  --slurpfile baseline "${OUT}/retrieval-baseline.json" \
  --slurpfile filtered "${OUT}/filtered-retrieval-baseline.json" \
  --slurpfile benchmark "${OUT}/benchmark-summary.json" \
  --slurpfile benchmark_restart "${OUT}/benchmark-summary-after-restart.json" \
  --slurpfile recommendation "${OUT}/recommendation.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    collection_name: $benchmark[0].collection_name,
    dense_backend: $benchmark[0].dense_backend,
    sparse_backend: $benchmark[0].sparse_backend,
    backend_count: ($matrix[0].backends | length),
    benchmark_case_count: ($benchmark[0].summary.case_count),
    baseline_hit_count: ($baseline[0].hits | length),
    filtered_hit_count: ($filtered[0].hits | length),
    average_filter_correctness: $benchmark[0].summary.average_filter_correctness,
    average_relevance_proxy: $benchmark[0].summary.average_relevance_proxy,
    context_packet_usable_case_count: $benchmark[0].summary.context_packet_usable_case_count,
    keep_qdrant: $recommendation[0].keep_qdrant,
    dense_backend_recommendation: $recommendation[0].dense_backend_recommendation,
    reranking_recommendation: $recommendation[0].reranking_recommendation,
    recommendation_state: "bounded-upgrade-path-present",
    reranking_state: $reranking[0].current_state,
    restart_recovered_session: (
      $benchmark[0].dense_backend == $benchmark_restart[0].dense_backend and
      $benchmark[0].sparse_backend == $benchmark_restart[0].sparse_backend and
      (($benchmark[0].cases | map({id: .case_id, top_hit: .top_hit_memory_id})) ==
       ($benchmark_restart[0].cases | map({id: .case_id, top_hit: .top_hit_memory_id}))) and
      $recommendation[0] == $benchmark_restart[0].recommendation
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health
