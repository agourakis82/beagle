#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/intent-to-execution-planner}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18730}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B241_INTENT_TO_EXECUTION_PLANNER_EXPERIMENT_WORKBENCH.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B241_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B241_KNOWN_LIMITS.md}"
INTENT_CONTRACT_FILE="${INTENT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/intent-plan-schema.yaml}"
EXECUTION_CONTRACT_FILE="${EXECUTION_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/execution-plan-schema.yaml}"
ACCEPTANCE_CONTRACT_FILE="${ACCEPTANCE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/plan-acceptance-criteria-schema.yaml}"
INTENT_PLANNER_SOURCE_FILE="${INTENT_PLANNER_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/intent_planner.rs}"
EXECUTION_PLAN_SOURCE_FILE="${EXECUTION_PLAN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/execution_plan.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
WORKSTREAM_COCKPIT_SOURCE_FILE="${WORKSTREAM_COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
SUBAGENT_ROUTING_SOURCE_FILE="${SUBAGENT_ROUTING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_routing.rs}"
HTTP_DARWIN_SOURCE_FILE="${HTTP_DARWIN_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
PRIOR_COMPILER_ARTIFACT_DIR="${PRIOR_COMPILER_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/query-adaptive-memory-compiler}"
PRIOR_EVAL_ARTIFACT_DIR="${PRIOR_EVAL_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/context-quality-evals}"
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

curl_json_retry() {
  local attempts="$1"
  local sleep_seconds="$2"
  local method="$3"
  local path="$4"
  local output="$5"
  local payload="${6:-}"
  local attempt=1

  while (( attempt <= attempts )); do
    if curl_json "${method}" "${path}" "${output}" "${payload}"; then
      return 0
    fi
    rm -f "${output}"
    if (( attempt == attempts )); then
      echo "[FAIL] request ${method} ${path} failed after ${attempts} attempts" >&2
      return 1
    fi
    sleep "${sleep_seconds}"
    attempt=$((attempt + 1))
  done
}

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"

DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
INTENT_CONTRACT_PRESENT=0
EXECUTION_CONTRACT_PRESENT=0
ACCEPTANCE_CONTRACT_PRESENT=0
INTENT_PLANNER_SOURCE_PRESENT=0
EXECUTION_PLAN_SOURCE_PRESENT=0
WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
WORKSTREAM_COCKPIT_SOURCE_PRESENT=0
SUBAGENT_ROUTING_SOURCE_PRESENT=0
HTTP_DARWIN_SOURCE_PRESENT=0
PRIOR_COMPILER_ARTIFACTS_PRESENT=0
PRIOR_EVAL_ARTIFACTS_PRESENT=0
PRIOR_TEMPORAL_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${INTENT_CONTRACT_FILE}" ]] && INTENT_CONTRACT_PRESENT=1
[[ -f "${EXECUTION_CONTRACT_FILE}" ]] && EXECUTION_CONTRACT_PRESENT=1
[[ -f "${ACCEPTANCE_CONTRACT_FILE}" ]] && ACCEPTANCE_CONTRACT_PRESENT=1

if rg -q "planner_policy_for_workstream|build_intent_execution_plan|IntentPlannerResponse" "${INTENT_PLANNER_SOURCE_FILE}"; then
  INTENT_PLANNER_SOURCE_PRESENT=1
fi
if rg -q "IntentPlan|ExecutionPlan|PlannerPolicy|IntentPlannerAvailability" "${EXECUTION_PLAN_SOURCE_FILE}"; then
  EXECUTION_PLAN_SOURCE_PRESENT=1
fi
if rg -q "planner: Option<IntentPlannerAvailability>|compiled_context_budget_profile_id" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "planner: Option<IntentPlannerAvailability>|compiled_context_budget_profile_id" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "planner: Option<IntentPlannerAvailability>|compiled_context_present" "${WORKSTREAM_COCKPIT_SOURCE_FILE}"; then
  WORKSTREAM_COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "planner: Option<IntentPlannerAvailability>|WorkspaceSubAgentRoutePlane" "${SUBAGENT_ROUTING_SOURCE_FILE}"; then
  SUBAGENT_ROUTING_SOURCE_PRESENT=1
fi
if rg -q "/planner-policy|/intent-plan|apply_intent_planner_to_packet" "${HTTP_DARWIN_SOURCE_FILE}"; then
  HTTP_DARWIN_SOURCE_PRESENT=1
fi

if [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/memory-compiler.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-implementation.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-analysis.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-manuscript.json" ]]; then
  PRIOR_COMPILER_ARTIFACTS_PRESENT=1
fi

if [[ -f "${PRIOR_EVAL_ARTIFACT_DIR}/compiler-eval-report.json" ]] && \
   [[ -f "${PRIOR_EVAL_ARTIFACT_DIR}/compiler-policy.json" ]] && \
   [[ -f "${PRIOR_EVAL_ARTIFACT_DIR}/smoke.json" ]]; then
  PRIOR_EVAL_ARTIFACTS_PRESENT=1
fi

if [[ -f "${PRIOR_TEMPORAL_ARTIFACT_DIR}/temporal-query-result.json" ]] && \
   [[ -f "${PRIOR_TEMPORAL_ARTIFACT_DIR}/contradiction-report.json" ]] && \
   [[ -f "${PRIOR_TEMPORAL_ARTIFACT_DIR}/smoke.json" ]]; then
  PRIOR_TEMPORAL_ARTIFACTS_PRESENT=1
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson intent_contract_present "${INTENT_CONTRACT_PRESENT}" \
  --argjson execution_contract_present "${EXECUTION_CONTRACT_PRESENT}" \
  --argjson acceptance_contract_present "${ACCEPTANCE_CONTRACT_PRESENT}" \
  --argjson intent_planner_source_present "${INTENT_PLANNER_SOURCE_PRESENT}" \
  --argjson execution_plan_source_present "${EXECUTION_PLAN_SOURCE_PRESENT}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson workstream_cockpit_source_present "${WORKSTREAM_COCKPIT_SOURCE_PRESENT}" \
  --argjson subagent_routing_source_present "${SUBAGENT_ROUTING_SOURCE_PRESENT}" \
  --argjson http_darwin_source_present "${HTTP_DARWIN_SOURCE_PRESENT}" \
  --argjson prior_compiler_artifacts_present "${PRIOR_COMPILER_ARTIFACTS_PRESENT}" \
  --argjson prior_eval_artifacts_present "${PRIOR_EVAL_ARTIFACTS_PRESENT}" \
  --argjson prior_temporal_artifacts_present "${PRIOR_TEMPORAL_ARTIFACTS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    intent_contract_present: $intent_contract_present,
    execution_contract_present: $execution_contract_present,
    acceptance_contract_present: $acceptance_contract_present,
    intent_planner_source_present: $intent_planner_source_present,
    execution_plan_source_present: $execution_plan_source_present,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    workstream_cockpit_source_present: $workstream_cockpit_source_present,
    subagent_routing_source_present: $subagent_routing_source_present,
    http_darwin_source_present: $http_darwin_source_present,
    prior_compiler_artifacts_present: $prior_compiler_artifacts_present,
    prior_eval_artifacts_present: $prior_eval_artifacts_present,
    prior_temporal_artifacts_present: $prior_temporal_artifacts_present
  }' > "${OUT}/source-summary.json"

API_TOKEN="$(resolve_operator_api_token)"
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
JSON_HEADER="Content-Type: application/json"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/planner-policy" "${OUT}/planner-policy.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-with-planner.json"
curl_json GET "/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" "${OUT}/program-context-packet-with-planner.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/codex" "${OUT}/tool-codex.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-route?tool_id=claude-code&work_mode=manuscript" "${OUT}/workspace-subagent-route-manuscript.json"

IMPLEMENTATION_PAYLOAD="$(jq -n \
  --arg task_family "implementation" \
  --arg intent_text "Implement a bounded Darwin planner path that keeps code retrieval local to the repo-native workstream lane." \
  --arg query_text "crates/beagle-darwin/src/intent_planner.rs execution_plan.rs repo_native_dev_loop implementation" \
  --arg tool_id "codex" \
  --arg work_mode "implementation" \
  '{task_family: $task_family, intent_text: $intent_text, query_text: $query_text, tool_id: $tool_id, work_mode: $work_mode}')"

ANALYSIS_PAYLOAD="$(jq -n \
  --arg task_family "analysis" \
  --arg intent_text "Analyze the active campaign and produce a bounded experiment workbench plan that keeps result awareness explicit." \
  --arg query_text "expedition-002-hrv-aware experiment result workbench operator_cpu_loop analysis" \
  --arg tool_id "claude-code" \
  --arg work_mode "analysis" \
  '{task_family: $task_family, intent_text: $intent_text, query_text: $query_text, tool_id: $tool_id, work_mode: $work_mode}')"

MANUSCRIPT_PAYLOAD="$(jq -n \
  --arg task_family "manuscript" \
  --arg intent_text "Support manuscript work with a bounded plan that preserves claim and evidence linkage without hiding readiness limits." \
  --arg query_text "claim evidence manuscript readiness support semantic global" \
  --arg tool_id "claude-code" \
  --arg work_mode "manuscript" \
  '{task_family: $task_family, intent_text: $intent_text, query_text: $query_text, tool_id: $tool_id, work_mode: $work_mode}')"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/intent-plan" "${OUT}/intent-plan-response-implementation.json" "${IMPLEMENTATION_PAYLOAD}"
curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/intent-plan" "${OUT}/intent-plan-response-analysis.json" "${ANALYSIS_PAYLOAD}"
curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/intent-plan" "${OUT}/intent-plan-response-manuscript.json" "${MANUSCRIPT_PAYLOAD}"

jq '.intent' "${OUT}/intent-plan-response-implementation.json" > "${OUT}/intent-plan.json"
jq '.execution_plan' "${OUT}/intent-plan-response-implementation.json" > "${OUT}/execution-plan-implementation.json"
jq '.execution_plan' "${OUT}/intent-plan-response-analysis.json" > "${OUT}/execution-plan-analysis.json"
jq '.execution_plan' "${OUT}/intent-plan-response-manuscript.json" > "${OUT}/execution-plan-manuscript.json"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${BEAGLE_DEPLOYMENT}" > "${OUT}/restart.log"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${BEAGLE_DEPLOYMENT}" --timeout=900s > "${OUT}/rollout-status.log"

stop_port_forward BEAGLE_PF_PID
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID

curl_json_retry 5 3 GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-with-planner-after-restart.json"
curl_json_retry 5 3 POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/intent-plan" "${OUT}/intent-plan-response-analysis-after-restart.json" "${ANALYSIS_PAYLOAD}"
jq '.execution_plan' "${OUT}/intent-plan-response-analysis-after-restart.json" > "${OUT}/execution-plan-analysis-after-restart.json"

jq -n \
  --arg phase "B24.1" \
  --arg planner_policy_id "$(jq -r '.policy_id' "${OUT}/planner-policy.json")" \
  --arg implementation_subagent "$(jq -r '.selected_subagent_id' "${OUT}/execution-plan-implementation.json")" \
  --arg implementation_retrieval "$(jq -r '.retrieval_query_type' "${OUT}/execution-plan-implementation.json")" \
  --arg implementation_compiler "$(jq -r '.compiler_profile_id' "${OUT}/execution-plan-implementation.json")" \
  --arg implementation_graphrag "$(jq -r '.graphrag_query_mode' "${OUT}/execution-plan-implementation.json")" \
  --arg implementation_recipe_kind "$(jq -r '.recipe_target.recipe_kind // "none"' "${OUT}/execution-plan-implementation.json")" \
  --arg analysis_subagent "$(jq -r '.selected_subagent_id' "${OUT}/execution-plan-analysis.json")" \
  --arg analysis_retrieval "$(jq -r '.retrieval_query_type' "${OUT}/execution-plan-analysis.json")" \
  --arg analysis_compiler "$(jq -r '.compiler_profile_id' "${OUT}/execution-plan-analysis.json")" \
  --arg analysis_graphrag "$(jq -r '.graphrag_query_mode' "${OUT}/execution-plan-analysis.json")" \
  --arg analysis_recipe_kind "$(jq -r '.recipe_target.recipe_kind // "none"' "${OUT}/execution-plan-analysis.json")" \
  --arg manuscript_subagent "$(jq -r '.selected_subagent_id' "${OUT}/execution-plan-manuscript.json")" \
  --arg manuscript_retrieval "$(jq -r '.retrieval_query_type' "${OUT}/execution-plan-manuscript.json")" \
  --arg manuscript_compiler "$(jq -r '.compiler_profile_id' "${OUT}/execution-plan-manuscript.json")" \
  --arg manuscript_graphrag "$(jq -r '.graphrag_query_mode' "${OUT}/execution-plan-manuscript.json")" \
  --arg manuscript_recipe_kind "$(jq -r '.recipe_target.recipe_kind // "none"' "${OUT}/execution-plan-manuscript.json")" \
  --arg analysis_experiment_id "$(jq -r '.experiment_target.experiment_id // "none"' "${OUT}/execution-plan-analysis.json")" \
  --arg manuscript_experiment_id "$(jq -r '.experiment_target.experiment_id // "none"' "${OUT}/execution-plan-manuscript.json")" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --argjson planner_policy_profile_count "$(jq '.profiles | length' "${OUT}/planner-policy.json")" \
  --argjson same_beagle_owned_identity "$(jq -n \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg expected_workspace "${EXPECTED_WORKSPACE}" \
    --arg expected_session "${EXPECTED_SESSION}" \
    --slurpfile impl "${OUT}/execution-plan-implementation.json" \
    --slurpfile analysis "${OUT}/execution-plan-analysis.json" \
    --slurpfile manuscript "${OUT}/execution-plan-manuscript.json" \
    '$impl[0].workstream_id == $expected_workstream and
     $analysis[0].workstream_id == $expected_workstream and
     $manuscript[0].workstream_id == $expected_workstream and
     $impl[0].workspace_id == $expected_workspace and
     $analysis[0].workspace_id == $expected_workspace and
     $manuscript[0].workspace_id == $expected_workspace and
     $impl[0].session_id == $expected_session and
     $analysis[0].session_id == $expected_session and
     $manuscript[0].session_id == $expected_session')" \
  --argjson restart_recovered_session "$(jq -n \
    --slurpfile before "${OUT}/execution-plan-analysis.json" \
    --slurpfile after "${OUT}/execution-plan-analysis-after-restart.json" \
    '$before[0].workstream_id == $after[0].workstream_id and
     $before[0].workspace_id == $after[0].workspace_id and
     $before[0].session_id == $after[0].session_id and
     $before[0].selected_subagent_id == $after[0].selected_subagent_id and
     $before[0].retrieval_query_type == $after[0].retrieval_query_type and
     $before[0].compiler_profile_id == $after[0].compiler_profile_id and
     $before[0].graphrag_query_mode == $after[0].graphrag_query_mode and
     ($before[0].recipe_target.recipe_kind // "none") == ($after[0].recipe_target.recipe_kind // "none")')" \
  '{
    phase: $phase,
    planner_policy_id: $planner_policy_id,
    planner_policy_profile_count: $planner_policy_profile_count,
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    implementation_selected_subagent_id: $implementation_subagent,
    implementation_retrieval_query_type: $implementation_retrieval,
    implementation_compiler_profile_id: $implementation_compiler,
    implementation_graphrag_query_mode: $implementation_graphrag,
    implementation_recipe_kind: $implementation_recipe_kind,
    analysis_selected_subagent_id: $analysis_subagent,
    analysis_retrieval_query_type: $analysis_retrieval,
    analysis_compiler_profile_id: $analysis_compiler,
    analysis_graphrag_query_mode: $analysis_graphrag,
    analysis_recipe_kind: $analysis_recipe_kind,
    analysis_experiment_id: $analysis_experiment_id,
    manuscript_selected_subagent_id: $manuscript_subagent,
    manuscript_retrieval_query_type: $manuscript_retrieval,
    manuscript_compiler_profile_id: $manuscript_compiler,
    manuscript_graphrag_query_mode: $manuscript_graphrag,
    manuscript_recipe_kind: $manuscript_recipe_kind,
    manuscript_experiment_id: $manuscript_experiment_id,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health

