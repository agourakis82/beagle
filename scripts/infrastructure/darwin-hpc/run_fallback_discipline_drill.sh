#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18093}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/fallback-discipline-drill}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSPACE_ID="${WORKSPACE_ID:-b134-$(date +%m%d%H%M%S)}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-general-noninfra}"
FALLBACK_REASON="${FALLBACK_REASON:-bounded_vm_fallback_drill}"
RETURN_REASON="${RETURN_REASON:-fallback_window_closed}"
BRIDGE_PROVIDER="${BRIDGE_PROVIDER:-deepseek}"
BRIDGE_MODEL="${BRIDGE_MODEL:-deepseek-chat}"
BRIDGE_REQUEST_ID="${BRIDGE_REQUEST_ID:-b134-fallback-drill-$(date +%m%d%H%M%S)}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
WORKSPACE_SOURCE_FILE="${WORKSPACE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require base64
require git
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

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

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

LOCAL_PORT="$(choose_local_port)"
PF_LOG="${OUT}/port-forward.log"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_REPO}" > "${OUT}/expected-repo.txt"
echo "${EXPECTED_BRANCH}" > "${OUT}/expected-branch.txt"
echo "${EXPECTED_DEFAULT_DEV_PLANE}" > "${OUT}/expected-default-dev-plane.txt"
echo "${EXPECTED_VM_FALLBACK_ROLE}" > "${OUT}/expected-vm-fallback-role.txt"
echo "${EXPECTED_PROMOTION_SCOPE}" > "${OUT}/expected-promotion-scope.txt"
echo "${FALLBACK_REASON}" > "${OUT}/fallback-reason.txt"
echo "${RETURN_REASON}" > "${OUT}/return-reason.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"
stop_port_forward

WORKSPACE_SOURCE_PRESENT=0
HTTP_ROUTE_PRESENT=0
if rg -q "record_workspace_fallback_start|record_workspace_fallback_return|fallback_active|active_dev_plane" "${WORKSPACE_SOURCE_FILE}"; then
  WORKSPACE_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/workspace/fallback/start|/api/darwin/workspace/fallback/return" "${HTTP_SOURCE_FILE}"; then
  HTTP_ROUTE_PRESENT=1
fi

jq -nc \
  --arg workspace_source_file "${WORKSPACE_SOURCE_FILE}" \
  --arg http_source_file "${HTTP_SOURCE_FILE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --argjson workspace_source_present "${WORKSPACE_SOURCE_PRESENT}" \
  --argjson http_route_present "${HTTP_ROUTE_PRESENT}" \
  '{
    workspace_source_file: $workspace_source_file,
    http_source_file: $http_source_file,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    workspace_source_present: $workspace_source_present,
    http_route_present: $http_route_present
  }' > "${OUT}/drill-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-for-deploy.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward-after-deploy.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-deploy.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-deploy.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-deploy.json"

cat > "${OUT}/fallback-start-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "reason": "${FALLBACK_REASON}"
}
EOF

curl_json POST "/api/darwin/workspace/fallback/start" "${OUT}/fallback-enter.json" "${OUT}/fallback-start-request.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-during-fallback.json"

sleep 2

cat > "${OUT}/fallback-return-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "reason": "${RETURN_REASON}"
}
EOF

curl_json POST "/api/darwin/workspace/fallback/return" "${OUT}/fallback-return.json" "${OUT}/fallback-return-request.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-return.json"
curl_json GET "/api/darwin/hpc/control" "${OUT}/control-after-return.json"
curl_json GET "/api/darwin/hpc/results?profile_id=cpu-short-v1&state=COMPLETED" "${OUT}/results-after-return.json"

cat > "${OUT}/bridge-execute-request.json" <<EOF
{
  "request_id": "${BRIDGE_REQUEST_ID}",
  "bridge_kind": "cheap_api",
  "bridge_mode": "api_optional",
  "provider": "${BRIDGE_PROVIDER}",
  "model": "${BRIDGE_MODEL}",
  "task_type": "fallback_discipline_note",
  "payload": {
    "input": "Repo=${EXPECTED_REPO}. Branch=${EXPECTED_BRANCH}. Default plane=${EXPECTED_DEFAULT_DEV_PLANE}. VM role=${EXPECTED_VM_FALLBACK_ROLE}. Summarize why fallback should stay explicit and bounded in 3 short bullets."
  },
  "metadata": {
    "source": "run_fallback_discipline_drill",
    "workspace_id": "${WORKSPACE_ID}",
    "repo": "${EXPECTED_REPO}",
    "branch": "${EXPECTED_BRANCH}",
    "promotion_scope": "${EXPECTED_PROMOTION_SCOPE}"
  }
}
EOF

curl_json POST "/api/darwin/bridge/execute" "${OUT}/bridge-execute.json" "${OUT}/bridge-execute-request.json"

${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
  'test -s "${BEAGLE_DATA_DIR}/workspace-plane/fallback_discipline_events.jsonl" && tail -n 40 "${BEAGLE_DATA_DIR}/workspace-plane/fallback_discipline_events.jsonl"' \
  > "${OUT}/fallback-ledger-tail.jsonl"

PREDEPLOY_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-before.json")"
POSTDEPLOY_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-after-deploy.json")"
AFTER_RETURN_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/session-after-return.json")"
BRIDGE_STATUS="$(jq -r '.status // empty' "${OUT}/bridge-execute.json")"
RETURN_DURATION_SECONDS="$(jq -r '.last_fallback_event.duration_seconds // 0' "${OUT}/fallback-return.json")"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-after-drill.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after-restart.txt"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"

AFTER_RESTART_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/session-after-restart.json")"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg fallback_reason "${FALLBACK_REASON}" \
  --arg return_reason "${RETURN_REASON}" \
  --arg predeploy_session_id "${PREDEPLOY_SESSION_ID}" \
  --arg postdeploy_session_id "${POSTDEPLOY_SESSION_ID}" \
  --arg after_return_session_id "${AFTER_RETURN_SESSION_ID}" \
  --arg after_restart_session_id "${AFTER_RESTART_SESSION_ID}" \
  --arg bridge_status "${BRIDGE_STATUS}" \
  --arg bridge_provider "${BRIDGE_PROVIDER}" \
  --argjson return_duration_seconds "${RETURN_DURATION_SECONDS}" \
  '{
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    fallback_reason: $fallback_reason,
    return_reason: $return_reason,
    predeploy_session_id: $predeploy_session_id,
    postdeploy_session_id: $postdeploy_session_id,
    after_return_session_id: $after_return_session_id,
    after_restart_session_id: $after_restart_session_id,
    bridge_status: $bridge_status,
    bridge_provider: $bridge_provider,
    return_duration_seconds: $return_duration_seconds
  }' > "${OUT}/smoke.json"

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

echo "[OK] fallback discipline drill artifacts written to ${OUT}"
