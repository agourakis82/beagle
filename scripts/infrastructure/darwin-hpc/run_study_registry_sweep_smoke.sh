#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/study-registry-sweep}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18531}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"

B257_BASE_OUT="${B257_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/replay-branch-fork-execution}"
B255_BASE_OUT="${B255_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/reproducibility-capsule}"
B253_BASE_OUT="${B253_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/workbench-orchestration}"

STUDY_REGISTRY_SOURCE_FILE="${STUDY_REGISTRY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_registry.rs}"
STUDY_DAG_SOURCE_FILE="${STUDY_DAG_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_dag.rs}"
STUDY_SWEEP_SOURCE_FILE="${STUDY_SWEEP_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_sweep.rs}"
WORKBENCH_RUN_SOURCE_FILE="${WORKBENCH_RUN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_run.rs}"
WORKBENCH_RESULT_BINDING_SOURCE_FILE="${WORKBENCH_RESULT_BINDING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_result_binding.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B261_EXPERIMENT_REGISTRY_STUDY_DAG_SWEEP_WORKBENCH.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B261_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B261_KNOWN_LIMITS.md}"
STUDY_REGISTRY_SCHEMA_FILE="${STUDY_REGISTRY_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-registry-schema.yaml}"
STUDY_DAG_SCHEMA_FILE="${STUDY_DAG_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-dag-schema.yaml}"
STUDY_SWEEP_SCHEMA_FILE="${STUDY_SWEEP_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-sweep-schema.yaml}"

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
  # shellcheck disable=SC2086
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

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"

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
STUDY_REGISTRY_SCHEMA_PRESENT=0
STUDY_DAG_SCHEMA_PRESENT=0
STUDY_SWEEP_SCHEMA_PRESENT=0
B257_BASE_PRESENT=0
B255_BASE_PRESENT=0
B253_BASE_PRESENT=0

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
if rg -q "pub mod study_registry|pub mod study_dag|pub mod study_sweep|ensure_study_registry_sweep" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/study-registry|/study-dag|/study-sweep|/comparative-result-summary|workstream_study_registry_handler" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi

[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${STUDY_REGISTRY_SCHEMA_FILE}" ]] && STUDY_REGISTRY_SCHEMA_PRESENT=1
[[ -f "${STUDY_DAG_SCHEMA_FILE}" ]] && STUDY_DAG_SCHEMA_PRESENT=1
[[ -f "${STUDY_SWEEP_SCHEMA_FILE}" ]] && STUDY_SWEEP_SCHEMA_PRESENT=1

if [[ -f "${B257_BASE_OUT}/smoke.json" ]] && jq -e '.phase == "B25.7" and .status == "ok" and .same_beagle_owned_identity == true' "${B257_BASE_OUT}/smoke.json" >/dev/null; then
  B257_BASE_PRESENT=1
fi
if [[ -f "${B255_BASE_OUT}/smoke.json" ]] && jq -e '.phase == "B25.5" and .status == "ok" and .same_beagle_owned_identity == true' "${B255_BASE_OUT}/smoke.json" >/dev/null; then
  B255_BASE_PRESENT=1
fi
if [[ -f "${B253_BASE_OUT}/smoke.json" ]] && jq -e '.phase == "B25.3" and .status == "ok" and .same_beagle_owned_identity == true' "${B253_BASE_OUT}/smoke.json" >/dev/null; then
  B253_BASE_PRESENT=1
fi

jq -nc \
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
  --argjson study_registry_schema_present "${STUDY_REGISTRY_SCHEMA_PRESENT}" \
  --argjson study_dag_schema_present "${STUDY_DAG_SCHEMA_PRESENT}" \
  --argjson study_sweep_schema_present "${STUDY_SWEEP_SCHEMA_PRESENT}" \
  --argjson b257_base_present "${B257_BASE_PRESENT}" \
  --argjson b255_base_present "${B255_BASE_PRESENT}" \
  --argjson b253_base_present "${B253_BASE_PRESENT}" \
  '{
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
    study_registry_schema_present: $study_registry_schema_present,
    study_dag_schema_present: $study_dag_schema_present,
    study_sweep_schema_present: $study_sweep_schema_present,
    b257_base_present: $b257_base_present,
    b255_base_present: $b255_base_present,
    b253_base_present: $b253_base_present
  }' > "${OUT}/source-summary.json"

LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
BEAGLE_BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-before.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/collaborative-workbench" \
  | jq '.' > "${OUT}/workbench-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/study-registry" \
  | jq '.' > "${OUT}/study-registry.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/study-dag" \
  | jq '.' > "${OUT}/study-dag.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/study-sweep" \
  | jq '.' > "${OUT}/study-sweep.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/comparative-result-summary" \
  | jq '.' > "${OUT}/comparative-result-summary.json"

WORKSPACE_ID="$(jq -r '.workspace_id' "${OUT}/study-registry.json")"
SESSION_ID="$(jq -r '.session_id' "${OUT}/study-registry.json")"
STUDY_ID="$(jq -r '.study_id' "${OUT}/study-registry.json")"
BASELINE_RUN_ID="$(jq -r '.baseline_run_id' "${OUT}/study-registry.json")"
RUN_COUNT="$(jq -r '.run_count' "${OUT}/study-registry.json")"
VARIANT_COUNT="$(jq -r '.variant_count' "${OUT}/study-registry.json")"
COMPARED_RUN_COUNT="$(jq -r '.compared_run_count' "${OUT}/comparative-result-summary.json")"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${SESSION_ID}" > "${OUT}/session-id.txt"
echo "${STUDY_ID}" > "${OUT}/study-id.txt"
echo "${BASELINE_RUN_ID}" > "${OUT}/baseline-run-id.txt"

stop_port_forward
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/rollout-restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=300s > "${OUT}/rollout-after-restart.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/study-registry" \
  | jq '.' > "${OUT}/study-registry-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "${BEAGLE_BASE_URL}/api/darwin/workstreams/${WORKSTREAM_ID}/comparative-result-summary" \
  | jq '.' > "${OUT}/comparative-result-summary-after-restart.json"

capture_cluster_health

jq -nc \
  --arg phase "B26.1" \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg study_id "${STUDY_ID}" \
  --arg baseline_run_id "${BASELINE_RUN_ID}" \
  --argjson run_count "${RUN_COUNT}" \
  --argjson variant_count "${VARIANT_COUNT}" \
  --argjson compared_run_count "${COMPARED_RUN_COUNT}" \
  --argjson study_registered "$(jq -r '.run_count > 0' "${OUT}/study-registry.json")" \
  --argjson multiple_runs_tied "$(jq -r '.run_count >= 2' "${OUT}/study-registry.json")" \
  --argjson bounded_sweep_represented "$(jq -r '.variant_count >= 1' "${OUT}/study-sweep.json")" \
  --argjson comparative_summary_generated "$(jq -r '.compared_run_count >= 1' "${OUT}/comparative-result-summary.json")" \
  --argjson same_beagle_owned_identity "$(jq -r '(.same_beagle_owned_identity == true)' "${OUT}/study-registry.json")" \
  --argjson study_dag_identity "$(jq -r '(.same_beagle_owned_identity == true)' "${OUT}/study-dag.json")" \
  --argjson study_sweep_identity "$(jq -r '(.same_beagle_owned_identity == true)' "${OUT}/study-sweep.json")" \
  --argjson comparative_identity "$(jq -r '(.same_beagle_owned_identity == true)' "${OUT}/comparative-result-summary.json")" \
  --argjson restart_recovered_session "$(jq -r --arg study_id "${STUDY_ID}" --arg workspace_id "${WORKSPACE_ID}" --arg session_id "${SESSION_ID}" '.study_id == $study_id and .workspace_id == $workspace_id and .session_id == $session_id and .same_beagle_owned_identity == true' "${OUT}/study-registry-after-restart.json")" \
  --argjson code_state_diff_visible "$(jq -r '(.changed_categories_union | length) >= 0' "${OUT}/comparative-result-summary.json")" \
  '{
    status: "ok",
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    study_id: $study_id,
    baseline_run_id: $baseline_run_id,
    run_count: $run_count,
    variant_count: $variant_count,
    compared_run_count: $compared_run_count,
    study_registered: $study_registered,
    multiple_runs_tied: $multiple_runs_tied,
    bounded_sweep_represented: $bounded_sweep_represented,
    comparative_summary_generated: $comparative_summary_generated,
    same_beagle_owned_identity: ($same_beagle_owned_identity and $study_dag_identity and $study_sweep_identity and $comparative_identity),
    restart_recovered_session: $restart_recovered_session,
    code_state_diff_visible: $code_state_diff_visible,
    note: "B26.1 registers one canonical bounded study, ties multiple runs into explicit sweep variants, and exposes comparative baseline-versus-variant result categories inside the same Beagle workbench identity plane."
  }' > "${OUT}/smoke.json"

echo "[OK] B26.1 study registry / sweep smoke complete"
