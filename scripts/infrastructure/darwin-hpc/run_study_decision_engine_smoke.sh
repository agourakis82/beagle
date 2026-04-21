#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/study-decision-engine}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18532}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"

B261_BASE_OUT="${B261_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/study-registry-sweep}"

STUDY_DECISION_SOURCE_FILE="${STUDY_DECISION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_decision.rs}"
NEXT_RUN_PROPOSAL_SOURCE_FILE="${NEXT_RUN_PROPOSAL_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/next_run_proposal.rs}"
STUDY_REGISTRY_SOURCE_FILE="${STUDY_REGISTRY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_registry.rs}"
STUDY_DAG_SOURCE_FILE="${STUDY_DAG_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_dag.rs}"
STUDY_SWEEP_SOURCE_FILE="${STUDY_SWEEP_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_sweep.rs}"
WORKBENCH_RUN_SOURCE_FILE="${WORKBENCH_RUN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_run.rs}"
WORKBENCH_RESULT_BINDING_SOURCE_FILE="${WORKBENCH_RESULT_BINDING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_result_binding.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B262_STUDY_DECISION_ENGINE_ADAPTIVE_SWEEP_POLICY.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B262_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B262_KNOWN_LIMITS.md}"
STUDY_DECISION_SCHEMA_FILE="${STUDY_DECISION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-decision-schema.yaml}"
NEXT_RUN_PROPOSAL_SCHEMA_FILE="${NEXT_RUN_PROPOSAL_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/next-run-proposal-schema.yaml}"
STUDY_DECISION_BASIS_SCHEMA_FILE="${STUDY_DECISION_BASIS_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-decision-basis-schema.yaml}"

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
  local port="$1"
  local log_file="$2"
  : > "${log_file}"
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${port}:8080" >"${log_file}" 2>&1 &
  PF_PID=$!
  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${log_file}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${log_file}" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${log_file}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

wait_for_health() {
  local port="$1"
  local target="$2"
  local ready=0
  for _ in $(seq 1 30); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != "1" ]]; then
    echo "[FAIL] Beagle health endpoint did not become ready on port ${port}" >&2
    exit 1
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

fetch_json() {
  local port="$1"
  local path="$2"
  local output="$3"
  curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${port}${path}" \
    > "${output}"
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"

STUDY_DECISION_SOURCE_PRESENT=0
NEXT_RUN_PROPOSAL_SOURCE_PRESENT=0
STUDY_REGISTRY_SOURCE_PRESENT=0
STUDY_DAG_SOURCE_PRESENT=0
STUDY_SWEEP_SOURCE_PRESENT=0
WORKBENCH_RUN_SOURCE_PRESENT=0
WORKBENCH_RESULT_BINDING_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
STUDY_DECISION_SCHEMA_PRESENT=0
NEXT_RUN_PROPOSAL_SCHEMA_PRESENT=0
STUDY_DECISION_BASIS_SCHEMA_PRESENT=0
B261_BASE_PRESENT=0

if rg -q "ensure_study_decision_engine|StudyDecisionEngineBundle|study-decision-basis" "${STUDY_DECISION_SOURCE_FILE}"; then
  STUDY_DECISION_SOURCE_PRESENT=1
fi
if rg -q "pub struct NextRunProposal|build_next_run_proposal|next-run-proposal" "${NEXT_RUN_PROPOSAL_SOURCE_FILE}"; then
  NEXT_RUN_PROPOSAL_SOURCE_PRESENT=1
fi
if rg -q "ensure_study_registry_sweep|StudyRegistrySweepBundle|comparative-result-summary" "${STUDY_REGISTRY_SOURCE_FILE}"; then
  STUDY_REGISTRY_SOURCE_PRESENT=1
fi
if rg -q "pub struct StudyDag|study-dag|derived-from-run" "${STUDY_DAG_SOURCE_FILE}"; then
  STUDY_DAG_SOURCE_PRESENT=1
fi
if rg -q "pub struct StudySweep|pub struct StudySweepVariant|study-sweep" "${STUDY_SWEEP_SOURCE_FILE}"; then
  STUDY_SWEEP_SOURCE_PRESENT=1
fi
if rg -q "WorkbenchRunOrchestrationBundle|orchestrate_workbench_run" "${WORKBENCH_RUN_SOURCE_FILE}"; then
  WORKBENCH_RUN_SOURCE_PRESENT=1
fi
if rg -q "WorkbenchResultBinding|read_workbench_result_binding|deterministic" "${WORKBENCH_RESULT_BINDING_SOURCE_FILE}"; then
  WORKBENCH_RESULT_BINDING_SOURCE_PRESENT=1
fi
if rg -q "pub mod study_decision|pub mod next_run_proposal|ensure_study_decision_engine" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/study-decision|/next-run-proposal|workstream_study_decision_handler" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${STUDY_DECISION_SCHEMA_FILE}" ]] && STUDY_DECISION_SCHEMA_PRESENT=1
[[ -f "${NEXT_RUN_PROPOSAL_SCHEMA_FILE}" ]] && NEXT_RUN_PROPOSAL_SCHEMA_PRESENT=1
[[ -f "${STUDY_DECISION_BASIS_SCHEMA_FILE}" ]] && STUDY_DECISION_BASIS_SCHEMA_PRESENT=1

if [[ -f "${B261_BASE_OUT}/smoke.json" ]] && jq -e '.phase == "B26.1" and .status == "ok" and .same_beagle_owned_identity == true' "${B261_BASE_OUT}/smoke.json" >/dev/null; then
  B261_BASE_PRESENT=1
fi

B261_STUDY_ID=""
B261_WORKSPACE_ID=""
B261_SESSION_ID=""
if [[ -f "${B261_BASE_OUT}/study-registry.json" ]]; then
  B261_STUDY_ID="$(jq -r '.study_id' "${B261_BASE_OUT}/study-registry.json")"
  B261_WORKSPACE_ID="$(jq -r '.workspace_id' "${B261_BASE_OUT}/study-registry.json")"
  B261_SESSION_ID="$(jq -r '.session_id' "${B261_BASE_OUT}/study-registry.json")"
fi

jq -nc \
  --argjson study_decision_source_present "${STUDY_DECISION_SOURCE_PRESENT}" \
  --argjson next_run_proposal_source_present "${NEXT_RUN_PROPOSAL_SOURCE_PRESENT}" \
  --argjson study_registry_source_present "${STUDY_REGISTRY_SOURCE_PRESENT}" \
  --argjson study_dag_source_present "${STUDY_DAG_SOURCE_PRESENT}" \
  --argjson study_sweep_source_present "${STUDY_SWEEP_SOURCE_PRESENT}" \
  --argjson workbench_run_source_present "${WORKBENCH_RUN_SOURCE_PRESENT}" \
  --argjson workbench_result_binding_source_present "${WORKBENCH_RESULT_BINDING_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson study_decision_schema_present "${STUDY_DECISION_SCHEMA_PRESENT}" \
  --argjson next_run_proposal_schema_present "${NEXT_RUN_PROPOSAL_SCHEMA_PRESENT}" \
  --argjson study_decision_basis_schema_present "${STUDY_DECISION_BASIS_SCHEMA_PRESENT}" \
  --argjson b261_base_present "${B261_BASE_PRESENT}" \
  --arg b261_study_id "${B261_STUDY_ID}" \
  --arg b261_workspace_id "${B261_WORKSPACE_ID}" \
  --arg b261_session_id "${B261_SESSION_ID}" \
  '{
    study_decision_source_present: $study_decision_source_present,
    next_run_proposal_source_present: $next_run_proposal_source_present,
    study_registry_source_present: $study_registry_source_present,
    study_dag_source_present: $study_dag_source_present,
    study_sweep_source_present: $study_sweep_source_present,
    workbench_run_source_present: $workbench_run_source_present,
    workbench_result_binding_source_present: $workbench_result_binding_source_present,
    lib_source_present: $lib_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    study_decision_schema_present: $study_decision_schema_present,
    next_run_proposal_schema_present: $next_run_proposal_schema_present,
    study_decision_basis_schema_present: $study_decision_basis_schema_present,
    b261_base_present: $b261_base_present,
    b261_study_id: $b261_study_id,
    b261_workspace_id: $b261_workspace_id,
    b261_session_id: $b261_session_id
  }' > "${OUT}/source-summary.json"

PORT="$(choose_local_port "${LOCAL_PORT}")"
PF_LOG="${OUT}/port-forward.log"
start_port_forward "${PORT}" "${PF_LOG}"
AUTH_HEADER="Authorization: Bearer $(resolve_operator_api_token)"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

wait_for_health "${PORT}" "${OUT}/health-before.json"

fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-registry" "${OUT}/study-registry.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-dag" "${OUT}/study-dag.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-sweep" "${OUT}/study-sweep.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/comparative-result-summary" "${OUT}/comparative-result-summary.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-decision" "${OUT}/study-decision.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-decision-basis" "${OUT}/study-decision-basis.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/next-run-proposal" "${OUT}/next-run-proposal.json"

jq -e '
  .phase == "B26.2" and
  .contract_kind == "study-decision" and
  .contract_version == "beagle-study-decision-v1" and
  (.recommended_action | IN("continue-sweep","stop-study","promote-variant","archive-variant","rerun-variant")) and
  (.recommended_next_variant_id | length) > 0 and
  (.recommended_next_compute_profile_id | length) > 0 and
  .same_beagle_owned_identity == true
' "${OUT}/study-decision.json" >/dev/null

jq -e '
  .phase == "B26.2" and
  .contract_kind == "study-decision-basis" and
  .contract_version == "beagle-study-decision-basis-v1" and
  .same_beagle_owned_identity == true and
  (.evidence_refs | length) >= 4 and
  (.best_run_id | length) > 0 and
  (.best_variant_id | length) > 0
' "${OUT}/study-decision-basis.json" >/dev/null

jq -e '
  .phase == "B26.2" and
  .contract_kind == "next-run-proposal" and
  .contract_version == "beagle-next-run-proposal-v1" and
  .same_beagle_owned_identity == true and
  (.proposed_run_label | length) > 0 and
  (.proposed_variant_id | length) > 0 and
  (.proposed_compute_profile_id | length) > 0 and
  .operator_review_required == true
' "${OUT}/next-run-proposal.json" >/dev/null

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s

fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-registry" "${OUT}/study-registry-after-restart.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-sweep" "${OUT}/study-sweep-after-restart.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/comparative-result-summary" "${OUT}/comparative-result-summary-after-restart.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-decision" "${OUT}/study-decision-after-restart.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/study-decision-basis" "${OUT}/study-decision-basis-after-restart.json"
fetch_json "${PORT}" "/api/darwin/workstreams/${WORKSTREAM_ID}/next-run-proposal" "${OUT}/next-run-proposal-after-restart.json"

wait_for_health "${PORT}" "${OUT}/health-after.json"

RESTART_RECOVERED_SESSION=0
if jq -e \
  --arg study_id "$(jq -r '.study_id' "${OUT}/study-registry.json")" \
  --arg workspace_id "$(jq -r '.workspace_id' "${OUT}/study-registry.json")" \
  --arg session_id "$(jq -r '.session_id' "${OUT}/study-registry.json")" \
  --argjson same_beagle_owned_identity "$(jq -r '.same_beagle_owned_identity' "${OUT}/study-registry.json")" \
  '
    .study_id == $study_id and
    .workspace_id == $workspace_id and
    .session_id == $session_id and
    .same_beagle_owned_identity == $same_beagle_owned_identity
  ' "${OUT}/study-registry-after-restart.json" >/dev/null; then
  RESTART_RECOVERED_SESSION=1
fi

jq -nc \
  --arg study_id "$(jq -r '.study_id' "${OUT}/study-registry.json")" \
  --arg workstream_id "$(jq -r '.workstream_id' "${OUT}/study-registry.json")" \
  --arg workspace_id "$(jq -r '.workspace_id' "${OUT}/study-registry.json")" \
  --arg session_id "$(jq -r '.session_id' "${OUT}/study-registry.json")" \
  --arg recommended_action "$(jq -r '.recommended_action' "${OUT}/study-decision.json")" \
  --arg recommended_next_variant_id "$(jq -r '.recommended_next_variant_id' "${OUT}/study-decision.json")" \
  --arg recommended_next_compute_profile_id "$(jq -r '.recommended_next_compute_profile_id' "${OUT}/study-decision.json")" \
  --arg proposal_id "$(jq -r '.proposal_id' "${OUT}/next-run-proposal.json")" \
  --arg study_decision_id "$(jq -r '.decision_id' "${OUT}/study-decision.json")" \
  --arg study_decision_basis_id "$(jq -r '.basis_id' "${OUT}/study-decision-basis.json")" \
  --argjson same_beagle_owned_identity "$(jq -r '.same_beagle_owned_identity' "${OUT}/study-decision.json")" \
  --argjson restart_recovered_session "${RESTART_RECOVERED_SESSION}" \
  '{
    status: "ok",
    phase: "B26.2",
    study_id: $study_id,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    same_beagle_owned_identity: $same_beagle_owned_identity,
    study_decision_id: $study_decision_id,
    study_decision_basis_id: $study_decision_basis_id,
    next_run_proposal_id: $proposal_id,
    recommended_action: $recommended_action,
    recommended_next_variant_id: $recommended_next_variant_id,
    recommended_next_compute_profile_id: $recommended_next_compute_profile_id,
    study_decision_generated: true,
    next_run_proposal_generated: true,
    decision_basis_generated: true,
    comparative_summary_generated: true,
    restart_recovered_session: ($restart_recovered_session == 1)
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] study decision engine smoke artifacts captured"
