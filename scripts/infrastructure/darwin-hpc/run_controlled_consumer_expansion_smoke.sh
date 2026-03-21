#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18089}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/controlled-consumer-expansion-smoke}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:?BEAGLE_OPERATOR_API_TOKEN is required}"
RESEARCH_API_TOKEN="${BEAGLE_RESEARCH_API_TOKEN:?BEAGLE_RESEARCH_API_TOKEN is required}"
WORKSPACE_ID="${WORKSPACE_ID:-b97-$(date +%m%d%H%M%S)}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)}"
ALLOWED_PROFILE_ID="${ALLOWED_PROFILE_ID:-cpu-short-v1}"
DENIED_PROFILE_ID="${DENIED_PROFILE_ID:-gpu-single-v1}"
RUN_LABEL="${RUN_LABEL:-b97-$(date +%m%d%H%M%S)-research-consumer}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require jq
require ss
require git

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
    if curl -fsS -H "Authorization: Bearer ${OPERATOR_API_TOKEN}" -H 'X-Beagle-Consumer: beagle-operator' \
      "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
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
  local token="$1"
  local consumer="$2"
  local method="$3"
  local path="$4"
  local target="$5"
  local body="${6:-}"

  if [[ -n "${body}" ]]; then
    curl -fsS -X "${method}" \
      -H "Authorization: Bearer ${token}" \
      -H "X-Beagle-Consumer: ${consumer}" \
      -H 'Content-Type: application/json' \
      --data @"${body}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "Authorization: Bearer ${token}" \
      -H "X-Beagle-Consumer: ${consumer}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  fi
}

curl_capture() {
  local token="$1"
  local consumer="$2"
  local method="$3"
  local path="$4"
  local body="${5:-}"
  local target_base="$6"

  if [[ -n "${body}" ]]; then
    curl -sS -o "${target_base}.json" -w '%{http_code}' -X "${method}" \
      -H "Authorization: Bearer ${token}" \
      -H "X-Beagle-Consumer: ${consumer}" \
      -H 'Content-Type: application/json' \
      --data @"${body}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target_base}.code"
  else
    curl -sS -o "${target_base}.json" -w '%{http_code}' -X "${method}" \
      -H "Authorization: Bearer ${token}" \
      -H "X-Beagle-Consumer: ${consumer}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target_base}.code"
  fi
}

LOCAL_PORT="$(choose_local_port)"
PF_LOG="${OUT}/port-forward.log"

echo "${LOCAL_PORT}" > "${OUT}/selected-port.txt"
echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_REPO}" > "${OUT}/expected-repo.txt"
echo "${EXPECTED_BRANCH}" > "${OUT}/expected-branch.txt"
echo "${ALLOWED_PROFILE_ID}" > "${OUT}/allowed-profile-id.txt"
echo "${DENIED_PROFILE_ID}" > "${OUT}/denied-profile-id.txt"
echo "${RUN_LABEL}" > "${OUT}/run-label.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"

curl_json "${OPERATOR_API_TOKEN}" "beagle-operator" GET "/api/darwin/consumers/self" "${OUT}/operator-self.json"
curl_json "${OPERATOR_API_TOKEN}" "beagle-operator" GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/operator-bootstrap.json"
curl_json "${OPERATOR_API_TOKEN}" "beagle-operator" GET "/api/darwin/hpc/control" "${OUT}/operator-control.json"

curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/consumers/self" "${OUT}/research-self.json"
curl_capture "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/control" "" "${OUT}/research-control-denied"
curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/profiles" "${OUT}/research-profiles.json"

cat > "${OUT}/research-submit-denied-request.json" <<EOF
{
  "profile_id": "${DENIED_PROFILE_ID}",
  "parameters": {
    "run_label": "${RUN_LABEL}-denied"
  }
}
EOF
curl_capture "${RESEARCH_API_TOKEN}" "darwin-research" POST "/api/darwin/hpc/jobs/submit" "${OUT}/research-submit-denied-request.json" "${OUT}/research-submit-denied"

cat > "${OUT}/research-submit-request.json" <<EOF
{
  "profile_id": "${ALLOWED_PROFILE_ID}",
  "parameters": {
    "run_label": "${RUN_LABEL}"
  }
}
EOF
curl_capture "${RESEARCH_API_TOKEN}" "darwin-research" POST "/api/darwin/hpc/jobs/submit" "${OUT}/research-submit-request.json" "${OUT}/research-submit"

RESEARCH_SUBMIT_CODE="$(cat "${OUT}/research-submit.code")"
if [[ "${RESEARCH_SUBMIT_CODE}" != "200" ]]; then
  echo "[FAIL] research submit did not return 200" >&2
  cat "${OUT}/research-submit.json" >&2 || true
  exit 1
fi

JOB_ID="$(jq -r '.job_id' "${OUT}/research-submit.json")"
if [[ -z "${JOB_ID}" || "${JOB_ID}" == "null" ]]; then
  echo "[FAIL] research-submit.json missing job_id" >&2
  exit 1
fi
echo "${JOB_ID}" > "${OUT}/research-job-id.txt"

POLL_STARTED="$(date +%s)"
while true; do
  curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/jobs/${JOB_ID}" "${OUT}/research-status.json"
  JOB_STATE="$(jq -r '.state // "UNKNOWN"' "${OUT}/research-status.json")"

  if [[ "${JOB_STATE}" == "COMPLETED" || "${JOB_STATE}" == "SUCCEEDED" || "${JOB_STATE}" == "SUCCESS" ]]; then
    break
  fi
  if [[ "${JOB_STATE}" == "FAILED" || "${JOB_STATE}" == "CANCELLED" || "${JOB_STATE}" == "TIMEOUT" || "${JOB_STATE}" == "ERROR" ]]; then
    echo "[FAIL] research job entered failure state: ${JOB_STATE}" >&2
    exit 1
  fi
  if (( $(date +%s) - POLL_STARTED >= TIMEOUT_SECONDS )); then
    echo "[FAIL] timed out waiting for research job completion" >&2
    exit 1
  fi
  sleep 5
done

curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/jobs/${JOB_ID}/artifact-manifest" "${OUT}/research-artifact-manifest.json"
curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/jobs/${JOB_ID}/stdout" "${OUT}/research-stdout.json"
curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/jobs/${JOB_ID}/stderr" "${OUT}/research-stderr.json"
curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/results?profile_id=${ALLOWED_PROFILE_ID}&state=COMPLETED" "${OUT}/research-results.json"

PUBLISHED_RESULT_JOB_ID="$(jq -r '.results[0].job_id' "${OUT}/research-results.json")"
if [[ -z "${PUBLISHED_RESULT_JOB_ID}" || "${PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] research-results.json missing published result job id" >&2
  exit 1
fi
echo "${PUBLISHED_RESULT_JOB_ID}" > "${OUT}/published-result-job-id.txt"

curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/results/${PUBLISHED_RESULT_JOB_ID}" "${OUT}/research-result.json"
curl_json "${RESEARCH_API_TOKEN}" "darwin-research" GET "/api/darwin/hpc/results/${PUBLISHED_RESULT_JOB_ID}/manifest" "${OUT}/research-result-manifest.json"

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

echo "[OK] controlled consumer expansion smoke artifacts written to ${OUT}"
