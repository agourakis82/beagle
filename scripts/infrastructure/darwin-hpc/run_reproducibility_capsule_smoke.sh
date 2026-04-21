#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/reproducibility-capsule}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18495}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B254_BASE_OUT="${B254_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/deterministic-result-binding}"

RUN_CAPSULE_SOURCE_FILE="${RUN_CAPSULE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/run_capsule.rs}"
RUN_DIFF_SOURCE_FILE="${RUN_DIFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/run_diff.rs}"
WORKBENCH_RUN_SOURCE_FILE="${WORKBENCH_RUN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_run.rs}"
WORKBENCH_RESULT_BINDING_SOURCE_FILE="${WORKBENCH_RESULT_BINDING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_result_binding.rs}"
WORKSPACE_PLANE_SOURCE_FILE="${WORKSPACE_PLANE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B255_REPRODUCIBILITY_CAPSULES_RUN_LINEAGE_DIFF.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B255_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B255_KNOWN_LIMITS.md}"
RUN_CAPSULE_SCHEMA_FILE="${RUN_CAPSULE_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/run-capsule-schema.yaml}"
RUN_DIFF_SCHEMA_FILE="${RUN_DIFF_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/run-diff-schema.yaml}"
REPLAY_REQUEST_SCHEMA_FILE="${REPLAY_REQUEST_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/replay-request-schema.yaml}"

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

RUN_CAPSULE_SOURCE_PRESENT=0
RUN_DIFF_SOURCE_PRESENT=0
WORKBENCH_RUN_SOURCE_PRESENT=0
WORKBENCH_RESULT_BINDING_SOURCE_PRESENT=0
WORKSPACE_PLANE_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
RUN_CAPSULE_SCHEMA_PRESENT=0
RUN_DIFF_SCHEMA_PRESENT=0
REPLAY_REQUEST_SCHEMA_PRESENT=0
B254_BASE_PRESENT=0

if rg -q "RunCapsule|record_run_capsule|read_latest_run_capsule" "${RUN_CAPSULE_SOURCE_FILE}"; then
  RUN_CAPSULE_SOURCE_PRESENT=1
fi
if rg -q "RunDiff|generate_run_diff|read_run_diff" "${RUN_DIFF_SOURCE_FILE}"; then
  RUN_DIFF_SOURCE_PRESENT=1
fi
if rg -q "record_run_capsule|WorkbenchRunOrchestrationBundle|orchestrate_workbench_run" "${WORKBENCH_RUN_SOURCE_FILE}"; then
  WORKBENCH_RUN_SOURCE_PRESENT=1
fi
if rg -q "RunResultIdentityReceipt|DeterministicResultBinding|WorkbenchResultBinding" "${WORKBENCH_RESULT_BINDING_SOURCE_FILE}"; then
  WORKBENCH_RESULT_BINDING_SOURCE_PRESENT=1
fi
if rg -q "WorkspacePilotResponse|requested_run_label|published_result_manifest" "${WORKSPACE_PLANE_SOURCE_FILE}"; then
  WORKSPACE_PLANE_SOURCE_PRESENT=1
fi
if rg -q "pub mod run_capsule|pub mod run_diff|RunCapsule|RunDiff|ReplayRequest" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/run-capsule|/prior-run-capsule|/run-diff|/replay-request" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${RUN_CAPSULE_SCHEMA_FILE}" ]] && RUN_CAPSULE_SCHEMA_PRESENT=1
[[ -f "${RUN_DIFF_SCHEMA_FILE}" ]] && RUN_DIFF_SCHEMA_PRESENT=1
[[ -f "${REPLAY_REQUEST_SCHEMA_FILE}" ]] && REPLAY_REQUEST_SCHEMA_PRESENT=1
[[ -f "${B254_BASE_OUT}/smoke.json" ]] && B254_BASE_PRESENT=1

jq -nc \
  --argjson run_capsule_source_present "${RUN_CAPSULE_SOURCE_PRESENT}" \
  --argjson run_diff_source_present "${RUN_DIFF_SOURCE_PRESENT}" \
  --argjson workbench_run_source_present "${WORKBENCH_RUN_SOURCE_PRESENT}" \
  --argjson workbench_result_binding_source_present "${WORKBENCH_RESULT_BINDING_SOURCE_PRESENT}" \
  --argjson workspace_plane_source_present "${WORKSPACE_PLANE_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson run_capsule_schema_present "${RUN_CAPSULE_SCHEMA_PRESENT}" \
  --argjson run_diff_schema_present "${RUN_DIFF_SCHEMA_PRESENT}" \
  --argjson replay_request_schema_present "${REPLAY_REQUEST_SCHEMA_PRESENT}" \
  --argjson b254_base_present "${B254_BASE_PRESENT}" \
  '{
    run_capsule_source_present: $run_capsule_source_present,
    run_diff_source_present: $run_diff_source_present,
    workbench_run_source_present: $workbench_run_source_present,
    workbench_result_binding_source_present: $workbench_result_binding_source_present,
    workspace_plane_source_present: $workspace_plane_source_present,
    lib_source_present: $lib_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    run_capsule_schema_present: $run_capsule_schema_present,
    run_diff_schema_present: $run_diff_schema_present,
    replay_request_schema_present: $replay_request_schema_present,
    b254_base_present: $b254_base_present
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
PRIOR_RUN_LABEL="${PRIOR_RUN_LABEL:-b255-$(date +%m%d%H%M%S)-prior-cpu-short}"
CURRENT_RUN_LABEL="${CURRENT_RUN_LABEL:-b255-$(date +%m%d%H%M%S)-current-cpu-batch}"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${SESSION_ID}" > "${OUT}/session-id.txt"
echo "${PRIOR_RUN_LABEL}" > "${OUT}/prior-run-label.txt"
echo "${CURRENT_RUN_LABEL}" > "${OUT}/current-run-label.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-before.json"

cat > "${OUT}/prior-workbench-run-request.json" <<EOF
{
  "requested_by": "partner-dev",
  "requester_role_id": "partner-dev",
  "selected_subagent_id": "experiments",
  "task_family": "analysis",
  "intent_text": "Create the prior bounded analysis run capsule for the canonical B25.5 reproducibility smoke.",
  "compute_profile_id": "cpu-short-v1",
  "run_label": "${PRIOR_RUN_LABEL}",
  "recipe_kind": "reproducibility-prior",
  "experiment_id": "b255-prior-run",
  "reservation_note": "Reserve the bounded partner-dev cpu-short lane for the prior B25.5 reproducibility capsule run.",
  "dispatch_note": "Dispatch the prior bounded analysis run so the workbench can capture a direct-parent capsule lineage baseline.",
  "poll_interval_seconds": 5,
  "timeout_seconds": 600
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/prior-workbench-run-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-run" \
  > "${OUT}/prior-workbench-run-dispatch-response.json"

cat > "${OUT}/current-workbench-run-request.json" <<EOF
{
  "requested_by": "beagle-operator",
  "requester_role_id": "beagle-operator",
  "selected_subagent_id": "experiments",
  "task_family": "analysis",
  "intent_text": "Create the current bounded analysis run capsule for the canonical B25.5 reproducibility smoke.",
  "compute_profile_id": "cpu-batch-v1",
  "run_label": "${CURRENT_RUN_LABEL}",
  "recipe_kind": "reproducibility-current",
  "experiment_id": "b255-current-run",
  "reservation_note": "Reserve the operator cpu-batch lane for the current B25.5 reproducibility capsule run.",
  "dispatch_note": "Dispatch the current bounded analysis run with a different compute profile so the workbench can explain config and environment changes explicitly.",
  "poll_interval_seconds": 5,
  "timeout_seconds": 600
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/current-workbench-run-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-run" \
  > "${OUT}/current-workbench-run-dispatch-response.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/prior-run-capsule" \
  > "${OUT}/prior-run-capsule.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-diff" \
  > "${OUT}/run-diff.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-request" \
  > "${OUT}/replay-request.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/workbench-context-after-run.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-request" \
  > "${OUT}/replay-request-after-restart.json"

jq -n \
  --slurpfile current "${OUT}/run-capsule.json" \
  --slurpfile prior "${OUT}/prior-run-capsule.json" \
  --slurpfile diff "${OUT}/run-diff.json" \
  --slurpfile replay "${OUT}/replay-request.json" \
  --slurpfile bootstrap_before "${OUT}/bootstrap-before.json" \
  --slurpfile bootstrap_after "${OUT}/bootstrap-after-restart.json" \
  --slurpfile workbench_before "${OUT}/workbench-before.json" \
  '{
    status: "ok",
    phase: "B25.5",
    workstream_id: $current[0].workstream_id,
    workspace_id: $current[0].workspace_id,
    session_id: $current[0].session_id,
    same_beagle_owned_identity: (
      $current[0].same_beagle_owned_identity and
      $prior[0].same_beagle_owned_identity and
      $diff[0].same_beagle_owned_identity
    ),
    current_run_id: $current[0].run_id,
    prior_run_id: $prior[0].run_id,
    current_parent_run_id: $current[0].parent_run_id,
    current_submitted_job_id: $current[0].submitted_job_id,
    prior_submitted_job_id: $prior[0].submitted_job_id,
    current_run_label: $current[0].run_label,
    prior_run_label: $prior[0].run_label,
    code_diff_explicit: (
      ($diff[0].code.prior_summary | length) > 0 and
      ($diff[0].code.current_summary | length) > 0
    ),
    config_changed: $diff[0].config.changed,
    environment_changed: $diff[0].environment.changed,
    result_changed: $diff[0].result.changed,
    replay_request_source_run_id: $replay[0].source_run_id,
    replay_request_source_job_id: $replay[0].source_submitted_job_id,
    partner_access_state: $workbench_before[0].collaboration_access.partner_access_state,
    bootstrap_recovered_before: $bootstrap_before[0].recovered_session,
    restart_recovered_session: $bootstrap_after[0].recovered_session,
    note: "B25.5 captures one replay-grade run capsule per workbench run, compares the latest run to its direct-parent lineage capsule, and preserves deterministic linkage after restart."
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] reproducibility capsule smoke artifacts written to ${OUT}"
