#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-kubectl}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18083}"
PROFILE_ID="${PROFILE_ID:-cpu-short-v1}"
RUN_LABEL_PREFIX="${RUN_LABEL_PREFIX:-b123}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/internal-control-surface-smoke}"
API_TOKEN="${BEAGLE_API_TOKEN:?BEAGLE_API_TOKEN is required}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-5}"
POLL_TIMEOUT_SECONDS="${POLL_TIMEOUT_SECONDS:-180}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require date
require jq
require ss
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

LOCAL_PORT="$(choose_local_port)"
echo "${LOCAL_PORT}" > "${OUT}/selected-port.txt"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout.txt"

PF_LOG="${OUT}/port-forward.log"
${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${LOCAL_PORT}:8080" >"${PF_LOG}" 2>&1 &
PF_PID=$!

cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"

ready=0
for _ in $(seq 1 20); do
  if curl -fsS -H "${AUTH_HEADER}" \
    "http://127.0.0.1:${LOCAL_PORT}/health" \
    > "${OUT}/beagle-health.json.tmp"; then
    mv "${OUT}/beagle-health.json.tmp" "${OUT}/beagle-health.json"
    ready=1
    break
  fi
  if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
    echo "[FAIL] port-forward exited before Beagle health became ready" >&2
    cat "${PF_LOG}" >&2 || true
    exit 1
  fi
  sleep 1
done

if [[ "${ready}" != "1" ]]; then
  echo "[FAIL] Beagle health endpoint did not become ready on local port ${LOCAL_PORT}" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
fi

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/control" \
  > "${OUT}/control.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/profiles" \
  > "${OUT}/profiles.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/results" \
  > "${OUT}/results.json"

PUBLISHED_JOB_ID="$(jq -r '.results[0].job_id // empty' "${OUT}/results.json")"
PUBLISHED_RUN_LABEL="$(jq -r '.results[0].run_label // empty' "${OUT}/results.json")"

if [[ -z "${PUBLISHED_JOB_ID}" || -z "${PUBLISHED_RUN_LABEL}" ]]; then
  echo "[FAIL] results catalog does not expose at least one published result" >&2
  exit 1
fi

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/health" \
  > "${OUT}/bridge-health.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/providers" \
  > "${OUT}/bridge-providers.json"

cat > "${OUT}/bridge-execute-human-request.json" <<'EOF'
{
  "request_id": "b123-human-smoke",
  "bridge_kind": "human_premium",
  "bridge_mode": "human_session",
  "provider": "codex_human",
  "task_type": "control_surface_smoke",
  "payload": {
    "input": "Record a B12.3 human-session bridge request without executing it."
  },
  "metadata": {
    "source": "run_internal_control_surface_smoke"
  }
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/bridge-execute-human-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/bridge/execute" \
  > "${OUT}/bridge-execute-human.json"

RUN_LABEL="${RUN_LABEL_PREFIX}-$(date +%m%d%H%M%S)"
cat > "${OUT}/submit-request.json" <<EOF
{
  "profile_id": "${PROFILE_ID}",
  "parameters": {
    "run_label": "${RUN_LABEL}"
  }
}
EOF

curl -fsS -H "${AUTH_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/submit-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/jobs/submit" \
  > "${OUT}/submit.json"

JOB_ID="$(jq -r '.job_id' "${OUT}/submit.json")"
if [[ -z "${JOB_ID}" || "${JOB_ID}" == "null" ]]; then
  echo "[FAIL] submit response missing job_id" >&2
  exit 1
fi

started_at="$(date +%s)"
while true; do
  curl -fsS -H "${AUTH_HEADER}" \
    "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/jobs/${JOB_ID}" \
    > "${OUT}/job-status.json"

  JOB_STATE="$(jq -r '.state // empty' "${OUT}/job-status.json")"
  if [[ "${JOB_STATE}" =~ ^(COMPLETED|SUCCEEDED|SUCCESS)$ ]]; then
    break
  fi

  if [[ "${JOB_STATE}" =~ ^(FAILED|CANCELLED|TIMEOUT|ERROR)$ ]]; then
    echo "[FAIL] job entered failure state: ${JOB_STATE}" >&2
    exit 1
  fi

  if (( $(date +%s) - started_at >= POLL_TIMEOUT_SECONDS )); then
    echo "[FAIL] timed out waiting for terminal job state" >&2
    exit 1
  fi

  sleep "${POLL_INTERVAL_SECONDS}"
done

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/jobs/${JOB_ID}/artifact-manifest" \
  > "${OUT}/job-artifact-manifest.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/results/${PUBLISHED_JOB_ID}" \
  > "${OUT}/published-result.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/results/${PUBLISHED_JOB_ID}/manifest" \
  > "${OUT}/published-result-manifest.json"

curl -fsS -H "${AUTH_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/hpc/results?run_label=${PUBLISHED_RUN_LABEL}" \
  > "${OUT}/results-by-run-label.json"

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

echo "[OK] internal control surface smoke artifacts written to ${OUT}"
