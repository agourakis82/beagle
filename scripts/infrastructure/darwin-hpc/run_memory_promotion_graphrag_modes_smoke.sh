#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/memory-promotion-graphrag-modes}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18520}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_SOURCE="${EXPECTED_SOURCE:-codex}"
EXPECTED_ROLE="${EXPECTED_ROLE:-assistant}"
PROMOTION_POLICY_FILE="${PROMOTION_POLICY_FILE:-${ROOT}/crates/beagle-memory/src/promotion.rs}"
RETENTION_POLICY_FILE="${RETENTION_POLICY_FILE:-${ROOT}/crates/beagle-memory/src/retention.rs}"
GRAPHRAG_MODE_FILE="${GRAPHRAG_MODE_FILE:-${ROOT}/crates/beagle-memory/src/graphrag_modes.rs}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
CORE_CONTEXT_SOURCE_FILE="${CORE_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-core/src/context.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B232_MEMORY_PROMOTION_FORGETTING_AND_GRAPHRAG_QUERY_MODES.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B232_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B232_KNOWN_LIMITS.md}"
PROMOTION_CONTRACT_FILE="${PROMOTION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-promotion-policy-schema.yaml}"
RETENTION_CONTRACT_FILE="${RETENTION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-retention-policy-schema.yaml}"
GRAPHRAG_MODE_CONTRACT_FILE="${GRAPHRAG_MODE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/graphrag-query-mode-schema.yaml}"
PRIOR_GRAPHRAG_ARTIFACT_DIR="${PRIOR_GRAPHRAG_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/memory-hierarchy-graphrag}"
PRIOR_FEEDBACK_ARTIFACT_DIR="${PRIOR_FEEDBACK_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/retrieval-feedback-loop}"
TAG="${TAG:-b232-promote}"

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

PROMOTION_SOURCE_PRESENT=0
RETENTION_SOURCE_PRESENT=0
GRAPHRAG_MODE_SOURCE_PRESENT=0
ENGINE_SOURCE_PRESENT=0
MEMORY_LIB_SOURCE_PRESENT=0
CORE_CONTEXT_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
HTTP_MEMORY_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
PROMOTION_CONTRACT_PRESENT=0
RETENTION_CONTRACT_PRESENT=0
GRAPHRAG_MODE_CONTRACT_PRESENT=0
PRIOR_GRAPHRAG_ARTIFACTS_PRESENT=0
PRIOR_FEEDBACK_ARTIFACTS_PRESENT=0

if rg -q "memory_promotion_policy|derive_memory_promotion|promoted_target_memory_type" "${PROMOTION_POLICY_FILE}"; then
  PROMOTION_SOURCE_PRESENT=1
fi
if rg -q "memory_retention_policy|retain-until-superseded|expire-or-compact" "${RETENTION_POLICY_FILE}"; then
  RETENTION_SOURCE_PRESENT=1
fi
if rg -q "derive_graphrag_query_mode|apply_graphrag_query_mode|query_text_signals_drift" "${GRAPHRAG_MODE_FILE}"; then
  GRAPHRAG_MODE_SOURCE_PRESENT=1
fi
if rg -q "evaluate_memory_promotion|graph_rag_query_mode|derive_promoted_memories" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "MemoryPromotionPolicy|MemoryRetentionPolicy|GraphRagQueryModeDecision" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "memory_promotion_policy|memory_retention_policy|memory_graph_rag_query_mode|memory_evaluate_promotion" "${CORE_CONTEXT_SOURCE_FILE}"; then
  CORE_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "promotion_policy_id|retention_policy_id|graphrag_query_mode|promoted_memory_count" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "promotion_policy_id|retention_policy_id|graphrag_query_mode|promoted_memory_count" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/promotion-policy|/api/memory/retention-policy|/api/memory/graphrag/query-mode|/api/memory/promotion/evaluate" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
if rg -q "promotion_policy_id|graphrag_query_mode|promoted_memory_count" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${PROMOTION_CONTRACT_FILE}" ]] && PROMOTION_CONTRACT_PRESENT=1
[[ -f "${RETENTION_CONTRACT_FILE}" ]] && RETENTION_CONTRACT_PRESENT=1
[[ -f "${GRAPHRAG_MODE_CONTRACT_FILE}" ]] && GRAPHRAG_MODE_CONTRACT_PRESENT=1
if [[ -f "${PRIOR_GRAPHRAG_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_GRAPHRAG_ARTIFACT_DIR}/graphrag-result.json" ]]; then
  PRIOR_GRAPHRAG_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_FEEDBACK_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_FEEDBACK_ARTIFACT_DIR}/retrieval-policy.json" ]]; then
  PRIOR_FEEDBACK_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson promotion_source_present "${PROMOTION_SOURCE_PRESENT}" \
  --argjson retention_source_present "${RETENTION_SOURCE_PRESENT}" \
  --argjson graphrag_mode_source_present "${GRAPHRAG_MODE_SOURCE_PRESENT}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson memory_lib_source_present "${MEMORY_LIB_SOURCE_PRESENT}" \
  --argjson core_context_source_present "${CORE_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson promotion_contract_present "${PROMOTION_CONTRACT_PRESENT}" \
  --argjson retention_contract_present "${RETENTION_CONTRACT_PRESENT}" \
  --argjson graphrag_mode_contract_present "${GRAPHRAG_MODE_CONTRACT_PRESENT}" \
  --argjson prior_graphrag_artifacts_present "${PRIOR_GRAPHRAG_ARTIFACTS_PRESENT}" \
  --argjson prior_feedback_artifacts_present "${PRIOR_FEEDBACK_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    promotion_source_present: $promotion_source_present,
    retention_source_present: $retention_source_present,
    graphrag_mode_source_present: $graphrag_mode_source_present,
    engine_source_present: $engine_source_present,
    memory_lib_source_present: $memory_lib_source_present,
    core_context_source_present: $core_context_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    http_memory_source_present: $http_memory_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    promotion_contract_present: $promotion_contract_present,
    retention_contract_present: $retention_contract_present,
    graphrag_mode_contract_present: $graphrag_mode_contract_present,
    prior_graphrag_artifacts_present: $prior_graphrag_artifacts_present,
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

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${BASE_URL}/api/memory/promotion-policy" \
  > "${OUT}/promotion-policy.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${BASE_URL}/api/memory/retention-policy" \
  > "${OUT}/retention-policy.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/baseline-context-packet.json"

SEED_QUERY_TEXT="$(
  jq -r '.packet.retrieval_context.query_text // empty' "${OUT}/baseline-context-packet.json"
)"
if [[ -z "${SEED_QUERY_TEXT}" ]]; then
  SEED_QUERY_TEXT="${EXPECTED_WORKSTREAM} agourakis82/beagle feat/darwin-hpc-governance"
fi

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b232-episodic-procedural" \
  --arg role "${EXPECTED_ROLE}" \
  --arg seed_query_text "${SEED_QUERY_TEXT}" \
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
    text: ($seed_query_text + " procedural runbook attach launch resume workflow keeps the same workspace attached after restart and preserves the handoff context."),
    tags: [$workstream_id, $tag, "memory"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id
  }' > "${OUT}/episodic-procedural-ingest.json"
ingest_memory "${OUT}/episodic-procedural-ingest.json"

jq -n \
  --arg source "${EXPECTED_SOURCE}" \
  --arg conversation_id "b232-episodic-semantic" \
  --arg role "${EXPECTED_ROLE}" \
  --arg seed_query_text "${SEED_QUERY_TEXT}" \
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
    text: ($seed_query_text + " result supports the campaign claim and manuscript review context after the latest bounded restart."),
    tags: [$workstream_id, $tag, "memory"],
    domain: $domain,
    provider: "codex",
    model: "gpt-5.4",
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id
  }' > "${OUT}/episodic-semantic-ingest.json"
ingest_memory "${OUT}/episodic-semantic-ingest.json"

PROCEDURAL_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/episodic-procedural-ingest-response.json")"
SEMANTIC_MEMORY_ID="$(jq -r '.memory_id // empty' "${OUT}/episodic-semantic-ingest-response.json")"

jq -n \
  --arg memory_id "${PROCEDURAL_MEMORY_ID}" \
  '{memory_id: $memory_id}' > "${OUT}/promotion-evaluate-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/promotion-evaluate-request.json" \
  "${BASE_URL}/api/memory/promotion/evaluate" \
  > "${OUT}/promoted-memory.json"

jq -n \
  --arg query_text "Compare drift across sessions for ${EXPECTED_WORKSTREAM} workflow changes and promotion behavior." \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg tag "${TAG}" \
  '{
    query_version: "beagle-graphrag-query-v1",
    query_text: $query_text,
    top_k: 4,
    max_hops: 2,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      tags: [$tag]
    },
    root_entity_type: "workstream",
    root_entity_id: $workstream_id,
    program_id: $program_id,
    include_memory_hierarchy: true,
    query_type_hint: "general"
  }' > "${OUT}/graphrag-query-mode-request.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/graphrag-query-mode-request.json" \
  "${BASE_URL}/api/memory/graphrag/query-mode" \
  > "${OUT}/graphrag-query-mode.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-promoted-memory.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${PROGRAM_URL}/context-packet" \
  > "${OUT}/program-context-packet-with-promoted-memory.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/promotion-evaluate-request.json" \
  "${BASE_URL}/api/memory/promotion/evaluate" \
  > "${OUT}/promoted-memory-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/context-packet-with-promoted-memory-after-restart.json"

jq -n \
  --arg phase "B23.2" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg procedural_memory_id "${PROCEDURAL_MEMORY_ID}" \
  --arg semantic_memory_id "${SEMANTIC_MEMORY_ID}" \
  --slurpfile promotion_policy "${OUT}/promotion-policy.json" \
  --slurpfile retention_policy "${OUT}/retention-policy.json" \
  --slurpfile promoted "${OUT}/promoted-memory.json" \
  --slurpfile mode "${OUT}/graphrag-query-mode.json" \
  --slurpfile workstream_packet "${OUT}/context-packet-with-promoted-memory.json" \
  --slurpfile program_packet "${OUT}/program-context-packet-with-promoted-memory.json" \
  --slurpfile promoted_restart "${OUT}/promoted-memory-after-restart.json" \
  --slurpfile restart_packet "${OUT}/context-packet-with-promoted-memory-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    promotion_policy_id: $promotion_policy[0].policy_id,
    retention_policy_id: $retention_policy[0].policy_id,
    promoted_source_memory_id: $promoted[0].source_memory_id,
    promoted_source_memory_type: $promoted[0].source_memory_type,
    promoted_target_memory_type: $promoted[0].target_memory_type,
    promoted_retention_action: $promoted[0].retention_action,
    drift_query_mode: $mode[0].query_mode,
    drift_query_mode_source: $mode[0].classifier_source,
    context_packet_contains_policy: (
      $workstream_packet[0].packet.retrieval_context.promotion_policy_id == $promotion_policy[0].policy_id and
      $workstream_packet[0].packet.retrieval_context.retention_policy_id == $retention_policy[0].policy_id
    ),
    context_packet_contains_mode: (
      (($workstream_packet[0].packet.retrieval_context.graphrag_query_mode // "") | length) > 0 and
      (($workstream_packet[0].packet.retrieval_context.graphrag_query_mode_reason // "") | length) > 0
    ),
    context_packet_contains_promotion: (
      ($workstream_packet[0].packet.retrieval_context.promoted_memory_count // 0) >= 1 and
      (($workstream_packet[0].packet.retrieval_context.promoted_target_memory_types // []) | length) >= 1
    ),
    program_context_contains_policy: (
      $program_packet[0].packet.retrieval_context.promotion_policy_id == $promotion_policy[0].policy_id and
      $program_packet[0].packet.retrieval_context.retention_policy_id == $retention_policy[0].policy_id
    ),
    promoted_memory_in_scope: (
      $promoted[0].source_memory_id == $procedural_memory_id and
      ($promoted[0].source_memory_type == "episodic") and
      (($promoted[0].target_memory_type == "procedural") or ($promoted[0].target_memory_type == "semantic"))
    ),
    restart_recovered_session: (
      $promoted_restart[0].source_memory_id == $procedural_memory_id and
      $promoted_restart[0].target_memory_type == $promoted[0].target_memory_type and
      ($restart_packet[0].packet.session_id == $session_id) and
      (($restart_packet[0].packet.retrieval_context.graphrag_query_mode // "") | length) > 0
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health
