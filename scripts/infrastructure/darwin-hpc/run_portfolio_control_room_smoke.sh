#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18110}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/portfolio-control-room}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
RUN_ID="${RUN_ID:-b162-portfolio-${STAMP}}"
GOVERNANCE_WORKSTREAM="${GOVERNANCE_WORKSTREAM:-beagle-darwin-hpc-governance}"
WAVE1_WORKSTREAM="${WAVE1_WORKSTREAM:-beagle-darwin-hpc-wave1}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_GOVERNANCE_STATE="${EXPECTED_GOVERNANCE_STATE:-canonical}"
EXPECTED_GOVERNANCE_LAST_TRANSITION="${EXPECTED_GOVERNANCE_LAST_TRANSITION:-resume}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
CONTROL_ROOM_SOURCE_FILE="${CONTROL_ROOM_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_control_room.rs}"
TIMELINE_SOURCE_FILE="${TIMELINE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_timeline.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B162_PORTFOLIO_CONTROL_ROOM.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B162_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B162_KNOWN_LIMITS.md}"
REGISTRY_FILE="${REGISTRY_FILE:-${ROOT}/docs/darwin/hpc/workstreams/registry.yaml}"

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

  curl -fsS -X "${method}" \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${LOCAL_PORT}${path}" \
    > "${target}"
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

LOCAL_PORT="$(choose_local_port)"
PF_LOG="${OUT}/port-forward.log"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${RUN_ID}" > "${OUT}/run-id.txt"
echo "${GOVERNANCE_WORKSTREAM}" > "${OUT}/governance-workstream-id.txt"
echo "${WAVE1_WORKSTREAM}" > "${OUT}/wave1-workstream-id.txt"
echo "${EXPECTED_DEFAULT_DEV_PLANE}" > "${OUT}/expected-default-dev-plane.txt"
echo "${EXPECTED_VM_FALLBACK_ROLE}" > "${OUT}/expected-vm-fallback-role.txt"
echo "${EXPECTED_GOVERNANCE_STATE}" > "${OUT}/expected-governance-state.txt"
echo "${EXPECTED_GOVERNANCE_LAST_TRANSITION}" > "${OUT}/expected-governance-last-transition.txt"

CONTROL_ROOM_SOURCE_PRESENT=0
TIMELINE_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
REGISTRY_PRESENT=0

if rg -q "get_workstream_portfolio_control_room|WorkstreamPortfolioResponse|WorkstreamPortfolioEntry" "${CONTROL_ROOM_SOURCE_FILE}"; then
  CONTROL_ROOM_SOURCE_PRESENT=1
fi
if rg -q "get_workstream_timeline|get_workstream_timeline_event" "${TIMELINE_SOURCE_FILE}"; then
  TIMELINE_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/portfolio/workstreams|workstream_portfolio_control_room_handler" "${HTTP_SOURCE_FILE}"; then
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
if [[ -s "${REGISTRY_FILE}" ]]; then
  REGISTRY_PRESENT=1
fi

jq -nc \
  --arg run_id "${RUN_ID}" \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --argjson control_room_source_present "${CONTROL_ROOM_SOURCE_PRESENT}" \
  --argjson timeline_source_present "${TIMELINE_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson registry_present "${REGISTRY_PRESENT}" \
  '{
    run_id: $run_id,
    governance_workstream: $governance_workstream,
    wave1_workstream: $wave1_workstream,
    control_room_source_present: $control_room_source_present,
    timeline_source_present: $timeline_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    registry_present: $registry_present
  }' > "${OUT}/source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_service "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"

curl_json GET "/api/darwin/workstreams" "${OUT}/workstreams-list.json"
curl_json GET "/api/darwin/portfolio/workstreams" "${OUT}/portfolio.json"

curl_json GET "/api/darwin/workstreams/${GOVERNANCE_WORKSTREAM}/status" "${OUT}/governance-status.json"
curl_json GET "/api/darwin/workstreams/${GOVERNANCE_WORKSTREAM}/handoff" "${OUT}/governance-handoff.json"
curl_json GET "/api/darwin/workstreams/${GOVERNANCE_WORKSTREAM}/last-result" "${OUT}/governance-last-result.json"
curl_json GET "/api/darwin/workstreams/${GOVERNANCE_WORKSTREAM}/timeline?limit=1" "${OUT}/governance-timeline.json"

curl_json GET "/api/darwin/workstreams/${WAVE1_WORKSTREAM}/status" "${OUT}/wave1-status.json"
curl_json GET "/api/darwin/workstreams/${WAVE1_WORKSTREAM}/handoff" "${OUT}/wave1-handoff.json"
curl_json GET "/api/darwin/workstreams/${WAVE1_WORKSTREAM}/last-result" "${OUT}/wave1-last-result.json"
curl_json GET "/api/darwin/workstreams/${WAVE1_WORKSTREAM}/timeline?limit=1" "${OUT}/wave1-timeline.json"
stop_port_forward

GOVERNANCE_WORKSPACE_ID="$(jq -r '.live_session.workspace_id' "${OUT}/governance-status.json")"
GOVERNANCE_SESSION_ID="$(jq -r '.live_session.session_id' "${OUT}/governance-status.json")"
WAVE1_WORKSPACE_ID="$(jq -r '.live_session.workspace_id' "${OUT}/wave1-status.json")"
WAVE1_SESSION_ID="$(jq -r '.live_session.session_id' "${OUT}/wave1-status.json")"
echo "${GOVERNANCE_WORKSPACE_ID}" > "${OUT}/governance-workspace-id.txt"
echo "${GOVERNANCE_SESSION_ID}" > "${OUT}/governance-session-id.txt"
echo "${WAVE1_WORKSPACE_ID}" > "${OUT}/wave1-workspace-id.txt"
echo "${WAVE1_SESSION_ID}" > "${OUT}/wave1-session-id.txt"

rollout_service "${OUT}/restart-for-recovery.txt" "${OUT}/recovery-rollout.log"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/portfolio/workstreams" "${OUT}/portfolio-after-restart.json"
stop_port_forward

capture_cluster_health

jq -nc \
  --arg run_id "${RUN_ID}" \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_governance_last_transition "${EXPECTED_GOVERNANCE_LAST_TRANSITION}" \
  --arg governance_workspace_id "${GOVERNANCE_WORKSPACE_ID}" \
  --arg governance_session_id "${GOVERNANCE_SESSION_ID}" \
  --arg wave1_workspace_id "${WAVE1_WORKSPACE_ID}" \
  --arg wave1_session_id "${WAVE1_SESSION_ID}" \
  --slurpfile list "${OUT}/workstreams-list.json" \
  --slurpfile portfolio "${OUT}/portfolio.json" \
  --slurpfile governance_status "${OUT}/governance-status.json" \
  --slurpfile governance_handoff "${OUT}/governance-handoff.json" \
  --slurpfile governance_last_result "${OUT}/governance-last-result.json" \
  --slurpfile governance_timeline "${OUT}/governance-timeline.json" \
  --slurpfile wave1_status "${OUT}/wave1-status.json" \
  --slurpfile wave1_handoff "${OUT}/wave1-handoff.json" \
  --slurpfile wave1_last_result "${OUT}/wave1-last-result.json" \
  --slurpfile wave1_timeline "${OUT}/wave1-timeline.json" \
  --slurpfile portfolio_after_restart "${OUT}/portfolio-after-restart.json" \
  'def portfolio_entry($id): ($portfolio[0].workstreams[] | select(.id == $id));
   def portfolio_entry_after_restart($id): ($portfolio_after_restart[0].workstreams[] | select(.id == $id));
   def timeline_event($doc): ($doc[0].events[0]);
   {
     status: (
       if (
         ($list[0].status // "") == "ok"
         and ($portfolio[0].status // "") == "ok"
         and ($portfolio_after_restart[0].status // "") == "ok"
         and (($list[0].workstreams | map(.id) | index($governance_workstream)) != null)
         and (($list[0].workstreams | map(.id) | index($wave1_workstream)) != null)
         and (($portfolio[0].canonical_workstream_ids | index($governance_workstream)) != null)
         and (($portfolio[0].canonical_workstream_ids | index($wave1_workstream)) != null)
         and ($portfolio[0].summary.total_workstreams // 0) >= 2
         and ($portfolio[0].summary.canonical_workstreams // 0) >= 2
         and ($portfolio[0].summary.live_sessions // 0) >= 2
         and (portfolio_entry($governance_workstream).live_session.workspace_id // "") == $governance_workspace_id
         and (portfolio_entry($governance_workstream).live_session.session_id // "") == $governance_session_id
         and (portfolio_entry($governance_workstream).default_dev_plane // "") == $expected_default_dev_plane
         and (portfolio_entry($governance_workstream).vm_fallback_role // "") == $expected_vm_fallback_role
         and (portfolio_entry($governance_workstream).governance_state // "") == $expected_governance_state
         and (portfolio_entry($governance_workstream).governance_last_transition // "") == $expected_governance_last_transition
         and (portfolio_entry($governance_workstream).handoff_present // false) == ($governance_handoff[0].handoff_present // false)
         and (portfolio_entry($governance_workstream).last_handoff // null) == ($governance_handoff[0].last_handoff // null)
         and (portfolio_entry($governance_workstream).latest_activity.event_id // "") == (timeline_event($governance_timeline).event_id // "")
         and (portfolio_entry($governance_workstream).latest_activity.event_kind // "") == (timeline_event($governance_timeline).event_kind // "")
         and (portfolio_entry($governance_workstream).timeline_total_events // -1) == ($governance_timeline[0].total_events // -2)
         and (portfolio_entry($governance_workstream).result_ready // false) == ((($governance_last_result[0].result // null) != null) and (($governance_last_result[0].manifest // null) != null))
         and ((portfolio_entry($governance_workstream).last_result_reference.job_id // null) == ($governance_last_result[0].last_result_reference.job_id // null))
         and (portfolio_entry($wave1_workstream).live_session.workspace_id // "") == $wave1_workspace_id
         and (portfolio_entry($wave1_workstream).live_session.session_id // "") == $wave1_session_id
         and (portfolio_entry($wave1_workstream).default_dev_plane // "") == $expected_default_dev_plane
         and (portfolio_entry($wave1_workstream).vm_fallback_role // "") == $expected_vm_fallback_role
         and (portfolio_entry($wave1_workstream).governance_state // "") == $expected_governance_state
         and (portfolio_entry($wave1_workstream).governance_last_transition // "") == $expected_governance_last_transition
         and (portfolio_entry($wave1_workstream).handoff_present // false) == ($wave1_handoff[0].handoff_present // false)
         and (portfolio_entry($wave1_workstream).last_handoff // null) == ($wave1_handoff[0].last_handoff // null)
         and (portfolio_entry($wave1_workstream).latest_activity.event_id // "") == (timeline_event($wave1_timeline).event_id // "")
         and (portfolio_entry($wave1_workstream).latest_activity.event_kind // "") == (timeline_event($wave1_timeline).event_kind // "")
         and (portfolio_entry($wave1_workstream).timeline_total_events // -1) == ($wave1_timeline[0].total_events // -2)
         and (portfolio_entry($wave1_workstream).result_ready // false) == ((($wave1_last_result[0].result // null) != null) and (($wave1_last_result[0].manifest // null) != null))
         and ((portfolio_entry($wave1_workstream).last_result_reference.job_id // null) == ($wave1_last_result[0].last_result_reference.job_id // null))
         and (portfolio_entry_after_restart($governance_workstream).live_session.workspace_id // "") == $governance_workspace_id
         and (portfolio_entry_after_restart($governance_workstream).live_session.session_id // "") == $governance_session_id
         and (portfolio_entry_after_restart($wave1_workstream).live_session.workspace_id // "") == $wave1_workspace_id
         and (portfolio_entry_after_restart($wave1_workstream).live_session.session_id // "") == $wave1_session_id
       ) then "ok" else "unexpected" end
     ),
     run_id: $run_id,
     governance_workstream: $governance_workstream,
     wave1_workstream: $wave1_workstream,
     portfolio_workstream_count: ($portfolio[0].workstreams | length),
     canonical_workstream_count: ($portfolio[0].summary.canonical_workstreams // 0),
     live_session_count: ($portfolio[0].summary.live_sessions // 0),
     governance_workspace_id: $governance_workspace_id,
     governance_session_id: $governance_session_id,
     governance_activity_event_id: (timeline_event($governance_timeline).event_id // ""),
     governance_activity_event_kind: (timeline_event($governance_timeline).event_kind // ""),
     governance_result_job_id: ($governance_last_result[0].last_result_reference.job_id // null),
     wave1_workspace_id: $wave1_workspace_id,
     wave1_session_id: $wave1_session_id,
     wave1_activity_event_id: (timeline_event($wave1_timeline).event_id // ""),
     wave1_activity_event_kind: (timeline_event($wave1_timeline).event_kind // ""),
     wave1_result_job_id: ($wave1_last_result[0].last_result_reference.job_id // null),
     after_restart_governance_session_id: (portfolio_entry_after_restart($governance_workstream).live_session.session_id // ""),
     after_restart_wave1_session_id: (portfolio_entry_after_restart($wave1_workstream).live_session.session_id // "")
   }' > "${OUT}/smoke.json"
