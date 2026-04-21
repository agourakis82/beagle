#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/temporal-memory-contradiction}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18540}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B234_TEMPORAL_MEMORY_AND_CONTRADICTION_RESOLUTION.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B234_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B234_KNOWN_LIMITS.md}"
TEMPORAL_SCHEMA_FILE="${TEMPORAL_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/temporal-memory-schema.yaml}"
CONTRADICTION_SCHEMA_FILE="${CONTRADICTION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-contradiction-schema.yaml}"
TEMPORAL_QUERY_SCHEMA_FILE="${TEMPORAL_QUERY_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/temporal-query-schema.yaml}"
TEMPORAL_SOURCE_FILE="${TEMPORAL_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/temporal.rs}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
CORE_CONTEXT_SOURCE_FILE="${CORE_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-core/src/context.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
PRIOR_GRAPHRAG_ARTIFACT_DIR="${PRIOR_GRAPHRAG_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/memory-hierarchy-graphrag}"
PRIOR_PROMOTION_ARTIFACT_DIR="${PRIOR_PROMOTION_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/memory-promotion-graphrag-modes}"
PRIOR_COMPILER_ARTIFACT_DIR="${PRIOR_COMPILER_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/query-adaptive-memory-compiler}"

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

curl_json() {
  local method="$1"
  local path="$2"
  local output="$3"
  local body="${4:-}"
  local url="http://127.0.0.1:${BEAGLE_LOCAL_PORT}${path}"
  if [[ -n "${body}" ]]; then
    curl -fsS \
      -H "Authorization: Bearer ${BEAGLE_TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Beagle-Consumer: beagle-operator" \
      -X "${method}" \
      --data @"${body}" \
      "${url}" > "${output}"
  else
    curl -fsS \
      -H "Authorization: Bearer ${BEAGLE_TOKEN}" \
      -H "X-Beagle-Consumer: beagle-operator" \
      -X "${method}" \
      "${url}" > "${output}"
  fi
}

ingest_chat_record() {
  local output_base="$1"
  local conversation_id="$2"
  local text="$3"
  local claim_ref="$4"

  jq -n \
    --arg source "claude-code" \
    --arg conversation_id "${conversation_id}" \
    --arg role "assistant" \
    --arg text "${text}" \
    --arg workstream_id "${EXPECTED_WORKSTREAM}" \
    --arg campaign_id "${EXPECTED_CAMPAIGN}" \
    --arg program_id "${EXPECTED_PROGRAM}" \
    --arg workspace_id "${EXPECTED_WORKSPACE}" \
    --arg session_id "${EXPECTED_SESSION}" \
    --arg claim_ref "${claim_ref}" \
    '{
      source: $source,
      conversation_id: $conversation_id,
      turn_index: 0,
      role: $role,
      text: $text,
      tags: [$workstream_id, "temporal", "claim"],
      domain: "darwin-hpc",
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      program_id: $program_id,
      workspace_id: $workspace_id,
      session_id: $session_id,
      claim_refs: [$claim_ref]
    }' > "${output_base}.json"

  curl_json POST "/api/memory/ingest_chat" "${output_base}-response.json" "${output_base}.json"
}

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
BEAGLE_TOKEN="$(resolve_operator_api_token)"

TEMPORAL_SOURCE_PRESENT=0
ENGINE_SOURCE_PRESENT=0
MEMORY_LIB_SOURCE_PRESENT=0
CORE_CONTEXT_SOURCE_PRESENT=0
HTTP_MEMORY_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
TEMPORAL_SCHEMA_PRESENT=0
CONTRADICTION_SCHEMA_PRESENT=0
TEMPORAL_QUERY_SCHEMA_PRESENT=0
PRIOR_GRAPHRAG_ARTIFACTS_PRESENT=0
PRIOR_PROMOTION_ARTIFACTS_PRESENT=0
PRIOR_COMPILER_ARTIFACTS_PRESENT=0

if rg -q "TEMPORAL_MEMORY_VERSION|TemporalQueryResult|detect_temporal_contradiction" "${TEMPORAL_SOURCE_FILE}"; then
  TEMPORAL_SOURCE_PRESENT=1
fi
if rg -q "temporal_query\\(|temporal_memory_schema\\(|temporal_query_from_runtime" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "pub mod temporal;|TemporalQuery|TemporalMemorySchema" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "memory_temporal_schema|memory_temporal_query" "${CORE_CONTEXT_SOURCE_FILE}"; then
  CORE_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/temporal|/api/memory/temporal/query|TemporalQueryRequest" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
if rg -q "temporal_query_for_workstream|temporal_truth_view|temporal_contradiction_count" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
if rg -q "temporal_truth_view|temporal_subject_refs|temporal_contradiction_ids" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "temporal_truth_view|temporal_subject_refs|temporal_contradiction_ids" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${TEMPORAL_SCHEMA_FILE}" ]] && TEMPORAL_SCHEMA_PRESENT=1
[[ -f "${CONTRADICTION_SCHEMA_FILE}" ]] && CONTRADICTION_SCHEMA_PRESENT=1
[[ -f "${TEMPORAL_QUERY_SCHEMA_FILE}" ]] && TEMPORAL_QUERY_SCHEMA_PRESENT=1
if [[ -f "${PRIOR_GRAPHRAG_ARTIFACT_DIR}/graphrag-result.json" && -f "${PRIOR_GRAPHRAG_ARTIFACT_DIR}/memory-hierarchy.json" ]]; then
  PRIOR_GRAPHRAG_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_PROMOTION_ARTIFACT_DIR}/promoted-memory.json" && -f "${PRIOR_PROMOTION_ARTIFACT_DIR}/graphrag-query-mode.json" ]]; then
  PRIOR_PROMOTION_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-analysis.json" && -f "${PRIOR_COMPILER_ARTIFACT_DIR}/memory-compiler.json" ]]; then
  PRIOR_COMPILER_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson temporal_source_present "${TEMPORAL_SOURCE_PRESENT}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson memory_lib_source_present "${MEMORY_LIB_SOURCE_PRESENT}" \
  --argjson core_context_source_present "${CORE_CONTEXT_SOURCE_PRESENT}" \
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson temporal_schema_present "${TEMPORAL_SCHEMA_PRESENT}" \
  --argjson contradiction_schema_present "${CONTRADICTION_SCHEMA_PRESENT}" \
  --argjson temporal_query_schema_present "${TEMPORAL_QUERY_SCHEMA_PRESENT}" \
  --argjson prior_graphrag_artifacts_present "${PRIOR_GRAPHRAG_ARTIFACTS_PRESENT}" \
  --argjson prior_promotion_artifacts_present "${PRIOR_PROMOTION_ARTIFACTS_PRESENT}" \
  --argjson prior_compiler_artifacts_present "${PRIOR_COMPILER_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    temporal_source_present: $temporal_source_present,
    engine_source_present: $engine_source_present,
    memory_lib_source_present: $memory_lib_source_present,
    core_context_source_present: $core_context_source_present,
    http_memory_source_present: $http_memory_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    temporal_schema_present: $temporal_schema_present,
    contradiction_schema_present: $contradiction_schema_present,
    temporal_query_schema_present: $temporal_query_schema_present,
    prior_graphrag_artifacts_present: $prior_graphrag_artifacts_present,
    prior_promotion_artifacts_present: $prior_promotion_artifacts_present,
    prior_compiler_artifacts_present: $prior_compiler_artifacts_present
  }' > "${OUT}/source-summary.json"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID

ingest_chat_record \
  "${OUT}/temporal-ingest-historical" \
  "b234-qa-historical" \
  "Claim expedition-002 QA state stayed blocked and not ready before validator alignment." \
  "claim:expedition-002-qa-state"

sleep 1

ingest_chat_record \
  "${OUT}/temporal-ingest-current" \
  "b234-qa-current" \
  "Claim expedition-002 QA state is now green and ready after validator alignment." \
  "claim:expedition-002-qa-state"

curl_json GET "/api/memory/temporal" "${OUT}/temporal-memory.json"

jq -n \
  --arg query "beagle-darwin-hpc-governance qa state across time" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg root_entity_type "workstream" \
  --arg root_entity_id "${EXPECTED_WORKSTREAM}" \
  '{
    query_text: $query,
    truth_view: "both",
    top_k: 4,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      tags: [$workstream_id, "temporal", "claim"]
    },
    root_entity_type: $root_entity_type,
    root_entity_id: $root_entity_id,
    subject_refs: ["claim:expedition-002-qa-state"],
    include_contradictions: true,
    query_type_hint: "general",
    rerank_hint: "b234-temporal-smoke"
  }' > "${OUT}/temporal-query.json"

curl_json POST "/api/memory/temporal/query" "${OUT}/temporal-query-result.json" "${OUT}/temporal-query.json"

jq '{
  contradiction_version: "beagle-memory-contradiction-v1",
  truth_view: .truth_view,
  contradiction_count: .contradiction_count,
  subject_refs: .subject_refs,
  contradictions: .contradictions
}' "${OUT}/temporal-query-result.json" > "${OUT}/contradiction-report.json"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-with-temporal-memory.json"
curl_json GET "/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" "${OUT}/program-context-packet-with-temporal-memory.json"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${BEAGLE_DEPLOYMENT}" > "${OUT}/restart.log"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${BEAGLE_DEPLOYMENT}" --timeout=900s > "${OUT}/rollout-status.log"

stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-with-temporal-memory-after-restart.json"

capture_cluster_health

jq -n \
  --arg phase "B23.4" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --slurpfile temporal "${OUT}/temporal-query-result.json" \
  --slurpfile context "${OUT}/context-packet-with-temporal-memory.json" \
  --slurpfile program "${OUT}/program-context-packet-with-temporal-memory.json" \
  --slurpfile restart_context "${OUT}/context-packet-with-temporal-memory-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    truth_view: $temporal[0].truth_view,
    current_truth_count: $temporal[0].current_truth_count,
    historical_truth_count: $temporal[0].historical_truth_count,
    contradiction_count: $temporal[0].contradiction_count,
    current_memory_id: ($temporal[0].top_current_memory_ids[0] // null),
    historical_memory_id: ($temporal[0].top_historical_memory_ids[0] // null),
    context_packet_contains_temporal_memory: ($context[0].packet.retrieval_context.temporal_truth_view != null),
    program_context_contains_temporal_memory: ($program[0].packet.retrieval_context.temporal_truth_view != null),
    restart_recovered_session: (
      ($restart_context[0].packet.session_id == $session_id) and
      ($restart_context[0].packet.retrieval_context.temporal_truth_view != null)
    )
  }' > "${OUT}/smoke.json"

printf '[OK] temporal memory contradiction smoke completed: %s\n' "${OUT}"
