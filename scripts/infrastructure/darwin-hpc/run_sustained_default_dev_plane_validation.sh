#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18096}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/sustained-default-dev-plane-validation}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSPACE_ID="${WORKSPACE_ID:-b136-$(date +%m%d%H%M%S)}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
LOOP1_BRIDGE_PROVIDER="${LOOP1_BRIDGE_PROVIDER:-deepseek}"
LOOP1_BRIDGE_MODEL="${LOOP1_BRIDGE_MODEL:-deepseek-chat}"
LOOP1_REQUEST_ID="${LOOP1_REQUEST_ID:-b136-loop1-$(date +%m%d%H%M%S)}"
LOOP2_PROFILE_ID="${LOOP2_PROFILE_ID:-cpu-batch-v1}"
LOOP3_PROFILE_ID="${LOOP3_PROFILE_ID:-gpu-single-v1}"
LOOP2_RUN_LABEL="${LOOP2_RUN_LABEL:-b136-$(date +%m%d%H%M%S)-cpu-batch}"
LOOP3_RUN_LABEL="${LOOP3_RUN_LABEL:-b136-$(date +%m%d%H%M%S)-gpu-single}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_PROMOTION_SCOPE="${EXPECTED_PROMOTION_SCOPE:-beagle-darwin-hpc-general-noninfra}"
EXPECTED_GPU_EXECUTION_NODE="${EXPECTED_GPU_EXECUTION_NODE:-r740-proxmox}"
ENABLE_OPTIONAL_FALLBACK="${ENABLE_OPTIONAL_FALLBACK:-0}"
FALLBACK_REASON="${FALLBACK_REASON:-sustained_validation_optional_vm_fallback}"
RETURN_REASON="${RETURN_REASON:-sustained_validation_return_to_canonical}"

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
echo "${EXPECTED_GPU_EXECUTION_NODE}" > "${OUT}/expected-gpu-execution-node.txt"
echo "${LOOP1_REQUEST_ID}" > "${OUT}/loop1-request-id.txt"
echo "${LOOP2_RUN_LABEL}" > "${OUT}/loop2-run-label.txt"
echo "${LOOP3_RUN_LABEL}" > "${OUT}/loop3-run-label.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-before.json"
stop_port_forward

git -C "${ROOT}" status --short --untracked-files=all > "${OUT}/git-status-before.txt"
git -C "${ROOT}" diff --stat > "${OUT}/git-diff-stat-before.txt" || true
CHANGED_FILE_COUNT="$(awk 'END{print NR+0}' "${OUT}/git-status-before.txt")"
HEAD_BEFORE="$(git -C "${ROOT}" rev-parse HEAD)"

if (( CHANGED_FILE_COUNT < 1 )); then
  echo "[FAIL] B13.6 loop1 requires a real repo-native delta in the working tree" >&2
  exit 1
fi

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

PREDEPLOY_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-before.json")"
POSTDEPLOY_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/bootstrap-after-deploy.json")"

cat > "${OUT}/loop1-bridge-request.json" <<EOF
{
  "request_id": "${LOOP1_REQUEST_ID}",
  "bridge_kind": "cheap_api",
  "bridge_mode": "api_optional",
  "provider": "${LOOP1_BRIDGE_PROVIDER}",
  "model": "${LOOP1_BRIDGE_MODEL}",
  "task_type": "sustained_default_dev_plane_note",
  "payload": {
    "input": "Repo=${EXPECTED_REPO}. Branch=${EXPECTED_BRANCH}. Promotion scope=${EXPECTED_PROMOTION_SCOPE}. The current repo-native working tree contains ${CHANGED_FILE_COUNT} changed paths. Summarize in 3 short bullets why sustained validation should stay cluster-first and keep VM fallback-only."
  },
  "metadata": {
    "source": "run_sustained_default_dev_plane_validation",
    "workspace_id": "${WORKSPACE_ID}",
    "repo": "${EXPECTED_REPO}",
    "branch": "${EXPECTED_BRANCH}",
    "promotion_scope": "${EXPECTED_PROMOTION_SCOPE}"
  }
}
EOF

curl_json POST "/api/darwin/bridge/execute" "${OUT}/loop1-bridge-execute.json" "${OUT}/loop1-bridge-request.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-loop1.json"

${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
  'test -s "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl" && tail -n 40 "${BEAGLE_DATA_DIR}/tool-bridge/tool_bridge_events.jsonl"' \
  > "${OUT}/loop1-bridge-ledger-tail.jsonl"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg git_head_before_build "${HEAD_BEFORE}" \
  --arg image_ref "${IMAGE_REF}" \
  --arg predeploy_session_id "${PREDEPLOY_SESSION_ID}" \
  --arg postdeploy_session_id "${POSTDEPLOY_SESSION_ID}" \
  --argjson changed_file_count "${CHANGED_FILE_COUNT}" \
  --slurpfile bootstrap "${OUT}/bootstrap-after-deploy.json" \
  --slurpfile session "${OUT}/session-after-loop1.json" \
  --slurpfile bridge "${OUT}/loop1-bridge-execute.json" \
  '{
    status: (if (($bridge[0].status // "") == "success") then "ok" else "unexpected" end),
    loop_kind: "repo_native_dev_loop",
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    git_head_before_build: $git_head_before_build,
    changed_file_count: $changed_file_count,
    image_ref: $image_ref,
    predeploy_session_id: $predeploy_session_id,
    postdeploy_session_id: $postdeploy_session_id,
    session_id: ($session[0].session_id // ""),
    active_dev_plane: ($session[0].active_dev_plane // ""),
    fallback_active: ($session[0].fallback_active // false),
    postdeploy_default_dev_plane: ($bootstrap[0].dev_plane_policy.default_dev_plane // ""),
    postdeploy_vm_fallback_role: ($bootstrap[0].dev_plane_policy.vm_fallback_role // ""),
    postdeploy_promotion_scope: ($bootstrap[0].dev_plane_policy.promotion_scope // ""),
    bridge_request_id: ($bridge[0].request_id // ""),
    bridge_provider: ($bridge[0].provider // ""),
    bridge_model: ($bridge[0].model // ""),
    bridge_status: ($bridge[0].status // ""),
    bridge_latency_ms: ($bridge[0].latency_ms // 0),
    last_handoff: ($session[0].last_handoff // "")
  }' > "${OUT}/loop1.json"

curl_json GET "/api/darwin/hpc/control" "${OUT}/control-before-loop2.json"
curl_json GET "/api/darwin/hpc/results?profile_id=${LOOP2_PROFILE_ID}&state=COMPLETED" "${OUT}/results-before-loop2.json"

cat > "${OUT}/loop2-pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${LOOP2_PROFILE_ID}",
  "run_label": "${LOOP2_RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF

curl_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/loop2-pilot.json" "${OUT}/loop2-pilot-request.json"

LOOP2_PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/loop2-pilot.json")"
if [[ -z "${LOOP2_PUBLISHED_RESULT_JOB_ID}" || "${LOOP2_PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] loop2-pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${LOOP2_PUBLISHED_RESULT_JOB_ID}" > "${OUT}/loop2-published-result-job-id.txt"

curl_json GET "/api/darwin/hpc/results/${LOOP2_PUBLISHED_RESULT_JOB_ID}" "${OUT}/loop2-result-after.json"
curl_json GET "/api/darwin/hpc/results/${LOOP2_PUBLISHED_RESULT_JOB_ID}/manifest" "${OUT}/loop2-result-manifest-after.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-loop2.json"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg run_label "${LOOP2_RUN_LABEL}" \
  --slurpfile pilot "${OUT}/loop2-pilot.json" \
  --slurpfile session "${OUT}/session-after-loop2.json" \
  '{
    status: (if (($pilot[0].status // "") == "ok" and ($pilot[0].final_job.state // "") == "COMPLETED") then "ok" else "unexpected" end),
    loop_kind: "single_rich_operator_workflow",
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    session_id: ($session[0].session_id // ""),
    active_dev_plane: ($session[0].active_dev_plane // ""),
    fallback_active: ($session[0].fallback_active // false),
    profile_id: ($pilot[0].submitted_job.profile_id // ""),
    submitted_job_id: ($pilot[0].submitted_job.job_id // null),
    final_job_state: ($pilot[0].final_job.state // ""),
    published_result_job_id: ($pilot[0].published_result.job_id // null),
    workflow_run_label: $run_label,
    task_kind: ($pilot[0].last_successful_task.task_kind // ""),
    last_handoff: ($session[0].last_handoff // "")
  }' > "${OUT}/loop2.json"

curl_json GET "/api/darwin/hpc/control" "${OUT}/control-before-loop3.json"
curl_json GET "/api/darwin/hpc/results?profile_id=${LOOP3_PROFILE_ID}&state=COMPLETED" "${OUT}/results-before-loop3.json"

cat > "${OUT}/loop3-pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${LOOP3_PROFILE_ID}",
  "run_label": "${LOOP3_RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF

curl_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/loop3-pilot.json" "${OUT}/loop3-pilot-request.json"

LOOP3_PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/loop3-pilot.json")"
if [[ -z "${LOOP3_PUBLISHED_RESULT_JOB_ID}" || "${LOOP3_PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] loop3-pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${LOOP3_PUBLISHED_RESULT_JOB_ID}" > "${OUT}/loop3-published-result-job-id.txt"

curl_json GET "/api/darwin/hpc/results/${LOOP3_PUBLISHED_RESULT_JOB_ID}" "${OUT}/loop3-result-after.json"
curl_json GET "/api/darwin/hpc/results/${LOOP3_PUBLISHED_RESULT_JOB_ID}/manifest" "${OUT}/loop3-result-manifest-after.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-before-restart.json"

if [[ "${ENABLE_OPTIONAL_FALLBACK}" == "1" ]]; then
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

  ${KUBECTL} -n "${NAMESPACE}" exec deploy/"${SERVICE_NAME}" -- sh -lc \
    'test -s "${BEAGLE_DATA_DIR}/workspace-plane/fallback_discipline_events.jsonl" && tail -n 40 "${BEAGLE_DATA_DIR}/workspace-plane/fallback_discipline_events.jsonl"' \
    > "${OUT}/fallback-ledger-tail.jsonl"

  jq -nc \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg fallback_reason "${FALLBACK_REASON}" \
    --arg return_reason "${RETURN_REASON}" \
    --slurpfile entered "${OUT}/fallback-enter.json" \
    --slurpfile returned "${OUT}/fallback-return.json" \
    '{
      observed: true,
      workspace_id: $workspace_id,
      fallback_reason: $fallback_reason,
      return_reason: $return_reason,
      entered_active_dev_plane: ($entered[0].active_dev_plane // ""),
      returned_active_dev_plane: ($returned[0].active_dev_plane // ""),
      duration_seconds: ($returned[0].last_fallback_event.duration_seconds // 0)
    }' > "${OUT}/fallback-summary.json"
else
  jq -nc \
    --arg workspace_id "${WORKSPACE_ID}" \
    '{observed: false, workspace_id: $workspace_id}' \
    > "${OUT}/fallback-summary.json"
fi

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-after-loops.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after-restart.txt"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"

AFTER_RESTART_SESSION_ID="$(jq -r '.session_id // empty' "${OUT}/session-after-restart.json")"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_execution_node "${EXPECTED_GPU_EXECUTION_NODE}" \
  --arg session_before_restart "$(jq -r '.session_id // empty' "${OUT}/session-before-restart.json")" \
  --arg session_after_restart "${AFTER_RESTART_SESSION_ID}" \
  --arg run_label "${LOOP3_RUN_LABEL}" \
  --slurpfile pilot "${OUT}/loop3-pilot.json" \
  --slurpfile result "${OUT}/loop3-result-after.json" \
  --slurpfile bootstrap "${OUT}/bootstrap-after-restart.json" \
  --slurpfile session "${OUT}/session-after-restart.json" \
  --slurpfile fallback "${OUT}/fallback-summary.json" \
  '{
    status: (
      if (($pilot[0].status // "") == "ok"
          and ($pilot[0].final_job.state // "") == "COMPLETED"
          and ($session[0].active_dev_plane // "") == $expected_default_dev_plane)
      then "ok" else "unexpected" end
    ),
    loop_kind: "advanced_operator_gpu_workflow",
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    expected_execution_node: $expected_execution_node,
    session_before_restart: $session_before_restart,
    session_after_restart: $session_after_restart,
    restart_preserved_session: ($session_before_restart == $session_after_restart),
    active_dev_plane_after_restart: ($session[0].active_dev_plane // ""),
    fallback_active_after_restart: ($session[0].fallback_active // false),
    profile_id: ($pilot[0].submitted_job.profile_id // ""),
    submitted_job_id: ($pilot[0].submitted_job.job_id // null),
    final_job_state: ($pilot[0].final_job.state // ""),
    final_job_node_list: ($pilot[0].final_job.node_list // ""),
    published_result_job_id: ($pilot[0].published_result.job_id // null),
    resolved_result_job_id: ($pilot[0].resolved_result_lookup.job_id // null),
    resolved_result_node: ($result[0].node_list // ""),
    workflow_run_label: $run_label,
    task_kind: ($pilot[0].last_successful_task.task_kind // ""),
    task_execution_node: ($pilot[0].last_successful_task.execution_node // ""),
    postrestart_default_dev_plane: ($bootstrap[0].dev_plane_policy.default_dev_plane // ""),
    postrestart_vm_fallback_role: ($bootstrap[0].dev_plane_policy.vm_fallback_role // ""),
    postrestart_promotion_scope: ($bootstrap[0].dev_plane_policy.promotion_scope // ""),
    fallback_observed: ($fallback[0].observed // false),
    last_handoff: ($session[0].last_handoff // "")
  }' > "${OUT}/loop3.json"

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
  --slurpfile loop1 "${OUT}/loop1.json" \
  --slurpfile loop2 "${OUT}/loop2.json" \
  --slurpfile loop3 "${OUT}/loop3.json" \
  --slurpfile fallback "${OUT}/fallback-summary.json" \
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
    loop1_status: ($loop1[0].status // ""),
    loop2_status: ($loop2[0].status // ""),
    loop3_status: ($loop3[0].status // ""),
    loop2_profile_id: ($loop2[0].profile_id // ""),
    loop3_profile_id: ($loop3[0].profile_id // ""),
    loop3_expected_execution_node: ($loop3[0].expected_execution_node // ""),
    fallback_observed: ($fallback[0].observed // false)
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] sustained default dev plane validation artifacts written to ${OUT}"
