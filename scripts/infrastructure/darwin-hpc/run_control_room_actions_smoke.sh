#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18103}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/control-room-actions}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b153-${STAMP}}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-general-noninfra}"
EXPECTED_STATE_BEFORE="${EXPECTED_STATE_BEFORE:-canonical}"
EXPECTED_LAST_TRANSITION_BEFORE="${EXPECTED_LAST_TRANSITION_BEFORE:-resume}"
HELD_STATE="${HELD_STATE:-held}"
HELD_LAST_TRANSITION="${HELD_LAST_TRANSITION:-hold}"
RESUMED_STATE="${RESUMED_STATE:-canonical}"
RESUMED_LAST_TRANSITION="${RESUMED_LAST_TRANSITION:-resume}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b153-${STAMP}-seed-cpu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
CONTROL_ROOM_SOURCE_FILE="${CONTROL_ROOM_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_control_room.rs}"
WORKSPACE_SOURCE_FILE="${WORKSPACE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B153_CONTROL_ROOM_ACTIONS.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B153_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B153_KNOWN_LIMITS.md}"
GOVERNANCE_LEDGER_PATH="${GOVERNANCE_LEDGER_PATH:-/var/lib/beagle/workspace-plane/workstream-governance-actions.jsonl}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require base64
require curl
require jq
require podman
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

  if [[ -f /etc/kubernetes/admin.conf ]] && command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
    return 0
  fi

  printf '%s\n' kubectl
}

KUBECTL="$(resolve_kubectl)"
require "${KUBECTL%% *}"

resolve_operator_api_token() {
  if [[ -n "${OPERATOR_API_TOKEN}" ]]; then
    printf '%s\n' "${OPERATOR_API_TOKEN}"
    return 0
  fi

  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi

  if [[ -n "${encoded_token}" ]]; then
    printf '%s' "${encoded_token}" | base64 -d
    return 0
  fi

  echo "[FAIL] BEAGLE_OPERATOR_API_TOKEN/BEAGLE_API_TOKEN not set locally and not found in secret ${SECRET_NAME}" >&2
  exit 1
}

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
mkdir -p "${OUT}"

choose_local_port() {
  local port="${LOCAL_PORT}"
  local max_tries=20
  local try=0

  while (( try < max_tries )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    try=$((try + 1))
  done

  echo "[FAIL] unable to find a free local port starting at ${LOCAL_PORT}" >&2
  exit 1
}

start_port_forward() {
  local port="$1"
  local pf_log="$2"

  : > "${pf_log}"
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${port}:8080" >"${pf_log}" 2>&1 &
  PF_PID=$!

  for _ in $(seq 1 20); do
    if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

wait_for_health() {
  local port="$1"
  local target="$2"

  for _ in $(seq 1 20); do
    if curl -fsS \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" \
      > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before health became ready" >&2
      cat "${PF_LOG}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] Beagle health endpoint did not become ready on local port ${port}" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
    echo
    echo "## darwin-gateway"
    ${KUBECTL} -n darwin-platform get deploy,svc,pods -l app.kubernetes.io/name=darwin-hpc-gateway -o wide || true
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

rollout_service() {
  local restart_log="$1"
  local rollout_log="$2"

  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${rollout_log}"
}

curl_json() {
  local method="$1"
  local path="$2"
  local target="$3"
  local body="${4:-}"

  if [[ -n "${body}" ]]; then
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      -H 'Content-Type: application/json' \
      --data @"${body}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  fi
}

capture_governance_ledger_tail() {
  local pod_name=""
  pod_name="$(${KUBECTL} -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=beagle-core -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | tail -n 1)"
  if [[ -z "${pod_name}" ]]; then
    : > "${OUT}/governance-ledger-tail.jsonl"
    return 0
  fi

  ${KUBECTL} -n "${NAMESPACE}" exec "${pod_name}" -- sh -lc "if [ -f '${GOVERNANCE_LEDGER_PATH}' ]; then tail -n 20 '${GOVERNANCE_LEDGER_PATH}'; fi" \
    > "${OUT}/governance-ledger-tail.jsonl"
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

LOCAL_PORT="$(choose_local_port)"
PF_LOG="${OUT}/port-forward.log"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_WORKSTREAM}" > "${OUT}/expected-workstream.txt"
echo "${EXPECTED_REPO}" > "${OUT}/expected-repo.txt"
echo "${EXPECTED_BRANCH}" > "${OUT}/expected-branch.txt"
echo "${EXPECTED_DEFAULT_DEV_PLANE}" > "${OUT}/expected-default-dev-plane.txt"
echo "${EXPECTED_VM_FALLBACK_ROLE}" > "${OUT}/expected-vm-fallback-role.txt"
echo "${EXPECTED_PROMOTION_SCOPE}" > "${OUT}/expected-promotion-scope.txt"
echo "${EXPECTED_STATE_BEFORE}" > "${OUT}/expected-state-before.txt"
echo "${EXPECTED_LAST_TRANSITION_BEFORE}" > "${OUT}/expected-last-transition-before.txt"
echo "${HELD_STATE}" > "${OUT}/expected-held-state.txt"
echo "${HELD_LAST_TRANSITION}" > "${OUT}/expected-held-last-transition.txt"
echo "${RESUMED_STATE}" > "${OUT}/expected-resumed-state.txt"
echo "${RESUMED_LAST_TRANSITION}" > "${OUT}/expected-resumed-last-transition.txt"
echo "${SEED_PROFILE_ID}" > "${OUT}/seed-profile-id.txt"
echo "${SEED_RUN_LABEL}" > "${OUT}/seed-run-label.txt"

ACTION_SOURCE_PRESENT=0
WORKSPACE_SOURCE_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "run_workstream_control_room_action|workstream-governance-actions.jsonl|bounded control-room action" "${CONTROL_ROOM_SOURCE_FILE}"; then
  ACTION_SOURCE_PRESENT=1
fi
if rg -q "normalize_workstream_governance_state|runtime_governance_state_survives_load_and_bootstrap_normalization" "${WORKSPACE_SOURCE_FILE}"; then
  WORKSPACE_SOURCE_PRESENT=1
fi
if rg -q "Control Room Actions|actions:" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "workstream_control_room_hold_handler|workstream_control_room_resume_handler|workstream_control_room_action_error" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if [[ -s "${DOC_FILE}" ]]; then
  DOC_PRESENT=1
fi
if [[ -s "${GO_NO_GO_FILE}" ]]; then
  GO_NO_GO_PRESENT=1
fi
if [[ -s "${KNOWN_LIMITS_FILE}" ]]; then
  KNOWN_LIMITS_PRESENT=1
fi

jq -nc \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg held_state "${HELD_STATE}" \
  --arg held_last_transition "${HELD_LAST_TRANSITION}" \
  --arg resumed_state "${RESUMED_STATE}" \
  --arg resumed_last_transition "${RESUMED_LAST_TRANSITION}" \
  --argjson action_source_present "${ACTION_SOURCE_PRESENT}" \
  --argjson workspace_source_present "${WORKSPACE_SOURCE_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_state_before: $expected_state_before,
    expected_last_transition_before: $expected_last_transition_before,
    held_state: $held_state,
    held_last_transition: $held_last_transition,
    resumed_state: $resumed_state,
    resumed_last_transition: $resumed_last_transition,
    action_source_present: $action_source_present,
    workspace_source_present: $workspace_source_present,
    cockpit_source_present: $cockpit_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' \
  > "${OUT}/control-room-actions-source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_service "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"

cat > "${OUT}/seed-pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${SEED_PROFILE_ID}",
  "run_label": "${SEED_RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF

curl_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/seed-pilot.json" "${OUT}/seed-pilot-request.json"
SEED_PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/seed-pilot.json")"
SEED_SESSION_ID="$(jq -r '.session_id' "${OUT}/seed-pilot.json")"
if [[ -z "${SEED_PUBLISHED_RESULT_JOB_ID}" || "${SEED_PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing published_result.job_id" >&2
  exit 1
fi
if [[ -z "${SEED_SESSION_ID}" || "${SEED_SESSION_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing session_id" >&2
  exit 1
fi
echo "${SEED_PUBLISHED_RESULT_JOB_ID}" > "${OUT}/seed-published-result-job-id.txt"
echo "${SEED_SESSION_ID}" > "${OUT}/seed-session-id.txt"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cockpit" "${OUT}/cockpit-before.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/status-before.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/handoff" "${OUT}/handoff-before.json"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/hold" "${OUT}/action-hold.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cockpit" "${OUT}/cockpit-held.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/status-held.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/handoff" "${OUT}/handoff-held.json"

curl_json POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/resume" "${OUT}/action-resume.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cockpit" "${OUT}/cockpit-resumed.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/status-resumed.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/handoff" "${OUT}/handoff-resumed.json"
stop_port_forward

rollout_service "${OUT}/restart-for-recovery.txt" "${OUT}/recovery-rollout.log"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cockpit" "${OUT}/cockpit-after-restart.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/status-after-restart.json"
stop_port_forward

capture_governance_ledger_tail
capture_cluster_health

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg held_state "${HELD_STATE}" \
  --arg held_last_transition "${HELD_LAST_TRANSITION}" \
  --arg resumed_state "${RESUMED_STATE}" \
  --arg resumed_last_transition "${RESUMED_LAST_TRANSITION}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --slurpfile seed_pilot "${OUT}/seed-pilot.json" \
  --slurpfile cockpit_before "${OUT}/cockpit-before.json" \
  --slurpfile status_before "${OUT}/status-before.json" \
  --slurpfile action_hold "${OUT}/action-hold.json" \
  --slurpfile cockpit_held "${OUT}/cockpit-held.json" \
  --slurpfile status_held "${OUT}/status-held.json" \
  --slurpfile handoff_held "${OUT}/handoff-held.json" \
  --slurpfile action_resume "${OUT}/action-resume.json" \
  --slurpfile cockpit_resumed "${OUT}/cockpit-resumed.json" \
  --slurpfile status_resumed "${OUT}/status-resumed.json" \
  --slurpfile handoff_resumed "${OUT}/handoff-resumed.json" \
  --slurpfile bootstrap_after_restart "${OUT}/bootstrap-after-restart.json" \
  --slurpfile session_after_restart "${OUT}/session-after-restart.json" \
  --slurpfile cockpit_after_restart "${OUT}/cockpit-after-restart.json" \
  --slurpfile status_after_restart "${OUT}/status-after-restart.json" \
  '{
    status: (
      if (
        ($seed_pilot[0].final_job.state // "") == "COMPLETED"
        and ($cockpit_before[0].envelope.workspace_id // "") == $workspace_id
        and ($status_before[0].governance_state // "") == $expected_state_before
        and ($status_before[0].governance_last_transition // "") == $expected_last_transition_before
        and ($action_hold[0].governance_state // "") == $held_state
        and ($action_hold[0].governance_last_transition // "") == $held_last_transition
        and ($status_held[0].governance_state // "") == $held_state
        and ($status_held[0].governance_last_transition // "") == $held_last_transition
        and ($action_resume[0].governance_state // "") == $resumed_state
        and ($action_resume[0].governance_last_transition // "") == $resumed_last_transition
        and ($status_resumed[0].governance_state // "") == $resumed_state
        and ($status_resumed[0].governance_last_transition // "") == $resumed_last_transition
        and ($bootstrap_after_restart[0].session_id // "") == ($seed_pilot[0].session_id // "")
        and ($status_after_restart[0].governance_state // "") == $resumed_state
        and ($status_after_restart[0].governance_last_transition // "") == $resumed_last_transition
      ) then "ok" else "unexpected" end
    ),
    workspace_id: $workspace_id,
    expected_workstream: $expected_workstream,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    seed_profile_id: $seed_profile_id,
    seed_run_label: $seed_run_label,
    seed_session_id: ($seed_pilot[0].session_id // ""),
    seed_published_result_job_id: ($seed_pilot[0].published_result.job_id // null),
    state_before: ($status_before[0].governance_state // ""),
    last_transition_before: ($status_before[0].governance_last_transition // ""),
    hold_session_id: ($action_hold[0].session_id // ""),
    held_state: ($status_held[0].governance_state // ""),
    held_last_transition: ($status_held[0].governance_last_transition // ""),
    resume_session_id: ($action_resume[0].session_id // ""),
    resumed_state: ($status_resumed[0].governance_state // ""),
    resumed_last_transition: ($status_resumed[0].governance_last_transition // ""),
    restarted_session_id: ($session_after_restart[0].session_id // ""),
    same_session_line: (
      ($seed_pilot[0].session_id // "") == ($action_hold[0].session_id // "")
      and ($action_hold[0].session_id // "") == ($action_resume[0].session_id // "")
      and ($action_resume[0].session_id // "") == ($session_after_restart[0].session_id // "")
    ),
    hold_handoff: ($handoff_held[0].last_handoff // ""),
    resume_handoff: ($handoff_resumed[0].last_handoff // ""),
    hold_last_result_job_id: ($handoff_held[0].last_result_reference.job_id // null),
    resume_last_result_job_id: ($handoff_resumed[0].last_result_reference.job_id // null),
    cockpit_recipe_count: ($cockpit_after_restart[0].envelope.recipe_count // 0),
    fallback_active_after_restart: ($session_after_restart[0].fallback_active // false),
    active_dev_plane_after_restart: ($session_after_restart[0].active_dev_plane // "")
  }' \
  > "${OUT}/smoke.json"

echo "[OK] control room actions smoke completed"
