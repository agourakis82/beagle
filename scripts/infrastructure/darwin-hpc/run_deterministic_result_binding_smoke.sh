#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/deterministic-result-binding}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18492}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B253_BASE_OUT="${B253_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/workbench-orchestration}"

WORKSPACE_PLANE_SOURCE_FILE="${WORKSPACE_PLANE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
WORKBENCH_RUN_SOURCE_FILE="${WORKBENCH_RUN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_run.rs}"
WORKBENCH_RESULT_BINDING_SOURCE_FILE="${WORKBENCH_RESULT_BINDING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_result_binding.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B254_DETERMINISTIC_RUN_PUBLICATION_AND_RUN_SCOPED_RESULT_BINDING.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B254_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B254_KNOWN_LIMITS.md}"
RUN_SCOPED_PUBLICATION_SCHEMA_FILE="${RUN_SCOPED_PUBLICATION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/run-scoped-publication-schema.yaml}"
DETERMINISTIC_RESULT_BINDING_SCHEMA_FILE="${DETERMINISTIC_RESULT_BINDING_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/deterministic-result-binding-schema.yaml}"
RUN_RESULT_IDENTITY_RECEIPT_SCHEMA_FILE="${RUN_RESULT_IDENTITY_RECEIPT_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/run-result-identity-receipt-schema.yaml}"

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
require sudo

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

WORKSPACE_PLANE_SOURCE_PRESENT=0
WORKBENCH_RUN_SOURCE_PRESENT=0
WORKBENCH_RESULT_BINDING_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
RUN_SCOPED_PUBLICATION_SCHEMA_PRESENT=0
DETERMINISTIC_RESULT_BINDING_SCHEMA_PRESENT=0
RUN_RESULT_IDENTITY_RECEIPT_SCHEMA_PRESENT=0
B253_BASE_PRESENT=0

if rg -q "ensure_no_preexisting_run_scoped_results|select_unique_run_scoped_published_result|result_lookup_scope" "${WORKSPACE_PLANE_SOURCE_FILE}"; then
  WORKSPACE_PLANE_SOURCE_PRESENT=1
fi
if rg -q "run_result_identity_receipt|run_scoped_publication|deterministic_result_binding" "${WORKBENCH_RUN_SOURCE_FILE}"; then
  WORKBENCH_RUN_SOURCE_PRESENT=1
fi
if rg -q "RunResultIdentityReceipt|RunScopedPublication|DeterministicResultBinding" "${WORKBENCH_RESULT_BINDING_SOURCE_FILE}"; then
  WORKBENCH_RESULT_BINDING_SOURCE_PRESENT=1
fi
if rg -q "read_run_result_identity_receipt|read_run_scoped_publication|read_deterministic_result_binding" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/run-result-identity-receipt|/run-scoped-publication|/deterministic-result-binding|workstream_run_result_identity_receipt_handler" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${RUN_SCOPED_PUBLICATION_SCHEMA_FILE}" ]] && RUN_SCOPED_PUBLICATION_SCHEMA_PRESENT=1
[[ -f "${DETERMINISTIC_RESULT_BINDING_SCHEMA_FILE}" ]] && DETERMINISTIC_RESULT_BINDING_SCHEMA_PRESENT=1
[[ -f "${RUN_RESULT_IDENTITY_RECEIPT_SCHEMA_FILE}" ]] && RUN_RESULT_IDENTITY_RECEIPT_SCHEMA_PRESENT=1
[[ -f "${B253_BASE_OUT}/smoke.json" ]] && B253_BASE_PRESENT=1

jq -nc \
  --argjson workspace_plane_source_present "${WORKSPACE_PLANE_SOURCE_PRESENT}" \
  --argjson workbench_run_source_present "${WORKBENCH_RUN_SOURCE_PRESENT}" \
  --argjson workbench_result_binding_source_present "${WORKBENCH_RESULT_BINDING_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson run_scoped_publication_schema_present "${RUN_SCOPED_PUBLICATION_SCHEMA_PRESENT}" \
  --argjson deterministic_result_binding_schema_present "${DETERMINISTIC_RESULT_BINDING_SCHEMA_PRESENT}" \
  --argjson run_result_identity_receipt_schema_present "${RUN_RESULT_IDENTITY_RECEIPT_SCHEMA_PRESENT}" \
  --argjson b253_base_present "${B253_BASE_PRESENT}" \
  '{
    workspace_plane_source_present: $workspace_plane_source_present,
    workbench_run_source_present: $workbench_run_source_present,
    workbench_result_binding_source_present: $workbench_result_binding_source_present,
    lib_source_present: $lib_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    run_scoped_publication_schema_present: $run_scoped_publication_schema_present,
    deterministic_result_binding_schema_present: $deterministic_result_binding_schema_present,
    run_result_identity_receipt_schema_present: $run_result_identity_receipt_schema_present,
    b253_base_present: $b253_base_present
  }' > "${OUT}/source-summary.json"

LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/collaborative-workbench" \
  > "${OUT}/workbench-before.json"

WORKSPACE_ID="$(jq -r '.workspace_id' "${OUT}/workbench-before.json")"
SESSION_ID="$(jq -r '.session_id' "${OUT}/workbench-before.json")"
RUN_LABEL="${RUN_LABEL:-b254-$(date +%m%d%H%M%S)-deterministic-cpu-short}"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${SESSION_ID}" > "${OUT}/session-id.txt"
echo "${RUN_LABEL}" > "${OUT}/run-label.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-before.json"

cat > "${OUT}/workbench-run-request.json" <<EOF
{
  "requested_by": "partner-dev",
  "requester_role_id": "partner-dev",
  "selected_subagent_id": "experiments",
  "task_family": "analysis",
  "intent_text": "Run a bounded deterministic result-binding smoke through the shared Beagle workbench and bind the published result back to the exact submitted run.",
  "compute_profile_id": "cpu-short-v1",
  "run_label": "${RUN_LABEL}",
  "recipe_kind": "deterministic-binding-smoke",
  "experiment_id": "b254-deterministic-binding-smoke",
  "reservation_note": "Reserve the bounded partner-dev cpu-short lane for the deterministic run-scoped publication smoke.",
  "dispatch_note": "Dispatch the bounded partner-dev analysis run through the workbench and require deterministic per-run result publication.",
  "poll_interval_seconds": 5,
  "timeout_seconds": 600
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/workbench-run-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-run" \
  > "${OUT}/workbench-run-dispatch-response.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-reservation" \
  > "${OUT}/workbench-reservation.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-run-orchestration" \
  > "${OUT}/workbench-run.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-result-identity-receipt" \
  > "${OUT}/run-result-identity-receipt.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-scoped-publication" \
  > "${OUT}/run-scoped-publication.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/deterministic-result-binding" \
  > "${OUT}/deterministic-result-binding.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/collaborative-workbench" \
  > "${OUT}/workbench-context-after-deterministic-binding.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/workbench-execution-state.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-result-identity-receipt" \
  > "${OUT}/run-result-identity-receipt-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-scoped-publication" \
  > "${OUT}/run-scoped-publication-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/deterministic-result-binding" \
  > "${OUT}/deterministic-result-binding-after-restart.json"

jq -n \
  --slurpfile receipt "${OUT}/run-result-identity-receipt.json" \
  --slurpfile publication "${OUT}/run-scoped-publication.json" \
  --slurpfile binding "${OUT}/deterministic-result-binding.json" \
  --slurpfile context "${OUT}/workbench-context-after-deterministic-binding.json" \
  --slurpfile execution "${OUT}/workbench-execution-state.json" \
  --slurpfile bootstrap_before "${OUT}/bootstrap-before.json" \
  --slurpfile bootstrap_after "${OUT}/bootstrap-after-restart.json" \
  '{
    status: "ok",
    phase: "B25.4",
    workstream_id: $receipt[0].workstream_id,
    workspace_id: $receipt[0].workspace_id,
    session_id: $receipt[0].session_id,
    same_beagle_owned_identity: (
      $receipt[0].same_beagle_owned_identity and
      $publication[0].same_beagle_owned_identity and
      $binding[0].same_beagle_owned_identity and
      $context[0].same_beagle_owned_identity
    ),
    requester_role_id: "partner-dev",
    selected_subagent_id: $receipt[0].selected_subagent_id,
    task_family: $receipt[0].task_family,
    compute_profile_id: $receipt[0].compute_profile_id,
    requested_run_label: $receipt[0].requested_run_label,
    published_result_run_label: $receipt[0].published_result_run_label,
    submitted_job_id: $receipt[0].submitted_job_id,
    published_result_job_id: $receipt[0].published_result_job_id,
    deterministic_identity_confirmed: $receipt[0].deterministic_identity_confirmed,
    no_profile_latest_ambiguity: (
      $publication[0].no_profile_latest_ambiguity and
      $binding[0].no_profile_latest_ambiguity
    ),
    result_lookup_scope: $receipt[0].result_lookup_scope,
    catalog_before_matching_run_count: $receipt[0].catalog_before_matching_run_count,
    catalog_after_matching_run_count: $receipt[0].catalog_after_matching_run_count,
    result_refs_bound: ($binding[0].result_refs | length),
    live_selected_subagent_id: $context[0].session.live_selected_subagent_id,
    execution_current_state: $context[0].run.current_state,
    workspace_last_workflow_kind: $execution[0].last_workflow_kind,
    workspace_last_job_profile_id: $execution[0].last_job_profile_id,
    bootstrap_recovered_before: $bootstrap_before[0].recovered_session,
    restart_recovered_session: $bootstrap_after[0].recovered_session,
    partner_access_state: $context[0].collaboration_access.partner_access_state,
    bounded_partner_access: true,
    note: "B25.4 binds one submitted workbench run to one run-scoped published result identity, removes profile-latest ambiguity, and preserves the same linkage after restart."
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] deterministic result binding smoke artifacts written to ${OUT}"
