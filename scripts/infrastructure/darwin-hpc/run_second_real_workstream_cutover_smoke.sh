#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18109}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/second-real-workstream-cutover}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b161-wave1-${STAMP}}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-wave1}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-wave1}"
EXPECTED_BRANCH_LINEAGE="${EXPECTED_BRANCH_LINEAGE:-feat/darwin-hpc-wave1}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-general-noninfra}"
EXPECTED_GOVERNANCE_STATE="${EXPECTED_GOVERNANCE_STATE:-canonical}"
EXPECTED_LAST_TRANSITION="${EXPECTED_LAST_TRANSITION:-resume}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b161-${STAMP}-wave1-cpu}"
TIMELINE_LIMIT="${TIMELINE_LIMIT:-2}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
WORKSPACE_SOURCE_FILE="${WORKSPACE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
CONTROL_ROOM_SOURCE_FILE="${CONTROL_ROOM_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_control_room.rs}"
TIMELINE_SOURCE_FILE="${TIMELINE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_timeline.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
SPEC_FILE="${SPEC_FILE:-${ROOT}/docs/darwin/hpc/workstreams/beagle-darwin-hpc-wave1.yaml}"
RECIPE_REPO_FILE="${RECIPE_REPO_FILE:-${ROOT}/docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.repo_native_dev_loop.yaml}"
RECIPE_CPU_FILE="${RECIPE_CPU_FILE:-${ROOT}/docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.operator_cpu_loop.yaml}"
RECIPE_RECOVERY_FILE="${RECIPE_RECOVERY_FILE:-${ROOT}/docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.recovery_resume_loop.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B161_SECOND_REAL_WORKSTREAM_CUTOVER.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B161_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B161_KNOWN_LIMITS.md}"

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
echo "${EXPECTED_BRANCH_LINEAGE}" > "${OUT}/expected-branch-lineage.txt"
echo "${EXPECTED_DEFAULT_DEV_PLANE}" > "${OUT}/expected-default-dev-plane.txt"
echo "${EXPECTED_VM_FALLBACK_ROLE}" > "${OUT}/expected-vm-fallback-role.txt"
echo "${EXPECTED_PROMOTION_SCOPE}" > "${OUT}/expected-promotion-scope.txt"
echo "${EXPECTED_GOVERNANCE_STATE}" > "${OUT}/expected-governance-state.txt"
echo "${EXPECTED_LAST_TRANSITION}" > "${OUT}/expected-last-transition.txt"
echo "${SEED_PROFILE_ID}" > "${OUT}/seed-profile-id.txt"
echo "${SEED_RUN_LABEL}" > "${OUT}/seed-run-label.txt"
echo "${TIMELINE_LIMIT}" > "${OUT}/timeline-limit.txt"

WORKSPACE_SOURCE_PRESENT=0
CONTROL_ROOM_SOURCE_PRESENT=0
TIMELINE_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
SPEC_PRESENT=0
RECIPE_REPO_PRESENT=0
RECIPE_CPU_PRESENT=0
RECIPE_RECOVERY_PRESENT=0

if rg -q "WorkspacePilotWorkstreamOverride|new_with_workstream_override|workstream_override" "${WORKSPACE_SOURCE_FILE}"; then
  WORKSPACE_SOURCE_PRESENT=1
fi
if rg -q "resolve_registered_workstream|get_workstream_control_room_status|WorkstreamControlRoomStatusResponse" "${CONTROL_ROOM_SOURCE_FILE}"; then
  CONTROL_ROOM_SOURCE_PRESENT=1
fi
if rg -q "get_workstream_timeline|get_workstream_timeline_event|recovery_bootstrap" "${TIMELINE_SOURCE_FILE}"; then
  TIMELINE_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/workstreams|workstream_timeline_handler|workspace_pilot_execute_handler" "${HTTP_SOURCE_FILE}"; then
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
if [[ -s "${SPEC_FILE}" ]]; then
  SPEC_PRESENT=1
fi
if [[ -s "${RECIPE_REPO_FILE}" ]]; then
  RECIPE_REPO_PRESENT=1
fi
if [[ -s "${RECIPE_CPU_FILE}" ]]; then
  RECIPE_CPU_PRESENT=1
fi
if [[ -s "${RECIPE_RECOVERY_FILE}" ]]; then
  RECIPE_RECOVERY_PRESENT=1
fi

jq -nc \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --argjson workspace_source_present "${WORKSPACE_SOURCE_PRESENT}" \
  --argjson control_room_source_present "${CONTROL_ROOM_SOURCE_PRESENT}" \
  --argjson timeline_source_present "${TIMELINE_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson spec_present "${SPEC_PRESENT}" \
  --argjson recipe_repo_present "${RECIPE_REPO_PRESENT}" \
  --argjson recipe_cpu_present "${RECIPE_CPU_PRESENT}" \
  --argjson recipe_recovery_present "${RECIPE_RECOVERY_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_branch: $expected_branch,
    expected_branch_lineage: $expected_branch_lineage,
    expected_governance_state: $expected_governance_state,
    expected_last_transition: $expected_last_transition,
    workspace_source_present: $workspace_source_present,
    control_room_source_present: $control_room_source_present,
    timeline_source_present: $timeline_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    spec_present: $spec_present,
    recipe_repo_present: $recipe_repo_present,
    recipe_cpu_present: $recipe_cpu_present,
    recipe_recovery_present: $recipe_recovery_present
  }' > "${OUT}/source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_service "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"

cat > "${OUT}/seed-pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${SEED_PROFILE_ID}",
  "run_label": "${SEED_RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS},
  "workstream_override": {
    "workstream_id": "${EXPECTED_WORKSTREAM}",
    "default_branch": "${EXPECTED_BRANCH}",
    "branch_lineage": "${EXPECTED_BRANCH_LINEAGE}",
    "governance_state": "${EXPECTED_GOVERNANCE_STATE}",
    "governance_last_transition": "${EXPECTED_LAST_TRANSITION}"
  }
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

curl_json GET "/api/darwin/workstreams" "${OUT}/workstreams-list.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}" "${OUT}/workstream-detail.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/recipes" "${OUT}/workstream-recipes.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/workstream-status.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/last-result" "${OUT}/workstream-last-result.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/handoff" "${OUT}/workstream-handoff.json"
stop_port_forward

rollout_service "${OUT}/restart-for-recovery.txt" "${OUT}/recovery-rollout.log"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/workstream-status-after-restart.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/timeline" "${OUT}/timeline.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/timeline?limit=${TIMELINE_LIMIT}" "${OUT}/timeline-limit.json"

WORKFLOW_EVENT_ID="$(jq -r '.events[] | select(.event_kind == "workflow_completed") | .event_id' "${OUT}/timeline.json" | head -n 1)"
RECOVERY_EVENT_ID="$(jq -r '.events[] | select(.event_kind == "recovery_bootstrap") | .event_id' "${OUT}/timeline.json" | head -n 1)"
if [[ -z "${WORKFLOW_EVENT_ID}" || "${WORKFLOW_EVENT_ID}" == "null" ]]; then
  echo "[FAIL] timeline.json missing workflow_completed event_id" >&2
  exit 1
fi
if [[ -z "${RECOVERY_EVENT_ID}" || "${RECOVERY_EVENT_ID}" == "null" ]]; then
  echo "[FAIL] timeline.json missing recovery_bootstrap event_id" >&2
  exit 1
fi
echo "${WORKFLOW_EVENT_ID}" > "${OUT}/timeline-workflow-event-id.txt"
echo "${RECOVERY_EVENT_ID}" > "${OUT}/timeline-recovery-event-id.txt"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/timeline/${WORKFLOW_EVENT_ID}" "${OUT}/timeline-event-workflow.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/timeline/${RECOVERY_EVENT_ID}" "${OUT}/timeline-event-recovery.json"
stop_port_forward

capture_cluster_health

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_branch_lineage "${EXPECTED_BRANCH_LINEAGE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --arg seed_session_id "${SEED_SESSION_ID}" \
  --argjson timeline_limit "${TIMELINE_LIMIT}" \
  --slurpfile seed_pilot "${OUT}/seed-pilot.json" \
  --slurpfile list "${OUT}/workstreams-list.json" \
  --slurpfile detail "${OUT}/workstream-detail.json" \
  --slurpfile recipes "${OUT}/workstream-recipes.json" \
  --slurpfile status "${OUT}/workstream-status.json" \
  --slurpfile last_result "${OUT}/workstream-last-result.json" \
  --slurpfile handoff "${OUT}/workstream-handoff.json" \
  --slurpfile bootstrap_after_restart "${OUT}/bootstrap-after-restart.json" \
  --slurpfile session_after_restart "${OUT}/session-after-restart.json" \
  --slurpfile status_after_restart "${OUT}/workstream-status-after-restart.json" \
  --slurpfile timeline "${OUT}/timeline.json" \
  --slurpfile timeline_limit_doc "${OUT}/timeline-limit.json" \
  --slurpfile timeline_event_workflow "${OUT}/timeline-event-workflow.json" \
  --slurpfile timeline_event_recovery "${OUT}/timeline-event-recovery.json" \
  '{
    status: (
      if (
        ($seed_pilot[0].status // "") == "ok"
        and ($seed_pilot[0].workspace_id // "") == $workspace_id
        and ($seed_pilot[0].session_id // "") == $seed_session_id
        and ($seed_pilot[0].canonical_repo // "") == $expected_repo
        and ($seed_pilot[0].canonical_branch // "") == $expected_branch
        and ($seed_pilot[0].last_successful_task.profile_id // "") == $seed_profile_id
        and ($list[0].workstreams | map(.id) | index($expected_workstream) != null)
        and ($detail[0].spec.id // "") == $expected_workstream
        and ($detail[0].spec.default_branch // "") == $expected_branch
        and ($recipes[0].recipe_count // 0) >= 3
        and ($status[0].governance_state // "") == $expected_governance_state
        and ($status[0].governance_last_transition // "") == $expected_last_transition
        and ($status[0].live_session.workspace_id // "") == $workspace_id
        and ($status[0].live_session.session_id // "") == $seed_session_id
        and ($status[0].live_session.active_dev_plane // "") == $expected_default_dev_plane
        and ($status[0].live_session.fallback_active // false) == false
        and ($last_result[0].last_result_reference.job_id // null) == ($seed_pilot[0].published_result.job_id // null)
        and ($handoff[0].handoff_present // false) == true
        and ($bootstrap_after_restart[0].workspace_id // "") == $workspace_id
        and ($bootstrap_after_restart[0].session_id // "") == $seed_session_id
        and ($bootstrap_after_restart[0].workstream_cutover_policy.workstream_name // "") == $expected_workstream
        and ($bootstrap_after_restart[0].canonical_branch // "") == $expected_branch
        and ($session_after_restart[0].session_id // "") == $seed_session_id
        and ($session_after_restart[0].workstream_cutover_policy.workstream_name // "") == $expected_workstream
        and ($status_after_restart[0].live_session.session_id // "") == $seed_session_id
        and ($timeline[0].workstream_id // "") == $expected_workstream
        and ($timeline[0].identity.workspace_id // "") == $workspace_id
        and ($timeline[0].identity.session_id // "") == $seed_session_id
        and ($timeline[0].returned_events // 0) >= 4
        and ($timeline_limit_doc[0].returned_events // 0) == $timeline_limit
        and ($timeline_event_workflow[0].event.event_kind // "") == "workflow_completed"
        and ($timeline_event_recovery[0].event.event_kind // "") == "recovery_bootstrap"
      ) then "ok" else "unexpected" end
    ),
    workspace_id: $workspace_id,
    expected_workstream: $expected_workstream,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_branch_lineage: $expected_branch_lineage,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    expected_governance_state: $expected_governance_state,
    expected_last_transition: $expected_last_transition,
    seed_profile_id: $seed_profile_id,
    seed_run_label: $seed_run_label,
    seed_session_id: $seed_session_id,
    seed_published_result_job_id: ($seed_pilot[0].published_result.job_id // null),
    listed_workstreams: ($list[0].workstreams | map(.id)),
    detail_workstream_id: ($detail[0].spec.id // ""),
    detail_branch: ($detail[0].spec.default_branch // ""),
    recipes_count: ($recipes[0].recipe_count // 0),
    status_session_id: ($status[0].live_session.session_id // ""),
    status_active_dev_plane: ($status[0].live_session.active_dev_plane // ""),
    handoff_present: ($handoff[0].handoff_present // false),
    after_restart_session_id: ($bootstrap_after_restart[0].session_id // ""),
    after_restart_workstream: ($bootstrap_after_restart[0].workstream_cutover_policy.workstream_name // ""),
    timeline_returned_events: ($timeline[0].returned_events // 0),
    timeline_limit_returned_events: ($timeline_limit_doc[0].returned_events // 0),
    workflow_event_id: ($timeline_event_workflow[0].event.event_id // ""),
    recovery_event_id: ($timeline_event_recovery[0].event.event_id // "")
  }' > "${OUT}/smoke.json"
