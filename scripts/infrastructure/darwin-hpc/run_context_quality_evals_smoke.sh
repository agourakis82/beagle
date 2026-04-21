#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/context-quality-evals}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_REMOTE_PORT="${BEAGLE_REMOTE_PORT:-8080}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18630}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B236_CONTEXT_QUALITY_EVALS_AND_COMPILER_POLICY_LEARNING.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B236_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B236_KNOWN_LIMITS.md}"
EVAL_CASE_CONTRACT_FILE="${EVAL_CASE_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/context-eval-case-schema.yaml}"
EVAL_REPORT_CONTRACT_FILE="${EVAL_REPORT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/compiler-eval-report-schema.yaml}"
POLICY_CONTRACT_FILE="${POLICY_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/compiler-policy-schema.yaml}"
PRIOR_COMPILER_ARTIFACT_DIR="${PRIOR_COMPILER_ARTIFACT_DIR:-${ROOT}/.artifacts/darwin-hpc/query-adaptive-memory-compiler}"
PRIOR_COMPILER_SMOKE_SCRIPT="${PRIOR_COMPILER_SMOKE_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/run_query_adaptive_memory_compiler_smoke.sh}"

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

DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
EVAL_CASE_CONTRACT_PRESENT=0
EVAL_REPORT_CONTRACT_PRESENT=0
POLICY_CONTRACT_PRESENT=0
PRIOR_COMPILER_ARTIFACTS_PRESENT=0

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${EVAL_CASE_CONTRACT_FILE}" ]] && EVAL_CASE_CONTRACT_PRESENT=1
[[ -f "${EVAL_REPORT_CONTRACT_FILE}" ]] && EVAL_REPORT_CONTRACT_PRESENT=1
[[ -f "${POLICY_CONTRACT_FILE}" ]] && POLICY_CONTRACT_PRESENT=1

KUBECTL="${KUBECTL}" OUT="${PRIOR_COMPILER_ARTIFACT_DIR}" bash "${PRIOR_COMPILER_SMOKE_SCRIPT}"

if [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/memory-compiler.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-implementation.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-analysis.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-manuscript.json" ]] && \
   [[ -f "${PRIOR_COMPILER_ARTIFACT_DIR}/smoke.json" ]]; then
  PRIOR_COMPILER_ARTIFACTS_PRESENT=1
fi

jq -n \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson eval_case_contract_present "${EVAL_CASE_CONTRACT_PRESENT}" \
  --argjson eval_report_contract_present "${EVAL_REPORT_CONTRACT_PRESENT}" \
  --argjson policy_contract_present "${POLICY_CONTRACT_PRESENT}" \
  --argjson prior_compiler_artifacts_present "${PRIOR_COMPILER_ARTIFACTS_PRESENT}" \
  '{
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    eval_case_contract_present: $eval_case_contract_present,
    eval_report_contract_present: $eval_report_contract_present,
    policy_contract_present: $policy_contract_present,
    prior_compiler_artifacts_present: $prior_compiler_artifacts_present
  }' > "${OUT}/source-summary.json"

API_TOKEN="$(resolve_operator_api_token)"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
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

EVAL_CASES_PAYLOAD="$(jq -n \
  --arg report_version "beagle-compiler-eval-report-v1" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --argjson implementation_expected "$(jq '.top_memory_ids[:3]' "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-implementation.json")" \
  --argjson analysis_expected "$(jq '.top_memory_ids[:3]' "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-analysis.json")" \
  --argjson manuscript_expected "$(jq '.top_memory_ids[:3]' "${PRIOR_COMPILER_ARTIFACT_DIR}/compiled-context-manuscript.json")" \
  '{
    report_version: $report_version,
    top_k_stability_runs: 2,
    cases: [
      {
        case_id: "implementation-policy-case",
        task_profile: "implementation",
        description: "Implementation should stay code-routed, local, and current-truth aware.",
        request: {
          task_profile: "implementation",
          tool_id: "codex",
          query_text: "Update compiler wiring for crates/beagle-memory/src/compiler.rs and keep code retrieval tightly local to the current workspace implementation lane.",
          workstream_id: $workstream_id,
          campaign_id: $campaign_id,
          program_id: $program_id,
          workspace_id: $workspace_id,
          session_id: $session_id,
          repo_path: "crates/beagle-memory/src/compiler.rs",
          file_type: "rs",
          tags: ["b236", "implementation", "code", "compiler-eval"]
        },
        expected_memory_ids: $implementation_expected,
        preferred_truth_view: "current",
        preferred_graphrag_mode: "local",
        preferred_memory_tiers: ["procedural", "semantic", "episodic"],
        expected_retrieval_query_type: "code"
      },
      {
        case_id: "analysis-policy-case",
        task_profile: "analysis",
        description: "Analysis should preserve semantic breadth, both-truth temporal context, and global graph scope.",
        request: {
          task_profile: "analysis",
          tool_id: "claude-code",
          query_text: "Analyze the active campaign and workstream continuity for expedition-002-hrv-aware using program and workstream memory plus graph relationships.",
          workstream_id: $workstream_id,
          campaign_id: $campaign_id,
          program_id: $program_id,
          workspace_id: $workspace_id,
          session_id: $session_id,
          tags: ["b236", "analysis", "campaign", "temporal", "compiler-eval"]
        },
        expected_memory_ids: $analysis_expected,
        preferred_truth_view: "both",
        preferred_graphrag_mode: "global",
        preferred_memory_tiers: ["semantic", "episodic", "procedural"],
        expected_retrieval_query_type: "general"
      },
      {
        case_id: "manuscript-policy-case",
        task_profile: "manuscript",
        description: "Manuscript work should remain semantic-heavy, globally scoped, and explicit about contradictions.",
        request: {
          task_profile: "manuscript",
          tool_id: "claude-code",
          query_text: "Compile bounded manuscript support context linking claim, evidence, result, and manuscript objects for expedition-002-hrv-aware.",
          workstream_id: $workstream_id,
          campaign_id: $campaign_id,
          program_id: $program_id,
          workspace_id: $workspace_id,
          session_id: $session_id,
          tags: ["b236", "manuscript", "claim", "evidence", "temporal", "compiler-eval"]
        },
        expected_memory_ids: $manuscript_expected,
        preferred_truth_view: "both",
        preferred_graphrag_mode: "global",
        preferred_memory_tiers: ["semantic", "episodic", "procedural"],
        expected_retrieval_query_type: "general"
      }
    ]
  }')"

printf '%s\n' "${EVAL_CASES_PAYLOAD}" | jq '.' > "${OUT}/eval-cases.json"

curl_json POST "/api/memory/compiler/eval" "${OUT}/compiler-eval-report.json" "${EVAL_CASES_PAYLOAD}"
curl_json POST "/api/memory/compiler/policy" "${OUT}/compiler-policy.json" "$(cat "${OUT}/compiler-eval-report.json")"

jq '.comparisons[] | select(.task_profile=="implementation")' "${OUT}/compiler-eval-report.json" > "${OUT}/implementation-policy-comparison.json"
jq '.comparisons[] | select(.task_profile=="analysis")' "${OUT}/compiler-eval-report.json" > "${OUT}/analysis-policy-comparison.json"
jq '.comparisons[] | select(.task_profile=="manuscript")' "${OUT}/compiler-eval-report.json" > "${OUT}/manuscript-policy-comparison.json"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${BEAGLE_DEPLOYMENT}" > "${OUT}/restart.log"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${BEAGLE_DEPLOYMENT}" --timeout=900s > "${OUT}/rollout-status.log"

stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
BEAGLE_BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" "${BEAGLE_REMOTE_PORT}" "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID

curl_json_retry 6 10 POST "/api/memory/compiler/eval" "${OUT}/compiler-eval-report-after-restart.json" "${EVAL_CASES_PAYLOAD}"

jq -n \
  --arg phase "B23.6" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --arg compiler_id "$(jq -r '.compiler_id' "${OUT}/compiler-eval-report.json")" \
  --arg implementation_selected_budget_profile_id "$(jq -r '.selected_budget_profile_id' "${OUT}/implementation-policy-comparison.json")" \
  --arg analysis_selected_budget_profile_id "$(jq -r '.selected_budget_profile_id' "${OUT}/analysis-policy-comparison.json")" \
  --arg manuscript_selected_budget_profile_id "$(jq -r '.selected_budget_profile_id' "${OUT}/manuscript-policy-comparison.json")" \
  --argjson implementation_variant_count "$(jq '.variants | length' "${OUT}/implementation-policy-comparison.json")" \
  --argjson analysis_variant_count "$(jq '.variants | length' "${OUT}/analysis-policy-comparison.json")" \
  --argjson manuscript_variant_count "$(jq '.variants | length' "${OUT}/manuscript-policy-comparison.json")" \
  --argjson policy_profile_count "$(jq '.profiles | length' "${OUT}/compiler-policy.json")" \
  --argjson restart_recovered_session "$(jq '([.comparisons[].selected_budget_profile_id] == [input.comparisons[].selected_budget_profile_id])' "${OUT}/compiler-eval-report.json" "${OUT}/compiler-eval-report-after-restart.json")" \
  '{
    phase: $phase,
    compiler_id: $compiler_id,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    implementation_selected_budget_profile_id: $implementation_selected_budget_profile_id,
    analysis_selected_budget_profile_id: $analysis_selected_budget_profile_id,
    manuscript_selected_budget_profile_id: $manuscript_selected_budget_profile_id,
    implementation_variant_count: $implementation_variant_count,
    analysis_variant_count: $analysis_variant_count,
    manuscript_variant_count: $manuscript_variant_count,
    policy_profile_count: $policy_profile_count,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health

printf '[OK] wrote B23.6 context quality eval artifacts to %s\n' "${OUT}"
