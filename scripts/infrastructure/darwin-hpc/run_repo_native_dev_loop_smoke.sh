#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18091}"
PROFILE_ID="${PROFILE_ID:-cpu-short-v1}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/repo-native-dev-loop-smoke}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSPACE_ID="${WORKSPACE_ID:-b132-$(date +%m%d%H%M%S)}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)}"
RUN_LABEL="${RUN_LABEL:-b132-$(date +%m%d%H%M%S)-repo-native-dev-loop}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
WORKSPACE_CONTRACT_VERSION="${WORKSPACE_CONTRACT_VERSION:-darwin-workspace-plane-v2}"
SOURCE_FILE="${SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"

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
echo "${RUN_LABEL}" > "${OUT}/run-label.txt"
echo "${WORKSPACE_CONTRACT_VERSION}" > "${OUT}/workspace-contract-version.txt"
echo "${IMAGE_REF}" > "${OUT}/image-ref.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"
stop_port_forward

FIELD_PRESENT_IN_SOURCE=0
if rg -q "workspace_plane_contract_version" "${SOURCE_FILE}"; then
  FIELD_PRESENT_IN_SOURCE=1
fi
MATCH_COUNT="$(rg -c "${WORKSPACE_CONTRACT_VERSION}" "${SOURCE_FILE}")"
HEAD_BEFORE="$(git -C "${ROOT}" rev-parse HEAD)"

jq -nc \
  --arg source_file "${SOURCE_FILE}" \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" \
  --arg git_head "${HEAD_BEFORE}" \
  --arg git_branch "${EXPECTED_BRANCH}" \
  --argjson field_present "${FIELD_PRESENT_IN_SOURCE}" \
  --argjson match_count "${MATCH_COUNT}" \
  '{
    source_file: $source_file,
    field_name: "workspace_plane_contract_version",
    expected_contract_version: $expected_contract_version,
    git_head_before_build: $git_head,
    git_branch: $git_branch,
    field_present_in_source: $field_present,
    source_match_count: $match_count
  }' > "${OUT}/patch-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-for-deploy.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward-after-deploy.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-deploy.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-deploy.json"

POSTDEPLOY_CONTRACT_VERSION="$(jq -r '.workspace_plane_contract_version // empty' "${OUT}/bootstrap-after-deploy.json")"
PREDEPLOY_CONTRACT_VERSION="$(jq -r '.workspace_plane_contract_version // empty' "${OUT}/bootstrap-before.json")"

jq -nc \
  --arg image_ref "${IMAGE_REF}" \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" \
  --arg predeploy_contract_version "${PREDEPLOY_CONTRACT_VERSION}" \
  --arg postdeploy_contract_version "${POSTDEPLOY_CONTRACT_VERSION}" \
  '{
    image_ref: $image_ref,
    expected_contract_version: $expected_contract_version,
    predeploy_contract_version: $predeploy_contract_version,
    postdeploy_contract_version: $postdeploy_contract_version,
    postdeploy_contract_version_matches: ($postdeploy_contract_version == $expected_contract_version)
  }' > "${OUT}/deploy.json"

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

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_contract_version "${WORKSPACE_CONTRACT_VERSION}" \
  --arg run_label "${RUN_LABEL}" \
  --slurpfile bootstrap "${OUT}/bootstrap-after-deploy.json" \
  --slurpfile pilot "${OUT}/pilot.json" \
  '{
    workspace_id: $workspace_id,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_contract_version: $expected_contract_version,
    postdeploy_contract_version: ($bootstrap[0].workspace_plane_contract_version // ""),
    submitted_job_id: ($pilot[0].final_job.job_id // null),
    submitted_profile_id: ($pilot[0].final_job.profile_id // null),
    published_result_job_id: ($pilot[0].published_result.job_id // null),
    workflow_run_label: $run_label,
    pilot_status: ($pilot[0].status // "unknown")
  }' > "${OUT}/smoke.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-after-smoke.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after-restart.txt"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" "${OUT}/session-after-restart.json"

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

echo "[OK] repo-native dev loop smoke artifacts written to ${OUT}"
