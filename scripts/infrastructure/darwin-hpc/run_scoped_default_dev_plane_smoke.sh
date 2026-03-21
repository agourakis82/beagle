#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18092}"
PROFILE_ID="${PROFILE_ID:-cpu-short-v1}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/scoped-default-dev-plane-smoke}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:?BEAGLE_OPERATOR_API_TOKEN or BEAGLE_API_TOKEN is required}}"
WORKSPACE_ID="${WORKSPACE_ID:-b133-$(date +%m%d%H%M%S)}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)}"
RUN_LABEL="${RUN_LABEL:-b133-$(date +%m%d%H%M%S)-scoped-default-dev-plane}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
BRIDGE_PROVIDER="${BRIDGE_PROVIDER:-deepseek}"
BRIDGE_MODEL="${BRIDGE_MODEL:-deepseek-chat}"
BRIDGE_REQUEST_ID="${BRIDGE_REQUEST_ID:-b133-default-dev-plane-$(date +%m%d%H%M%S)}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-small-medium}"
SOURCE_FILE="${SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
CONFIG_FILE="${CONFIG_FILE:-${ROOT}/k8s/beagle/configmap.yaml}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
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
echo "${RUN_LABEL}" > "${OUT}/run-label.txt"
echo "${EXPECTED_DEFAULT_DEV_PLANE}" > "${OUT}/expected-default-dev-plane.txt"
echo "${EXPECTED_VM_FALLBACK_ROLE}" > "${OUT}/expected-vm-fallback-role.txt"
echo "${EXPECTED_PROMOTION_SCOPE}" > "${OUT}/expected-promotion-scope.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"
stop_port_forward

SOURCE_POLICY_PRESENT=0
CONFIG_DEFAULT_PRESENT=0
CONFIG_VM_ROLE_PRESENT=0
CONFIG_SCOPE_PRESENT=0

if rg -q "dev_plane_policy|WorkspaceDevPlanePolicy|default_dev_plane" "${SOURCE_FILE}"; then
  SOURCE_POLICY_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_DEFAULT_DEV_PLANE: ${EXPECTED_DEFAULT_DEV_PLANE}" "${CONFIG_FILE}"; then
  CONFIG_DEFAULT_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_VM_FALLBACK_ROLE: ${EXPECTED_VM_FALLBACK_ROLE}" "${CONFIG_FILE}"; then
  CONFIG_VM_ROLE_PRESENT=1
fi
if rg -q "BEAGLE_WORKSPACE_PROMOTION_SCOPE: ${EXPECTED_PROMOTION_SCOPE}" "${CONFIG_FILE}"; then
  CONFIG_SCOPE_PRESENT=1
fi

jq -nc \
  --arg source_file "${SOURCE_FILE}" \
  --arg config_file "${CONFIG_FILE}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --argjson source_policy_present "${SOURCE_POLICY_PRESENT}" \
  --argjson config_default_present "${CONFIG_DEFAULT_PRESENT}" \
  --argjson config_vm_role_present "${CONFIG_VM_ROLE_PRESENT}" \
  --argjson config_scope_present "${CONFIG_SCOPE_PRESENT}" \
  '{
    source_file: $source_file,
    config_file: $config_file,
    policy_field_name: "dev_plane_policy",
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    source_policy_present: $source_policy_present,
    config_default_present: $config_default_present,
    config_vm_role_present: $config_vm_role_present,
    config_scope_present: $config_scope_present
  }' > "${OUT}/policy-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-for-deploy.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward-after-deploy.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-deploy.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-deploy.json"

cat > "${OUT}/bridge-execute-request.json" <<EOF
{
  "request_id": "${BRIDGE_REQUEST_ID}",
  "bridge_kind": "cheap_api",
  "bridge_mode": "api_optional",
  "provider": "${BRIDGE_PROVIDER}",
  "model": "${BRIDGE_MODEL}",
  "task_type": "scoped_default_dev_plane_note",
  "payload": {
    "input": "Repo=${EXPECTED_REPO}. Branch=${EXPECTED_BRANCH}. Default dev plane=${EXPECTED_DEFAULT_DEV_PLANE}. VM role=${EXPECTED_VM_FALLBACK_ROLE}. Summarize this scoped default dev-plane policy for Beagle in 3 short bullets."
  },
  "metadata": {
    "source": "run_scoped_default_dev_plane_smoke",
    "workspace_id": "${WORKSPACE_ID}",
    "repo": "${EXPECTED_REPO}",
    "branch": "${EXPECTED_BRANCH}",
    "promotion_scope": "${EXPECTED_PROMOTION_SCOPE}"
  }
}
EOF

curl_json POST "/api/darwin/bridge/execute" "${OUT}/bridge-execute.json" "${OUT}/bridge-execute-request.json"

${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
  'test -s "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl" && tail -n 40 "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl"' \
  > "${OUT}/bridge-ledger-tail.jsonl"

cat > "${OUT}/pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${PROFILE_ID}",
  "run_label": "${RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF

curl_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/pilot.json" "${OUT}/pilot-request.json"

PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/pilot.json")"
if [[ -z "${PUBLISHED_RESULT_JOB_ID}" || "${PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${PUBLISHED_RESULT_JOB_ID}" > "${OUT}/published-result-job-id.txt"

curl_json GET "/api/darwin/hpc/results/${PUBLISHED_RESULT_JOB_ID}" "${OUT}/result-after.json"
curl_json GET "/api/darwin/hpc/results/${PUBLISHED_RESULT_JOB_ID}/manifest" "${OUT}/result-manifest-after.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-before-restart.json"

PREDEPLOY_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-before.json")"
POSTDEPLOY_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-after-deploy.json")"
POSTDEPLOY_DEFAULT_DEV_PLANE="$(jq -r '.dev_plane_policy.default_dev_plane // empty' "${OUT}/bootstrap-after-deploy.json")"
POSTDEPLOY_VM_FALLBACK_ROLE="$(jq -r '.dev_plane_policy.vm_fallback_role // empty' "${OUT}/bootstrap-after-deploy.json")"
POSTDEPLOY_PROMOTION_SCOPE="$(jq -r '.dev_plane_policy.promotion_scope // empty' "${OUT}/bootstrap-after-deploy.json")"
BRIDGE_STATUS="$(jq -r '.status // empty' "${OUT}/bridge-execute.json")"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-after-smoke.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after-restart.txt"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"

AFTER_RESTART_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/session-after-restart.json")"
SUBMITTED_JOB_ID="$(jq -r '.submitted_job.job_id' "${OUT}/pilot.json")"
PILOT_STATUS="$(jq -r '.status // empty' "${OUT}/pilot.json")"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg predeploy_session_id "${PREDEPLOY_SESSION_ID}" \
  --arg postdeploy_session_id "${POSTDEPLOY_SESSION_ID}" \
  --arg after_restart_session_id "${AFTER_RESTART_SESSION_ID}" \
  --arg postdeploy_default_dev_plane "${POSTDEPLOY_DEFAULT_DEV_PLANE}" \
  --arg postdeploy_vm_fallback_role "${POSTDEPLOY_VM_FALLBACK_ROLE}" \
  --arg postdeploy_promotion_scope "${POSTDEPLOY_PROMOTION_SCOPE}" \
  --arg bridge_provider "${BRIDGE_PROVIDER}" \
  --arg bridge_status "${BRIDGE_STATUS}" \
  --arg workflow_run_label "${RUN_LABEL}" \
  --arg pilot_status "${PILOT_STATUS}" \
  --argjson submitted_job_id "${SUBMITTED_JOB_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" \
  '{
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    predeploy_session_id: $predeploy_session_id,
    postdeploy_session_id: $postdeploy_session_id,
    after_restart_session_id: $after_restart_session_id,
    postdeploy_default_dev_plane: $postdeploy_default_dev_plane,
    postdeploy_vm_fallback_role: $postdeploy_vm_fallback_role,
    postdeploy_promotion_scope: $postdeploy_promotion_scope,
    bridge_provider: $bridge_provider,
    bridge_status: $bridge_status,
    submitted_job_id: $submitted_job_id,
    published_result_job_id: $published_result_job_id,
    workflow_run_label: $workflow_run_label,
    pilot_status: $pilot_status
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

echo "[OK] scoped default dev plane smoke artifacts written to ${OUT}"
