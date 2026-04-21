#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/retrieval-feedback-loop}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18492}"
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
TAG="${TAG:-b229-feedback-loop}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
RETRIEVAL_SOURCE_FILE="${RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B229_RETRIEVAL_EVALUATION_AND_RELEVANCE_FEEDBACK_LOOP.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B229_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B229_KNOWN_LIMITS.md}"
FEEDBACK_CONTRACT_FILE="${FEEDBACK_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/relevance-feedback-schema.yaml}"
EVAL_CONTRACT_FILE="${EVAL_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-eval-report-schema.yaml}"
POLICY_CONTRACT_FILE="${POLICY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/retrieval-policy-schema.yaml}"
PRIOR_RERANKING_ARTIFACT_DIR="${PRIOR_RERANKING_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/reranking-pilot}"

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
HTTP_MEMORY_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
FEEDBACK_CONTRACT_PRESENT=0
EVAL_CONTRACT_PRESENT=0
POLICY_CONTRACT_PRESENT=0
PRIOR_RERANKING_ARTIFACTS_PRESENT=0

if rg -q "evaluate_retrieval|feedback_adjusted_routed_retrieve|derive_retrieval_policy" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "RELEVANCE_FEEDBACK_VERSION|RETRIEVAL_EVAL_REPORT_VERSION|RETRIEVAL_POLICY_VERSION" "${RETRIEVAL_SOURCE_FILE}"; then
  RETRIEVAL_SOURCE_PRESENT=1
fi
if rg -q "RetrievalEvalReport|RelevanceFeedbackInput|RetrievalPolicy" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/retrieval/evaluate|/api/memory/retrieval/feedback|/api/memory/retrieval/policy/derive" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${FEEDBACK_CONTRACT_FILE}" ]] && FEEDBACK_CONTRACT_PRESENT=1
[[ -f "${EVAL_CONTRACT_FILE}" ]] && EVAL_CONTRACT_PRESENT=1
[[ -f "${POLICY_CONTRACT_FILE}" ]] && POLICY_CONTRACT_PRESENT=1
if [[ -f "${PRIOR_RERANKING_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_RERANKING_ARTIFACT_DIR}/postrank-result.json" ]]; then
  PRIOR_RERANKING_ARTIFACTS_PRESENT=1
fi

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
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson feedback_contract_present "${FEEDBACK_CONTRACT_PRESENT}" \
  --argjson eval_contract_present "${EVAL_CONTRACT_PRESENT}" \
  --argjson policy_contract_present "${POLICY_CONTRACT_PRESENT}" \
  --argjson prior_reranking_artifacts_present "${PRIOR_RERANKING_ARTIFACTS_PRESENT}" \
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
    http_memory_source_present: $http_memory_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    feedback_contract_present: $feedback_contract_present,
    eval_contract_present: $eval_contract_present,
    policy_contract_present: $policy_contract_present,
    prior_reranking_artifacts_present: $prior_reranking_artifacts_present
  }' > "${OUT}/source-summary.json"

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

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
  --arg conversation_id "b229-general-primary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B22.9 general retrieval evaluation for campaign cadence, workstream governance, and tool launch context." \
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
    tags: [$workstream_id, $tag, "general", "eval"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b229-general-primary"],
    claim_refs: ["claim:b229-general-primary"]
  }' > "${OUT}/general-primary-ingest.json"
ingest_memory "${OUT}/general-primary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b229-general-secondary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "B22.9 general retrieval secondary memory for launch resume and campaign pacing comparison." \
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
    tags: [$workstream_id, $tag, "general", "eval"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b229-general-secondary"],
    claim_refs: ["claim:b229-general-secondary"]
  }' > "${OUT}/general-secondary-ingest.json"
ingest_memory "${OUT}/general-secondary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b229-code-primary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "workspace_exec_proxy shell helper for ssh port forward attach and rollout handling." \
  --arg domain "darwin-hpc" \
  --arg repo_path "beagle/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh" \
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
    tags: [$workstream_id, $tag, "code", "eval"],
    domain: $domain,
    repo_path: $repo_path,
    file_type: $file_type,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b229-code-primary"],
    claim_refs: ["claim:b229-code-primary"]
  }' > "${OUT}/code-primary-ingest.json"
ingest_memory "${OUT}/code-primary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b229-code-secondary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "http_memory routes for retrieval feedback policy derive and evaluation output." \
  --arg domain "darwin-hpc" \
  --arg repo_path "beagle/apps/beagle-monorepo/src/http_memory.rs" \
  --arg file_type "rust" \
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
    tags: [$workstream_id, $tag, "code", "eval"],
    domain: $domain,
    repo_path: $repo_path,
    file_type: $file_type,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b229-code-secondary"],
    claim_refs: ["claim:b229-code-secondary"]
  }' > "${OUT}/code-secondary-ingest.json"
ingest_memory "${OUT}/code-secondary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b229-sovereign-primary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Consulta multilíngue sobre memória soberana, privacidade do workspace e contexto offline." \
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
    turn_index: 5,
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
    result_refs: ["result:b229-sovereign-primary"],
    claim_refs: ["claim:b229-sovereign-primary"]
  }' > "${OUT}/sovereign-primary-ingest.json"
ingest_memory "${OUT}/sovereign-primary-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b229-sovereign-secondary" \
  --arg role "${EXPECTED_ROLE}" \
  --arg text "Memoria soberana multilanguage para auditoria privada e recuperación offline del mismo workspace." \
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
    turn_index: 6,
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
    result_refs: ["result:b229-sovereign-secondary"],
    claim_refs: ["claim:b229-sovereign-secondary"]
  }' > "${OUT}/sovereign-secondary-ingest.json"
ingest_memory "${OUT}/sovereign-secondary-ingest.json"

jq -n \
  --arg tag "${TAG}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "darwin-hpc" \
  '{
    report_version: "beagle-retrieval-eval-report-v1",
    top_k_stability_runs: 1,
    cases: [
      {
        case_id: "general-governance",
        query_type: "general",
        description: "general workstream and campaign context retrieval",
        query_text: "campaign cadence and tool launch context",
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
        rerank_hint: "b229-general-eval",
        expected_memory_ids: []
      },
      {
        case_id: "code-memory-routes",
        query_type: "code",
        description: "repo-native retrieval over code and scripts",
        query_text: "workspace proxy retrieval feedback route",
        top_k: 3,
        dense_enabled: true,
        sparse_enabled: true,
        dense_weight: 0.75,
        sparse_weight: 0.25,
        query_type_hint: "code",
        filters: {
          workstream_id: $workstream_id,
          campaign_id: $campaign_id,
          session_id: $session_id,
          source: $source,
          role: $role,
          domain: $domain,
          tags: [$tag, "code"]
        },
        rerank_hint: "b229-code-eval",
        expected_memory_ids: []
      },
      {
        case_id: "sovereign-multilingual",
        query_type: "sovereign",
        description: "multilingual sovereign retrieval",
        query_text: "consulta soberana de privacidad y memoria offline",
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
        rerank_hint: "b229-sovereign-eval",
        expected_memory_ids: []
      }
    ]
  }' > "${OUT}/eval-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/eval-request.json" \
  "${BASE_URL}/api/memory/retrieval/evaluate" \
  > "${OUT}/retrieval-eval-report.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/retrieval-eval-report.json" \
  "${BASE_URL}/api/memory/retrieval/policy/derive" \
  > "${OUT}/retrieval-policy.json"

jq -n \
  --arg tag "${TAG}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg role "${EXPECTED_ROLE}" \
  --arg domain "darwin-hpc" \
  '{
    feedback_version: "beagle-relevance-feedback-v1",
    feedback_round: 1,
    query_text: "workspace proxy retrieval feedback route",
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.75,
    sparse_weight: 0.25,
    query_type_hint: "code",
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      role: $role,
      domain: $domain,
      tags: [$tag, "code"]
    },
    rerank_hint: "b229-feedback-code",
    expected_memory_ids: [],
    judgments: [
      {
        memory_id: "PLACEHOLDER_PRIMARY",
        signal: "negative",
        score: 0.7,
        rationale: "The script helper is useful, but the HTTP route file is the desired target for this refinement."
      },
      {
        memory_id: "PLACEHOLDER_SECONDARY",
        signal: "positive",
        score: 0.9,
        rationale: "The HTTP memory route is the preferred code surface for the retrieval feedback pilot."
      }
    ],
    note: "B22.9 bounded feedback loop over the code lane."
  }' > "${OUT}/feedback-input.template.json"

CODE_PRIMARY_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/code-primary-ingest-response.json")"
CODE_SECONDARY_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/code-secondary-ingest-response.json")"

jq \
  --arg primary "${CODE_PRIMARY_MEMORY_ID}" \
  --arg secondary "${CODE_SECONDARY_MEMORY_ID}" \
  '
  .judgments[0].memory_id = $primary |
  .judgments[1].memory_id = $secondary
  ' "${OUT}/feedback-input.template.json" > "${OUT}/feedback-input.json"

jq '{query_text, top_k, dense_enabled, sparse_enabled, dense_weight, sparse_weight, query_type_hint, filters, rerank_hint}' \
  "${OUT}/feedback-input.json" > "${OUT}/feedback-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/feedback-query.json" \
  "${BASE_URL}/api/memory/retrieval/rerank/pilot" \
  > "${OUT}/feedback-prerank.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/feedback-input.json" \
  "${BASE_URL}/api/memory/retrieval/feedback" \
  > "${OUT}/feedback-postrank.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/feedback-input.json" \
  "${BASE_URL}/api/memory/retrieval/feedback" \
  > "${OUT}/feedback-postrank-after-restart.json"

jq -n \
  --arg phase "B22.9" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --slurpfile eval "${OUT}/retrieval-eval-report.json" \
  --slurpfile prerank "${OUT}/feedback-prerank.json" \
  --slurpfile postrank "${OUT}/feedback-postrank.json" \
  --slurpfile policy "${OUT}/retrieval-policy.json" \
  --slurpfile restart_postrank "${OUT}/feedback-postrank-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    eval_case_count: ($eval[0].cases | length),
    eval_lane_count: ($eval[0].lanes | length),
    general_dense_backend: ($eval[0].lanes[] | select(.query_type == "general") | .dense_backend),
    code_dense_backend: ($eval[0].lanes[] | select(.query_type == "code") | .dense_backend),
    sovereign_dense_backend: ($eval[0].lanes[] | select(.query_type == "sovereign") | .dense_backend),
    feedback_query_type: $postrank[0].query_type,
    feedback_route: $postrank[0].routing_decision.selected_route,
    feedback_applied: $postrank[0].feedback_applied,
    top_hit_changed: $postrank[0].top_hit_changed,
    improvement_observed: $postrank[0].improvement_observed,
    payload_filters_preserved: (
      ($postrank[0].hits | all(.[]; .point.payload.workstream_id == $workstream_id and .point.payload.campaign_id == $campaign_id and .point.payload.session_id == $session_id))
    ),
    policy_lane_count: ($policy[0].lanes | length),
    code_policy_feedback_mode: ($policy[0].lanes[] | select(.query_type == "code") | .feedback_mode),
    restart_recovered_session: (
      $restart_postrank[0].feedback_applied == true and
      ($restart_postrank[0].hits | length) >= 1 and
      ($restart_postrank[0].hits[0].point.payload.session_id == $session_id)
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health
