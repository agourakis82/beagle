#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/code-retrieval-pilot}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18479}"
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
EXPECTED_SPARSE="${EXPECTED_SPARSE:-local-lexical}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
RETRIEVAL_SOURCE_FILE="${RETRIEVAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/retrieval.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B225_CODE_RETRIEVAL_PILOT_VOYAGE_CODE_3.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B225_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B225_KNOWN_LIMITS.md}"
QUERY_CONTRACT_FILE="${QUERY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/code-retrieval-query-schema.yaml}"
RESULT_CONTRACT_FILE="${RESULT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/code-retrieval-result-schema.yaml}"
RUST_REPO_PATH="${RUST_REPO_PATH:-beagle/crates/beagle-darwin/src/workspace_attach.rs}"
SCRIPT_REPO_PATH="${SCRIPT_REPO_PATH:-beagle/scripts/infrastructure/darwin-hpc/run_dense_backend_promotion_smoke.sh}"
CONFIG_REPO_PATH="${CONFIG_REPO_PATH:-beagle/k8s/beagle/configmap.yaml}"
TAG="${TAG:-b225-code-retrieval}"

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
QUERY_CONTRACT_PRESENT=0
RESULT_CONTRACT_PRESENT=0

if rg -q "code_retrieval_backend_profile|code_retrieve|repo_path|file_type" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "CodeRetrievalQuery|CodeRetrievalResult|CODE_RETRIEVAL_QUERY_VERSION" "${RETRIEVAL_SOURCE_FILE}"; then
  RETRIEVAL_SOURCE_PRESENT=1
fi
if rg -q "CodeRetrievalQuery|CodeRetrievalResult" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/retrieval/code/query" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${QUERY_CONTRACT_FILE}" ]] && QUERY_CONTRACT_PRESENT=1
[[ -f "${RESULT_CONTRACT_FILE}" ]] && RESULT_CONTRACT_PRESENT=1

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --arg expected_general_dense "${EXPECTED_GENERAL_DENSE}" \
  --arg expected_code_dense "${EXPECTED_CODE_DENSE}" \
  --arg expected_sparse "${EXPECTED_SPARSE}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson retrieval_source_present "${RETRIEVAL_SOURCE_PRESENT}" \
  --argjson memory_lib_source_present "${MEMORY_LIB_SOURCE_PRESENT}" \
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson query_contract_present "${QUERY_CONTRACT_PRESENT}" \
  --argjson result_contract_present "${RESULT_CONTRACT_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    expected_general_dense: $expected_general_dense,
    expected_code_dense: $expected_code_dense,
    expected_sparse: $expected_sparse,
    engine_source_present: $engine_source_present,
    retrieval_source_present: $retrieval_source_present,
    memory_lib_source_present: $memory_lib_source_present,
    http_memory_source_present: $http_memory_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    query_contract_present: $query_contract_present,
    result_contract_present: $result_contract_present
  }' > "${OUT}/source-summary.json"

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

ingest_memory_point() {
  local conversation_id="$1"
  local text="$2"
  local domain="$3"
  local repo_path="$4"
  local file_type="$5"

  jq -n \
    --arg source "${EXPECTED_SOURCE}" \
    --arg conversation_id "${conversation_id}" \
    --arg role "${EXPECTED_ROLE}" \
    --arg text "${text}" \
    --arg domain "${domain}" \
    --arg provider "codex" \
    --arg model "gpt-5.4" \
    --arg workstream_id "${EXPECTED_WORKSTREAM}" \
    --arg campaign_id "${EXPECTED_CAMPAIGN}" \
    --arg program_id "${EXPECTED_PROGRAM}" \
    --arg workspace_id "${EXPECTED_WORKSPACE}" \
    --arg session_id "${EXPECTED_SESSION}" \
    --arg repo_path "${repo_path}" \
    --arg file_type "${file_type}" \
    --arg tag "${TAG}" \
    '{
      source: $source,
      conversation_id: $conversation_id,
      turn_index: 0,
      role: $role,
      text: $text,
      tags: [$tag, $file_type],
      domain: $domain,
      provider: $provider,
      model: $model,
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      program_id: $program_id,
      workspace_id: $workspace_id,
      session_id: $session_id,
      repo_path: $repo_path,
      file_type: $file_type
    }' \
    | curl -fsS \
        -H "${AUTH_HEADER}" \
        -H "${CONSUMER_HEADER}" \
        -H 'Content-Type: application/json' \
        -d @- \
        "${BASE_URL}/api/memory/ingest_chat" >/dev/null
}

ingest_memory_point \
  "b225-rust-memory" \
  "fn build_workspace_attach() -> WorkspaceAttachResponse { managed_attach_state(); stable_alias(\"beagle-cluster-pilot.coder\"); }" \
  "beagle-engine" \
  "${RUST_REPO_PATH}" \
  "rust"

ingest_memory_point \
  "b225-shell-memory" \
  "#!/usr/bin/env bash\nkubectl rollout restart deployment/beagle-core\nbash run_dense_backend_promotion_smoke.sh" \
  "darwin-hpc" \
  "${SCRIPT_REPO_PATH}" \
  "shell"

ingest_memory_point \
  "b225-config-memory" \
  "apiVersion: v1\nkind: ConfigMap\ndata:\n  BEAGLE_MEMORY_DENSE_BACKEND_ID: voyage-4-large" \
  "darwin-hpc" \
  "${CONFIG_REPO_PATH}" \
  "yaml"

jq -n \
  --arg query_text "managed attach workspace_attach stable alias rust code retrieval" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg tag "${TAG}" \
  '{
    query_version: "beagle-code-retrieval-query-v1",
    query_text: $query_text,
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
      tags: [$tag]
    },
    rerank_hint: "code-pilot"
  }' > "${OUT}/code-retrieval-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H 'Content-Type: application/json' \
  -d @"${OUT}/code-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/code/query" \
  > "${OUT}/code-retrieval-result.json"

jq '.comparison' "${OUT}/code-retrieval-result.json" > "${OUT}/code-retrieval-comparison.json"

jq -n \
  --arg query_text "kubectl rollout restart bash smoke" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg source "${EXPECTED_SOURCE}" \
  --arg repo_path "${SCRIPT_REPO_PATH}" \
  --arg file_type "shell" \
  --arg tag "${TAG}" \
  '{
    query_version: "beagle-code-retrieval-query-v1",
    query_text: $query_text,
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.75,
    sparse_weight: 0.25,
    compare_against_general: false,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: $source,
      repo_path: $repo_path,
      file_type: $file_type,
      tags: [$tag]
    },
    rerank_hint: "code-pilot-filtered"
  }' > "${OUT}/filtered-code-retrieval-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H 'Content-Type: application/json' \
  -d @"${OUT}/filtered-code-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/code/query" \
  > "${OUT}/filtered-code-retrieval-result.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-restart.log" "${OUT}/beagle-core-rollout.log"
stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H 'Content-Type: application/json' \
  -d @"${OUT}/code-retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/code/query" \
  > "${OUT}/code-retrieval-result-after-restart.json"

jq -n \
  --arg phase "B22.5" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg general_dense_backend "$(jq -r '.general_dense_backend' "${OUT}/code-retrieval-result.json")" \
  --arg code_dense_backend "$(jq -r '.code_dense_backend' "${OUT}/code-retrieval-result.json")" \
  --arg sparse_backend "$(jq -r '.sparse_backend' "${OUT}/code-retrieval-result.json")" \
  --arg code_runtime_state "$(jq -r '.backend_profile.runtime_state' "${OUT}/code-retrieval-result.json")" \
  --arg retrieval_mode "$(jq -r '.retrieval_mode' "${OUT}/code-retrieval-result.json")" \
  --arg filtered_repo_path "${SCRIPT_REPO_PATH}" \
  --arg filtered_file_type "shell" \
  --argjson retrieval_hit_count "$(jq '.hits | length' "${OUT}/code-retrieval-result.json")" \
  --argjson filtered_hit_count "$(jq '.hits | length' "${OUT}/filtered-code-retrieval-result.json")" \
  --argjson dense_hit_count "$(jq '.dense_hit_count' "${OUT}/code-retrieval-result.json")" \
  --argjson sparse_hit_count "$(jq '.sparse_hit_count' "${OUT}/code-retrieval-result.json")" \
  --argjson comparison_present "$(jq 'if .comparison == null then false else true end' "${OUT}/code-retrieval-result.json")" \
  --argjson top_hit_changed "$(jq '.comparison.top_hit_changed // false' "${OUT}/code-retrieval-result.json")" \
  --argjson filtered_repo_match_count "$(jq --arg repo_path "${SCRIPT_REPO_PATH}" '[.hits[] | select(.point.payload.repo_path == $repo_path)] | length' "${OUT}/filtered-code-retrieval-result.json")" \
  --argjson filtered_file_type_match_count "$(jq --arg file_type 'shell' '[.hits[] | select(.point.payload.file_type == $file_type)] | length' "${OUT}/filtered-code-retrieval-result.json")" \
  --argjson restart_recovered_session "$(jq --arg expected_code "${EXPECTED_CODE_DENSE}" --arg expected_general "${EXPECTED_GENERAL_DENSE}" --arg expected_session "${EXPECTED_SESSION}" '(.code_dense_backend == $expected_code) and (.general_dense_backend == $expected_general) and ((.hits | length) >= 1) and all(.hits[]; .point.payload.session_id == $expected_session)' "${OUT}/code-retrieval-result-after-restart.json")" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    general_dense_backend: $general_dense_backend,
    code_dense_backend: $code_dense_backend,
    sparse_backend: $sparse_backend,
    code_runtime_state: $code_runtime_state,
    retrieval_mode: $retrieval_mode,
    retrieval_hit_count: $retrieval_hit_count,
    filtered_hit_count: $filtered_hit_count,
    dense_hit_count: $dense_hit_count,
    sparse_hit_count: $sparse_hit_count,
    comparison_present: $comparison_present,
    top_hit_changed: $top_hit_changed,
    filtered_repo_path: $filtered_repo_path,
    filtered_file_type: $filtered_file_type,
    filtered_repo_match_count: $filtered_repo_match_count,
    filtered_file_type_match_count: $filtered_file_type_match_count,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
