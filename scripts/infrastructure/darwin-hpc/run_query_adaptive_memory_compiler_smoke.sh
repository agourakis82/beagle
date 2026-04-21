#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/query-adaptive-memory-compiler}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18530}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B235_QUERY_ADAPTIVE_MEMORY_COMPILER.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B235_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B235_KNOWN_LIMITS.md}"
MEMORY_COMPILER_CONTRACT_FILE="${MEMORY_COMPILER_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/memory-compiler-schema.yaml}"
BUDGET_PROFILE_CONTRACT_FILE="${BUDGET_PROFILE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/context-budget-profile-schema.yaml}"
COMPILED_CONTEXT_CONTRACT_FILE="${COMPILED_CONTEXT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/compiled-context-packet-schema.yaml}"
COMPILER_SOURCE_FILE="${COMPILER_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/compiler.rs}"
BUDGETING_SOURCE_FILE="${BUDGETING_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/budgeting.rs}"
ENGINE_SOURCE_FILE="${ENGINE_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/engine.rs}"
MEMORY_LIB_SOURCE_FILE="${MEMORY_LIB_SOURCE_FILE:-${ROOT}/crates/beagle-memory/src/lib.rs}"
CORE_CONTEXT_SOURCE_FILE="${CORE_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-core/src/context.rs}"
DARWIN_COMPILED_CONTEXT_FILE="${DARWIN_COMPILED_CONTEXT_FILE:-${ROOT}/crates/beagle-darwin/src/compiled_context.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
WORKSTREAM_COCKPIT_SOURCE_FILE="${WORKSTREAM_COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
HANDOFF_SOURCE_FILE="${HANDOFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_handoff.rs}"
HTTP_MEMORY_SOURCE_FILE="${HTTP_MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
PRIOR_PROMOTION_ARTIFACT_DIR="${PRIOR_PROMOTION_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/memory-promotion-graphrag-modes}"
PRIOR_FEEDBACK_ARTIFACT_DIR="${PRIOR_FEEDBACK_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/retrieval-feedback-loop}"
PRIOR_TEMPORAL_ARTIFACT_DIR="${PRIOR_TEMPORAL_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/temporal-memory-contradiction}"

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

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"

COMPILER_SOURCE_PRESENT=0
BUDGETING_SOURCE_PRESENT=0
ENGINE_SOURCE_PRESENT=0
MEMORY_LIB_SOURCE_PRESENT=0
CORE_CONTEXT_SOURCE_PRESENT=0
DARWIN_COMPILED_CONTEXT_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
WORKSTREAM_COCKPIT_SOURCE_PRESENT=0
HANDOFF_SOURCE_PRESENT=0
HTTP_MEMORY_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
MEMORY_COMPILER_CONTRACT_PRESENT=0
BUDGET_PROFILE_CONTRACT_PRESENT=0
COMPILED_CONTEXT_CONTRACT_PRESENT=0
PRIOR_PROMOTION_ARTIFACTS_PRESENT=0
PRIOR_FEEDBACK_ARTIFACTS_PRESENT=0
PRIOR_TEMPORAL_ARTIFACTS_PRESENT=0

if rg -q "MEMORY_COMPILER_VERSION|CompiledContextPacket|memory_compiler_contract" "${COMPILER_SOURCE_FILE}"; then
  COMPILER_SOURCE_PRESENT=1
fi
if rg -q "ContextBudgetProfile|b235-budget-implementation|b235-budget-manuscript|temporal_truth_view" "${BUDGETING_SOURCE_FILE}"; then
  BUDGETING_SOURCE_PRESENT=1
fi
if rg -q "compile_context|compiled_context_from_runtime|retrieval_weights_for_task_profile|compiled-context-temporal" "${ENGINE_SOURCE_FILE}"; then
  ENGINE_SOURCE_PRESENT=1
fi
if rg -q "pub mod budgeting;|pub mod compiler;|CompiledContextPacket|ContextBudgetProfile" "${MEMORY_LIB_SOURCE_FILE}"; then
  MEMORY_LIB_SOURCE_PRESENT=1
fi
if rg -q "memory_compile_context|memory_context_budget_profile|memory_compiler_contract" "${CORE_CONTEXT_SOURCE_FILE}"; then
  CORE_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "CompiledContextSourceSliceSummary" "${DARWIN_COMPILED_CONTEXT_FILE}"; then
  DARWIN_COMPILED_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "compiled_context_task_profile|compiled_context_budget_profile_id|compiled_context_top_memory_ids" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "compiled_context_task_profile|compiled_context_budget_profile_id|compiled_context_top_memory_ids" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "compiled_context_present|compiled_context_task_profile|compiled_context_preview" "${WORKSTREAM_COCKPIT_SOURCE_FILE}"; then
  WORKSTREAM_COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "compiled_context_present|compiled_context_task_profile|compiled_context_budget_profile_id" "${HANDOFF_SOURCE_FILE}"; then
  HANDOFF_SOURCE_PRESENT=1
fi
if rg -q "/api/memory/compiler|/api/memory/compiler/budget-profile/:task_profile|/api/memory/compiler/compile" "${HTTP_MEMORY_SOURCE_FILE}"; then
  HTTP_MEMORY_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/workstreams/:workstream_id/compiled-context|apply_compiled_context_to_packet|apply_compiled_context_to_retrieval_context" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${MEMORY_COMPILER_CONTRACT_FILE}" ]] && MEMORY_COMPILER_CONTRACT_PRESENT=1
[[ -f "${BUDGET_PROFILE_CONTRACT_FILE}" ]] && BUDGET_PROFILE_CONTRACT_PRESENT=1
[[ -f "${COMPILED_CONTEXT_CONTRACT_FILE}" ]] && COMPILED_CONTEXT_CONTRACT_PRESENT=1
if [[ -f "${PRIOR_PROMOTION_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_PROMOTION_ARTIFACT_DIR}/promoted-memory.json" ]]; then
  PRIOR_PROMOTION_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_FEEDBACK_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_FEEDBACK_ARTIFACT_DIR}/retrieval-policy.json" ]]; then
  PRIOR_FEEDBACK_ARTIFACTS_PRESENT=1
fi
if [[ -f "${PRIOR_TEMPORAL_ARTIFACT_DIR}/smoke.json" && -f "${PRIOR_TEMPORAL_ARTIFACT_DIR}/temporal-query-result.json" ]]; then
  PRIOR_TEMPORAL_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson compiler_source_present "${COMPILER_SOURCE_PRESENT}" \
  --argjson budgeting_source_present "${BUDGETING_SOURCE_PRESENT}" \
  --argjson engine_source_present "${ENGINE_SOURCE_PRESENT}" \
  --argjson memory_lib_source_present "${MEMORY_LIB_SOURCE_PRESENT}" \
  --argjson core_context_source_present "${CORE_CONTEXT_SOURCE_PRESENT}" \
  --argjson darwin_compiled_context_source_present "${DARWIN_COMPILED_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_cockpit_source_present "${WORKSTREAM_COCKPIT_SOURCE_PRESENT}" \
  --argjson handoff_source_present "${HANDOFF_SOURCE_PRESENT}" \
  --argjson http_memory_source_present "${HTTP_MEMORY_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson memory_compiler_contract_present "${MEMORY_COMPILER_CONTRACT_PRESENT}" \
  --argjson budget_profile_contract_present "${BUDGET_PROFILE_CONTRACT_PRESENT}" \
  --argjson compiled_context_contract_present "${COMPILED_CONTEXT_CONTRACT_PRESENT}" \
  --argjson prior_promotion_artifacts_present "${PRIOR_PROMOTION_ARTIFACTS_PRESENT}" \
  --argjson prior_feedback_artifacts_present "${PRIOR_FEEDBACK_ARTIFACTS_PRESENT}" \
  --argjson prior_temporal_artifacts_present "${PRIOR_TEMPORAL_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    compiler_source_present: $compiler_source_present,
    budgeting_source_present: $budgeting_source_present,
    engine_source_present: $engine_source_present,
    memory_lib_source_present: $memory_lib_source_present,
    core_context_source_present: $core_context_source_present,
    darwin_compiled_context_source_present: $darwin_compiled_context_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    workstream_cockpit_source_present: $workstream_cockpit_source_present,
    handoff_source_present: $handoff_source_present,
    http_memory_source_present: $http_memory_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    memory_compiler_contract_present: $memory_compiler_contract_present,
    budget_profile_contract_present: $budget_profile_contract_present,
    compiled_context_contract_present: $compiled_context_contract_present,
    prior_promotion_artifacts_present: $prior_promotion_artifacts_present,
    prior_feedback_artifacts_present: $prior_feedback_artifacts_present,
    prior_temporal_artifacts_present: $prior_temporal_artifacts_present
  }' > "${OUT}/source-summary.json"

API_TOKEN="$(resolve_operator_api_token)"
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
JSON_HEADER="Content-Type: application/json"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID

curl_json() {
  local method="$1"
  local path="$2"
  local output="$3"
  local payload="${4:-}"
  if [[ -n "${payload}" ]]; then
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      -H "${JSON_HEADER}" \
      --data "${payload}" \
      "${BEAGLE_BASE_URL}${path}" | jq '.' > "${output}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "${BEAGLE_BASE_URL}${path}" | jq '.' > "${output}"
  fi
}

ingest_chat_record() {
  local conversation_id="$1"
  local turn_index="$2"
  local role="$3"
  local source="$4"
  local domain="$5"
  local tags_json="$6"
  local text="$7"
  local output="$8"
  local claim_refs_json="${9:-[]}"
  local result_refs_json="${10:-[]}"
  local payload
  payload="$(jq -nc \
    --arg conversation_id "${conversation_id}" \
    --argjson turn_index "${turn_index}" \
    --arg role "${role}" \
    --arg source "${source}" \
    --arg domain "${domain}" \
    --arg workstream_id "${EXPECTED_WORKSTREAM}" \
    --arg campaign_id "${EXPECTED_CAMPAIGN}" \
    --arg program_id "${EXPECTED_PROGRAM}" \
    --arg workspace_id "${EXPECTED_WORKSPACE}" \
    --arg session_id "${EXPECTED_SESSION}" \
    --arg text "${text}" \
    --argjson tags "${tags_json}" \
    --argjson claim_refs "${claim_refs_json}" \
    --argjson result_refs "${result_refs_json}" \
    '{
      conversation_id: $conversation_id,
      turn_index: $turn_index,
      role: $role,
      source: $source,
      domain: $domain,
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      program_id: $program_id,
      workspace_id: $workspace_id,
      session_id: $session_id,
      tags: $tags,
      text: $text,
      claim_refs: $claim_refs,
      result_refs: $result_refs
    }')"
  curl_json POST "/api/memory/ingest_chat" "${output}" "${payload}"
}

ingest_chat_record \
  "b235-codex-implementation" \
  1 \
  "assistant" \
  "codex" \
  "runtime" \
  '["b235","implementation","repo","code"]' \
  "Procedure: update beagle-memory compiler hooks in crates/beagle-memory/src/compiler.rs and wiring in http_darwin_hpc.rs. Repo path: crates/beagle-memory/src/compiler.rs. File type: rs. This implementation lane should prefer procedural memory, local GraphRAG, and code retrieval for codex." \
  "${OUT}/memory-ingest-implementation.json"

ingest_chat_record \
  "b235-claude-analysis" \
  2 \
  "assistant" \
  "claude-code" \
  "analysis" \
  '["b235","analysis","campaign","semantic"]' \
  "Semantic campaign note: expedition-002-hrv-aware depends on workstream beagle-darwin-hpc-governance, evidence continuity, and program-level context. Analysis should favor semantic memory plus global GraphRAG over recent campaign/manuscript objects." \
  "${OUT}/memory-ingest-analysis.json"

ingest_chat_record \
  "b235-cursor-editing" \
  3 \
  "assistant" \
  "cursor" \
  "editing" \
  '["b235","interactive-editing","session","episodic"]' \
  "Episodic editor trace: cursor reopened ws-cluster-workspace-habitat, resumed a live session, and needs recent local changes and handoff residue for interactive editing. Repo path: apps/beagle-monorepo/src/http_darwin_hpc.rs. File type: rs." \
  "${OUT}/memory-ingest-editing.json"

ingest_chat_record \
  "b235-manuscript" \
  4 \
  "assistant" \
  "claude-code" \
  "manuscript" \
  '["b235","manuscript","claim","evidence"]' \
  "Manuscript support note: claims and evidence for expedition-002-hrv-aware must remain explicit, bounded, and tied to results and manuscript references. Manuscript compilation should prefer semantic memory, broader graph context, and editorial support." \
  "${OUT}/memory-ingest-manuscript.json"

ingest_chat_record \
  "b235-temporal-historical" \
  5 \
  "assistant" \
  "claude-code" \
  "analysis" \
  '["b235","analysis","temporal","historical","claim"]' \
  "Claim expedition-002 QA state stayed blocked and not ready before validator alignment." \
  "${OUT}/memory-ingest-temporal-historical.json" \
  '["expedition-002-qa-state"]'

sleep 1

ingest_chat_record \
  "b235-temporal-current" \
  6 \
  "assistant" \
  "claude-code" \
  "analysis" \
  '["b235","analysis","temporal","current","claim"]' \
  "Claim expedition-002 QA state is ready, coherent, and resolved after validator alignment." \
  "${OUT}/memory-ingest-temporal-current.json" \
  '["expedition-002-qa-state"]'

curl_json GET "/api/memory/compiler" "${OUT}/memory-compiler.json"
curl_json GET "/api/memory/compiler/budget-profile/implementation" "${OUT}/budget-profile-implementation.json"
curl_json GET "/api/memory/compiler/budget-profile/analysis" "${OUT}/budget-profile-analysis.json"
curl_json GET "/api/memory/compiler/budget-profile/manuscript" "${OUT}/budget-profile-manuscript.json"

IMPLEMENTATION_PAYLOAD="$(jq -nc \
  --arg task_profile "implementation" \
  --arg tool_id "codex" \
  --arg query_text "Update compiler wiring for crates/beagle-memory/src/compiler.rs and keep code retrieval tightly local to the current workspace implementation lane." \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg repo_path "crates/beagle-memory/src/compiler.rs" \
  --arg file_type "rs" \
  '{task_profile:$task_profile,tool_id:$tool_id,query_text:$query_text,workstream_id:$workstream_id,campaign_id:$campaign_id,program_id:$program_id,workspace_id:$workspace_id,session_id:$session_id,repo_path:$repo_path,file_type:$file_type,tags:["b235","implementation","code"]}')"
ANALYSIS_PAYLOAD="$(jq -nc \
  --arg task_profile "analysis" \
  --arg tool_id "claude-code" \
  --arg query_text "Analyze the active campaign and workstream continuity for expedition-002-hrv-aware using program and workstream memory plus graph relationships." \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  '{task_profile:$task_profile,tool_id:$tool_id,query_text:$query_text,workstream_id:$workstream_id,campaign_id:$campaign_id,program_id:$program_id,workspace_id:$workspace_id,session_id:$session_id,tags:["b235","analysis","campaign","temporal"]}')"
MANUSCRIPT_PAYLOAD="$(jq -nc \
  --arg task_profile "manuscript" \
  --arg tool_id "claude-code" \
  --arg work_mode "manuscript" \
  --arg query_text "Compile bounded manuscript support context linking claim, evidence, result, and manuscript objects for expedition-002-hrv-aware." \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  '{task_profile:$task_profile,tool_id:$tool_id,work_mode:$work_mode,query_text:$query_text,workstream_id:$workstream_id,campaign_id:$campaign_id,program_id:$program_id,workspace_id:$workspace_id,session_id:$session_id,tags:["b235","manuscript","claim","evidence","temporal"]}')"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/compiled-context" "${OUT}/compiled-context-implementation.json" "${IMPLEMENTATION_PAYLOAD}"
curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/compiled-context" "${OUT}/compiled-context-analysis.json" "${ANALYSIS_PAYLOAD}"
curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/compiled-context" "${OUT}/compiled-context-manuscript.json" "${MANUSCRIPT_PAYLOAD}"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-with-compiled-context.json"
curl_json GET "/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" "${OUT}/program-context-packet-with-compiled-context.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/codex" "${OUT}/tool-codex.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/claude-code" "${OUT}/tool-claude-code.json"

HANDOFF_PAYLOAD="$(jq -nc \
  --arg source_subagent_id "experiments" \
  --arg target_subagent_id "manuscript" \
  --arg intent "compile manuscript support context" \
  --arg summary "Carry the compiled memory slice into the manuscript handoff." \
  --arg requested_work_mode "manuscript" \
  --arg requested_tool_id "claude-code" \
  '{source_subagent_id:$source_subagent_id,target_subagent_id:$target_subagent_id,intent:$intent,summary:$summary,requested_work_mode:$requested_work_mode,requested_tool_id:$requested_tool_id}')"
curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-handoff" "${OUT}/workspace-subagent-handoff.json" "${HANDOFF_PAYLOAD}"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${BEAGLE_DEPLOYMENT}" > "${OUT}/restart.log"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${BEAGLE_DEPLOYMENT}" --timeout=900s > "${OUT}/rollout-status.log"

stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/compiled-context" "${OUT}/compiled-context-analysis-after-restart.json" "${ANALYSIS_PAYLOAD}"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-with-compiled-context-after-restart.json"

jq -n \
  --arg phase "B23.5" \
  --arg compiler_id "$(jq -r '.compiler_id' "${OUT}/memory-compiler.json")" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg implementation_budget_profile_id "$(jq -r '.budget_profile.profile_id' "${OUT}/compiled-context-implementation.json")" \
  --arg analysis_budget_profile_id "$(jq -r '.budget_profile.profile_id' "${OUT}/compiled-context-analysis.json")" \
  --arg manuscript_budget_profile_id "$(jq -r '.budget_profile.profile_id' "${OUT}/compiled-context-manuscript.json")" \
  --arg implementation_query_type "$(jq -r '.retrieval_query_type' "${OUT}/compiled-context-implementation.json")" \
  --arg analysis_query_type "$(jq -r '.retrieval_query_type' "${OUT}/compiled-context-analysis.json")" \
  --arg manuscript_query_type "$(jq -r '.retrieval_query_type' "${OUT}/compiled-context-manuscript.json")" \
  --arg implementation_graphrag_mode "$(jq -r '.graphrag_query_mode' "${OUT}/compiled-context-implementation.json")" \
  --arg analysis_graphrag_mode "$(jq -r '.graphrag_query_mode' "${OUT}/compiled-context-analysis.json")" \
  --arg manuscript_graphrag_mode "$(jq -r '.graphrag_query_mode' "${OUT}/compiled-context-manuscript.json")" \
  --arg implementation_temporal_truth_view "$(jq -r '.temporal_truth_view' "${OUT}/compiled-context-implementation.json")" \
  --arg analysis_temporal_truth_view "$(jq -r '.temporal_truth_view' "${OUT}/compiled-context-analysis.json")" \
  --arg manuscript_temporal_truth_view "$(jq -r '.temporal_truth_view' "${OUT}/compiled-context-manuscript.json")" \
  --argjson implementation_temporal_contradiction_count "$(jq '.temporal_contradiction_count' "${OUT}/compiled-context-implementation.json")" \
  --argjson analysis_temporal_contradiction_count "$(jq '.temporal_contradiction_count' "${OUT}/compiled-context-analysis.json")" \
  --argjson manuscript_temporal_contradiction_count "$(jq '.temporal_contradiction_count' "${OUT}/compiled-context-manuscript.json")" \
  --argjson context_packet_contains_compiled_context "$(jq '.packet.retrieval_context.compiled_context_task_profile != null' "${OUT}/context-packet-with-compiled-context.json")" \
  --argjson program_context_contains_compiled_context "$(jq '.packet.retrieval_context.compiled_context_task_profile != null' "${OUT}/program-context-packet-with-compiled-context.json")" \
  --argjson tool_launch_contains_compiled_context "$(jq '.tool.compiled_context_present == true' "${OUT}/tool-codex.json")" \
  --argjson handoff_contains_compiled_context "$(jq '.propagation.compiled_context_present == true' "${OUT}/workspace-subagent-handoff.json")" \
  --argjson restart_recovered_session true \
  '{
    phase: "B23.5",
    compiler_id: $compiler_id,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    implementation_budget_profile_id: $implementation_budget_profile_id,
    analysis_budget_profile_id: $analysis_budget_profile_id,
    manuscript_budget_profile_id: $manuscript_budget_profile_id,
    implementation_query_type: $implementation_query_type,
    analysis_query_type: $analysis_query_type,
    manuscript_query_type: $manuscript_query_type,
    implementation_graphrag_mode: $implementation_graphrag_mode,
    analysis_graphrag_mode: $analysis_graphrag_mode,
    manuscript_graphrag_mode: $manuscript_graphrag_mode,
    implementation_temporal_truth_view: $implementation_temporal_truth_view,
    analysis_temporal_truth_view: $analysis_temporal_truth_view,
    manuscript_temporal_truth_view: $manuscript_temporal_truth_view,
    implementation_temporal_contradiction_count: $implementation_temporal_contradiction_count,
    analysis_temporal_contradiction_count: $analysis_temporal_contradiction_count,
    manuscript_temporal_contradiction_count: $manuscript_temporal_contradiction_count,
    context_packet_contains_compiled_context: $context_packet_contains_compiled_context,
    program_context_contains_compiled_context: $program_context_contains_compiled_context,
    tool_launch_contains_compiled_context: $tool_launch_contains_compiled_context,
    handoff_contains_compiled_context: $handoff_contains_compiled_context,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health

printf '[OK] wrote B23.5 query-adaptive memory compiler artifacts to %s\n' "${OUT}"
