#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
CONFIGMAP_NAME="${CONFIGMAP_NAME:-beagle-core-config}"
LOCAL_PORT="${LOCAL_PORT:-18098}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/workstream-governance-smoke}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b144-${STAMP}}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
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
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b144-${STAMP}-seed-cpu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
CONFIG_MODEL_FILE="${CONFIG_MODEL_FILE:-${ROOT}/crates/beagle-config/src/model.rs}"
CONFIG_LIB_FILE="${CONFIG_LIB_FILE:-${ROOT}/crates/beagle-config/src/lib.rs}"
WORKSPACE_SOURCE_FILE="${WORKSPACE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
WORKSTREAM_SPEC_FILE="${WORKSTREAM_SPEC_FILE:-${ROOT}/docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml}"
REGISTRY_FILE="${REGISTRY_FILE:-${ROOT}/docs/darwin/hpc/workstreams/registry.yaml}"
CONFIG_FILE="${CONFIG_FILE:-${ROOT}/k8s/beagle/configmap.yaml}"

ORIGINAL_STATE=""
ORIGINAL_LAST_TRANSITION=""
CURRENT_STATE=""
CURRENT_LAST_TRANSITION=""

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require base64
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

record_configmap() {
  local target="$1"
  ${KUBECTL} -n "${NAMESPACE}" get configmap "${CONFIGMAP_NAME}" -o yaml > "${target}"
}

read_configmap_value() {
  local key="$1"
  ${KUBECTL} -n "${NAMESPACE}" get configmap "${CONFIGMAP_NAME}" -o "jsonpath={.data.${key}}" 2>/dev/null || true
}

patch_governance_state() {
  local state="$1"
  local transition="$2"
  local snapshot="$3"
  local patch=""

  patch="$(jq -nc \
    --arg state "${state}" \
    --arg transition "${transition}" \
    '{data: {"BEAGLE_WORKSPACE_CUTOVER_STATE": $state, "BEAGLE_WORKSTREAM_LAST_TRANSITION": $transition}}')"

  ${KUBECTL} -n "${NAMESPACE}" patch configmap "${CONFIGMAP_NAME}" --type merge -p "${patch}" > /dev/null
  record_configmap "${snapshot}"
  CURRENT_STATE="${state}"
  CURRENT_LAST_TRANSITION="${transition}"
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

  if [[ -n "${ORIGINAL_STATE}" ]] && [[ -n "${CURRENT_STATE}" ]]; then
    if [[ "${CURRENT_STATE}" != "${ORIGINAL_STATE}" || "${CURRENT_LAST_TRANSITION}" != "${ORIGINAL_LAST_TRANSITION}" ]]; then
      local patch=""
      patch="$(jq -nc \
        --arg state "${ORIGINAL_STATE}" \
        --arg transition "${ORIGINAL_LAST_TRANSITION}" \
        '{data: {"BEAGLE_WORKSPACE_CUTOVER_STATE": $state, "BEAGLE_WORKSTREAM_LAST_TRANSITION": $transition}}')"
      ${KUBECTL} -n "${NAMESPACE}" patch configmap "${CONFIGMAP_NAME}" --type merge -p "${patch}" > /dev/null 2>&1 || true
      ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > /dev/null 2>&1 || true
      ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > /dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

LOCAL_PORT="$(choose_local_port)"
PF_LOG="${OUT}/port-forward.log"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_REPO}" > "${OUT}/expected-repo.txt"
echo "${EXPECTED_BRANCH}" > "${OUT}/expected-branch.txt"
echo "${EXPECTED_WORKSTREAM}" > "${OUT}/expected-workstream.txt"
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

WORKSPACE_SOURCE_PRESENT=0
CONFIG_MODEL_PRESENT=0
CONFIG_LIB_PRESENT=0
CONFIGMAP_PRESENT=0
WORKSTREAM_SPEC_PRESENT=0
REGISTRY_PRESENT=0

if rg -q "cutover_last_transition|allowed_states|allowed_transitions|WorkspaceWorkstreamGovernanceTransition" "${WORKSPACE_SOURCE_FILE}"; then
  WORKSPACE_SOURCE_PRESENT=1
fi
if rg -q "cutover_last_transition" "${CONFIG_MODEL_FILE}"; then
  CONFIG_MODEL_PRESENT=1
fi
if rg -q "BEAGLE_WORKSTREAM_LAST_TRANSITION|cutover_last_transition" "${CONFIG_LIB_FILE}"; then
  CONFIG_LIB_PRESENT=1
fi
if rg -q "BEAGLE_WORKSTREAM_LAST_TRANSITION" "${CONFIG_FILE}"; then
  CONFIGMAP_PRESENT=1
fi
if rg -q "allowed_states:|allowed_transitions:|last_transition:" "${WORKSTREAM_SPEC_FILE}"; then
  WORKSTREAM_SPEC_PRESENT=1
fi
if rg -q "governance_model|governance_state|governance_last_transition" "${REGISTRY_FILE}"; then
  REGISTRY_PRESENT=1
fi

jq -nc \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_state_before "${EXPECTED_STATE_BEFORE}" \
  --arg expected_last_transition_before "${EXPECTED_LAST_TRANSITION_BEFORE}" \
  --arg held_state "${HELD_STATE}" \
  --arg held_last_transition "${HELD_LAST_TRANSITION}" \
  --arg resumed_state "${RESUMED_STATE}" \
  --arg resumed_last_transition "${RESUMED_LAST_TRANSITION}" \
  --argjson workspace_source_present "${WORKSPACE_SOURCE_PRESENT}" \
  --argjson config_model_present "${CONFIG_MODEL_PRESENT}" \
  --argjson config_lib_present "${CONFIG_LIB_PRESENT}" \
  --argjson configmap_present "${CONFIGMAP_PRESENT}" \
  --argjson workstream_spec_present "${WORKSTREAM_SPEC_PRESENT}" \
  --argjson registry_present "${REGISTRY_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_state_before: $expected_state_before,
    expected_last_transition_before: $expected_last_transition_before,
    held_state: $held_state,
    held_last_transition: $held_last_transition,
    resumed_state: $resumed_state,
    resumed_last_transition: $resumed_last_transition,
    workspace_source_present: $workspace_source_present,
    config_model_present: $config_model_present,
    config_lib_present: $config_lib_present,
    configmap_present: $configmap_present,
    workstream_spec_present: $workstream_spec_present,
    registry_present: $registry_present
  }' \
  > "${OUT}/governance-policy-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_service "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"
record_configmap "${OUT}/configmap-before.yaml"

ORIGINAL_STATE="$(read_configmap_value BEAGLE_WORKSPACE_CUTOVER_STATE)"
ORIGINAL_LAST_TRANSITION="$(read_configmap_value BEAGLE_WORKSTREAM_LAST_TRANSITION)"
ORIGINAL_STATE="${ORIGINAL_STATE:-${EXPECTED_STATE_BEFORE}}"
ORIGINAL_LAST_TRANSITION="${ORIGINAL_LAST_TRANSITION:-${EXPECTED_LAST_TRANSITION_BEFORE}}"
CURRENT_STATE="${ORIGINAL_STATE}"
CURRENT_LAST_TRANSITION="${ORIGINAL_LAST_TRANSITION}"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-before.json"
curl_json GET "/api/darwin/hpc/control" "${OUT}/control-before-seed.json"
curl_json GET "/api/darwin/hpc/results?profile_id=${SEED_PROFILE_ID}&state=COMPLETED" "${OUT}/results-before-seed.json"

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

curl_json GET "/api/darwin/hpc/results/${SEED_PUBLISHED_RESULT_JOB_ID}" "${OUT}/seed-result-after.json"
curl_json GET "/api/darwin/hpc/results/${SEED_PUBLISHED_RESULT_JOB_ID}/manifest" "${OUT}/seed-result-manifest-after.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-seed.json"
stop_port_forward

patch_governance_state "${HELD_STATE}" "${HELD_LAST_TRANSITION}" "${OUT}/configmap-held.yaml"
rollout_service "${OUT}/restart-held.txt" "${OUT}/rollout-held.log"

PF_LOG="${OUT}/port-forward-held.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-held.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-held.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-held.json"
stop_port_forward

patch_governance_state "${RESUMED_STATE}" "${RESUMED_LAST_TRANSITION}" "${OUT}/configmap-resumed.yaml"
rollout_service "${OUT}/restart-resumed.txt" "${OUT}/rollout-resumed.log"

PF_LOG="${OUT}/port-forward-resumed.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-resume.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-resume.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-resume.json"
stop_port_forward

CURRENT_STATE="${ORIGINAL_STATE}"
CURRENT_LAST_TRANSITION="${ORIGINAL_LAST_TRANSITION}"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
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
  --slurpfile bootstrap_before "${OUT}/bootstrap-before.json" \
  --slurpfile session_before "${OUT}/session-before.json" \
  --slurpfile seed_pilot "${OUT}/seed-pilot.json" \
  --slurpfile session_seed "${OUT}/session-after-seed.json" \
  --slurpfile bootstrap_held "${OUT}/bootstrap-held.json" \
  --slurpfile session_held "${OUT}/session-held.json" \
  --slurpfile bootstrap_resumed "${OUT}/bootstrap-after-resume.json" \
  --slurpfile session_resumed "${OUT}/session-after-resume.json" \
  '{
    status: (
      if (
        ($bootstrap_before[0].workstream_cutover_policy.promotion_state.state // "") == $expected_state_before
        and ($bootstrap_before[0].workstream_cutover_policy.promotion_state.last_transition // "") == $expected_last_transition_before
        and ($seed_pilot[0].final_job.state // "") == "COMPLETED"
        and ($bootstrap_held[0].workstream_cutover_policy.promotion_state.state // "") == $held_state
        and ($bootstrap_held[0].workstream_cutover_policy.promotion_state.last_transition // "") == $held_last_transition
        and ($bootstrap_resumed[0].workstream_cutover_policy.promotion_state.state // "") == $resumed_state
        and ($bootstrap_resumed[0].workstream_cutover_policy.promotion_state.last_transition // "") == $resumed_last_transition
      ) then "ok" else "unexpected" end
    ),
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_workstream: $expected_workstream,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_promotion_scope: $expected_promotion_scope,
    seed_profile_id: $seed_profile_id,
    seed_run_label: $seed_run_label,
    seed_session_id: ($session_seed[0].session_id // ""),
    held_session_id: ($session_held[0].session_id // ""),
    resumed_session_id: ($session_resumed[0].session_id // ""),
    same_session_line: (
      ($session_before[0].session_id // "") == ($session_seed[0].session_id // "")
      and ($session_seed[0].session_id // "") == ($session_held[0].session_id // "")
      and ($session_held[0].session_id // "") == ($session_resumed[0].session_id // "")
    ),
    state_before: ($bootstrap_before[0].workstream_cutover_policy.promotion_state.state // ""),
    last_transition_before: ($bootstrap_before[0].workstream_cutover_policy.promotion_state.last_transition // ""),
    held_state: ($bootstrap_held[0].workstream_cutover_policy.promotion_state.state // ""),
    held_last_transition: ($bootstrap_held[0].workstream_cutover_policy.promotion_state.last_transition // ""),
    resumed_state: ($bootstrap_resumed[0].workstream_cutover_policy.promotion_state.state // ""),
    resumed_last_transition: ($bootstrap_resumed[0].workstream_cutover_policy.promotion_state.last_transition // ""),
    seed_final_job_state: ($seed_pilot[0].final_job.state // ""),
    seed_published_result_job_id: ($seed_pilot[0].published_result.job_id // null),
    held_last_handoff: ($session_held[0].last_handoff // ""),
    resumed_last_handoff: ($session_resumed[0].last_handoff // ""),
    held_last_published_result_job_id: ($session_held[0].last_published_result_job_id // null),
    resumed_last_published_result_job_id: ($session_resumed[0].last_published_result_job_id // null),
    last_handoff_preserved_while_held: (($session_seed[0].last_handoff // "") != "" and ($session_held[0].last_handoff // "") == ($session_seed[0].last_handoff // "")),
    last_result_preserved_while_held: (($session_seed[0].last_published_result_job_id // null) == ($session_held[0].last_published_result_job_id // null)),
    last_handoff_preserved_after_resume: (($session_seed[0].last_handoff // "") != "" and ($session_resumed[0].last_handoff // "") == ($session_seed[0].last_handoff // "")),
    last_result_preserved_after_resume: (($session_seed[0].last_published_result_job_id // null) == ($session_resumed[0].last_published_result_job_id // null)),
    active_dev_plane_held: ($session_held[0].active_dev_plane // ""),
    active_dev_plane_after_resume: ($session_resumed[0].active_dev_plane // ""),
    fallback_active_held: ($session_held[0].fallback_active // false),
    fallback_active_after_resume: ($session_resumed[0].fallback_active // false)
  }' \
  > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] workstream governance smoke completed"
