#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18101}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/internal-workstream-control-room}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b151-${STAMP}}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-general-noninfra}"
EXPECTED_GOVERNANCE_STATE="${EXPECTED_GOVERNANCE_STATE:-canonical}"
EXPECTED_LAST_TRANSITION="${EXPECTED_LAST_TRANSITION:-resume}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b151-${STAMP}-seed-cpu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
CONTROL_ROOM_SOURCE_FILE="${CONTROL_ROOM_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_control_room.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B151_INTERNAL_WORKSTREAM_CONTROL_ROOM.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B151_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B151_KNOWN_LIMITS.md}"
VALIDATOR_HTTP_STATUS_EXPECTED="${VALIDATOR_HTTP_STATUS_EXPECTED:-501}"

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

curl_json_capture_status() {
  local method="$1"
  local path="$2"
  local target="$3"
  local status_target="$4"

  local http_code=""
  http_code="$(curl -sS -o "${target}" -w '%{http_code}' -X "${method}" \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${LOCAL_PORT}${path}")"
  printf '%s\n' "${http_code}" > "${status_target}"
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
echo "${EXPECTED_GOVERNANCE_STATE}" > "${OUT}/expected-governance-state.txt"
echo "${EXPECTED_LAST_TRANSITION}" > "${OUT}/expected-last-transition.txt"
echo "${SEED_PROFILE_ID}" > "${OUT}/seed-profile-id.txt"
echo "${SEED_RUN_LABEL}" > "${OUT}/seed-run-label.txt"
echo "${VALIDATOR_HTTP_STATUS_EXPECTED}" > "${OUT}/expected-action-http-status.txt"

CONTROL_ROOM_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "get_workstream_control_room_detail|get_workstream_control_room_status|WorkstreamControlRoomDetailResponse" "${CONTROL_ROOM_SOURCE_FILE}"; then
  CONTROL_ROOM_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/workstreams|workstream_control_room_detail_handler|workstream_control_room_last_result_handler" "${HTTP_SOURCE_FILE}"; then
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
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --argjson control_room_source_present "${CONTROL_ROOM_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_governance_state: $expected_governance_state,
    expected_last_transition: $expected_last_transition,
    control_room_source_present: $control_room_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' \
  > "${OUT}/control-room-source-summary.json"

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
if [[ -z "${SEED_PUBLISHED_RESULT_JOB_ID}" || "${SEED_PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${SEED_PUBLISHED_RESULT_JOB_ID}" > "${OUT}/seed-published-result-job-id.txt"

curl_json GET "/api/darwin/workstreams" "${OUT}/workstreams-list.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}" "${OUT}/workstream-detail.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/recipes" "${OUT}/workstream-recipes.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/status" "${OUT}/workstream-status.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/last-result" "${OUT}/workstream-last-result.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/handoff" "${OUT}/workstream-handoff.json"
curl_json_capture_status POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/hold" "${OUT}/workstream-hold.json" "${OUT}/workstream-hold.http"
curl_json_capture_status POST "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/resume" "${OUT}/workstream-resume.json" "${OUT}/workstream-resume.http"
stop_port_forward

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --arg expected_action_http_status "${VALIDATOR_HTTP_STATUS_EXPECTED}" \
  --arg seed_profile_id "${SEED_PROFILE_ID}" \
  --arg seed_run_label "${SEED_RUN_LABEL}" \
  --slurpfile seed_pilot "${OUT}/seed-pilot.json" \
  --slurpfile list "${OUT}/workstreams-list.json" \
  --slurpfile detail "${OUT}/workstream-detail.json" \
  --slurpfile recipes "${OUT}/workstream-recipes.json" \
  --slurpfile status "${OUT}/workstream-status.json" \
  --slurpfile last_result "${OUT}/workstream-last-result.json" \
  --slurpfile handoff "${OUT}/workstream-handoff.json" \
  --rawfile hold_http "${OUT}/workstream-hold.http" \
  --rawfile resume_http "${OUT}/workstream-resume.http" \
  '{
    status: (
      if (
        ($list[0].workstreams | map(.id) | index($expected_workstream) != null)
        and ($detail[0].registry_entry.id // "") == $expected_workstream
        and ($recipes[0].recipe_count // 0) >= 4
        and ($status[0].governance_state // "") == $expected_governance_state
        and ($status[0].governance_last_transition // "") == $expected_last_transition
        and ($status[0].live_session.workspace_id // "") == $workspace_id
        and ($status[0].live_session.active_dev_plane // "") == $expected_default_dev_plane
        and ($status[0].live_session.fallback_active // false) == false
        and ($last_result[0].last_result_reference.job_id // null) == ($seed_pilot[0].published_result.job_id // null)
        and ($handoff[0].handoff_present // false) == true
        and (($hold_http | gsub("\\s+"; "")) == $expected_action_http_status)
        and (($resume_http | gsub("\\s+"; "")) == $expected_action_http_status)
      ) then "ok" else "unexpected" end
    ),
    workspace_id: $workspace_id,
    expected_workstream: $expected_workstream,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    expected_governance_state: $expected_governance_state,
    expected_last_transition: $expected_last_transition,
    seed_profile_id: $seed_profile_id,
    seed_run_label: $seed_run_label,
    seed_session_id: ($seed_pilot[0].session_id // ""),
    seed_published_result_job_id: ($seed_pilot[0].published_result.job_id // null),
    listed_workstreams: ($list[0].workstreams | map(.id)),
    detail_workstream_id: ($detail[0].registry_entry.id // ""),
    detail_repo: ($detail[0].spec.repo // ""),
    detail_branch: ($detail[0].spec.default_branch // ""),
    detail_scope: ($detail[0].spec.scope // ""),
    recipes_count: ($recipes[0].recipe_count // 0),
    status_session_id: ($status[0].live_session.session_id // ""),
    status_workspace_id: ($status[0].live_session.workspace_id // ""),
    status_active_dev_plane: ($status[0].live_session.active_dev_plane // ""),
    status_fallback_active: ($status[0].live_session.fallback_active // false),
    governance_state: ($status[0].governance_state // ""),
    governance_last_transition: ($status[0].governance_last_transition // ""),
    handoff_present: ($handoff[0].handoff_present // false),
    last_result_job_id: ($last_result[0].last_result_reference.job_id // null),
    hold_http_status: ($hold_http | gsub("\\s+"; "")),
    resume_http_status: ($resume_http | gsub("\\s+"; ""))
  }' \
  > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] internal workstream control room smoke completed"
