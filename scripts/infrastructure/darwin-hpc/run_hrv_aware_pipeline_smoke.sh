#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
CONTAINER_NAME="${CONTAINER_NAME:-core-server}"
LOCAL_PORT="${LOCAL_PORT:-18131}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/hrv-aware-pipeline}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
SESSION_ID="${SESSION_ID:-b173-physio-${STAMP}}"
EXPERIMENT_ID="${EXPERIMENT_ID:-beagle_exp_002_hrv_aware_vs_blind}"
QUESTION="${QUESTION:-Bound the HRV-aware pipeline using canonical observer state and report the effect on the run metadata.}"

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
  printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
}

KUBECTL="$(resolve_kubectl)"

resolve_operator_api_token() {
  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

choose_local_port() {
  local port="${LOCAL_PORT}"
  local tries=0
  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done
  echo "[FAIL] unable to find free local port" >&2
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
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done
  cat "${pf_log}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

wait_for_health() {
  local port="$1"
  local target="$2"
  for _ in $(seq 1 20); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    sleep 1
  done
  echo "[FAIL] health endpoint did not become ready" >&2
  exit 1
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
      "http://127.0.0.1:${LOCAL_PORT}${path}" > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" > "${target}"
  fi
}

wait_for_run_done() {
  local run_id="$1"
  local target="$2"
  for _ in $(seq 1 120); do
    curl_json GET "/api/pipeline/status/${run_id}" "${target}.tmp"
    local status
    status="$(jq -r 'if (.status | type) == "string" then .status else ( .status | keys_unsorted[0] ) end' "${target}.tmp")"
    if [[ "${status}" == "done" || "${status}" == "triaddone" ]]; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    if [[ "${status}" == "error" ]]; then
      mv "${target}.tmp" "${target}"
      echo "[FAIL] pipeline run entered error state" >&2
      exit 1
    fi
    sleep 2
  done
  echo "[FAIL] pipeline run did not reach done state" >&2
  exit 1
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
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

resolve_beagle_pod() {
  ${KUBECTL} -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=beagle-core -o jsonpath='{.items[0].metadata.name}'
}

pod_data_dir() {
  local pod="$1"
  ${KUBECTL} -n "${NAMESPACE}" exec "${pod}" -c "${CONTAINER_NAME}" -- sh -lc 'if [ -n "${BEAGLE_DATA_DIR:-}" ]; then printf "%s" "${BEAGLE_DATA_DIR}"; else printf "%s/beagle-data" "${HOME:-/root}"; fi'
}

capture_pod_file() {
  local pod="$1"
  local remote_path="$2"
  local target="$3"
  ${KUBECTL} -n "${NAMESPACE}" exec "${pod}" -c "${CONTAINER_NAME}" -- cat "${remote_path}" > "${target}"
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

mkdir -p "${OUT}"
LOCAL_PORT="$(choose_local_port)"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

jq -nc \
  --arg session_id "${SESSION_ID}" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --arg question "${QUESTION}" \
  '{session_id:$session_id,experiment_id:$experiment_id,question:$question}' > "${OUT}/source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1
${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart-for-deploy.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/deploy-rollout.log"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"

cat > "${OUT}/physio-ingest-request.json" <<EOF
{
  "source": "observer-b173",
  "session_id": "${SESSION_ID}",
  "timestamp": "$(date -Iseconds)",
  "hr": 116,
  "hrv_ms": 24,
  "spo2": 93
}
EOF
curl_json POST "/api/observer/physio" "${OUT}/physio-ingest-response.json" "${OUT}/physio-ingest-request.json"
curl_json GET "/api/observer/physio/latest" "${OUT}/physio-latest.json"

cat > "${OUT}/pipeline-start-request.json" <<EOF
{
  "question": "${QUESTION}",
  "with_triad": false,
  "hrv_aware": true,
  "experiment_id": "${EXPERIMENT_ID}"
}
EOF
curl_json POST "/api/pipeline/start" "${OUT}/pipeline-start-response.json" "${OUT}/pipeline-start-request.json"
RUN_ID="$(jq -r '.run_id' "${OUT}/pipeline-start-response.json")"
if [[ -z "${RUN_ID}" || "${RUN_ID}" == "null" ]]; then
  echo "[FAIL] pipeline start did not return run_id" >&2
  exit 1
fi

wait_for_run_done "${RUN_ID}" "${OUT}/pipeline-status.json"
curl_json GET "/api/run/${RUN_ID}/artifacts" "${OUT}/run-artifacts.json"
curl_json GET "/api/observer/context" "${OUT}/observer-context.json"

POD_NAME="$(resolve_beagle_pod)"
DATA_DIR="$(pod_data_dir "${POD_NAME}")"
RUN_REPORT_PATH="$(${KUBECTL} -n "${NAMESPACE}" exec "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "ls -1 ${DATA_DIR}/logs/beagle-pipeline/*_${RUN_ID}.json | tail -n 1")"
if [[ -z "${RUN_REPORT_PATH}" ]]; then
  echo "[FAIL] unable to resolve run report for ${RUN_ID}" >&2
  exit 1
fi
capture_pod_file "${POD_NAME}" "${RUN_REPORT_PATH}" "${OUT}/run-report.json"

FEEDBACK_PATH="${DATA_DIR}/feedback/feedback_events.jsonl"
${KUBECTL} -n "${NAMESPACE}" exec "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "grep -h '${RUN_ID}' '${FEEDBACK_PATH}' | tail -n 1" > "${OUT}/feedback-event.json"

jq '.pipeline_physio' "${OUT}/run-report.json" > "${OUT}/pipeline-physio.json"
jq '.physio_event' "${OUT}/run-report.json" > "${OUT}/physio-event.json"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/final-rollout.log"
capture_cluster_health

jq -nc \
  --arg run_id "${RUN_ID}" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --slurpfile physio "${OUT}/physio-ingest-response.json" \
  --slurpfile latest "${OUT}/physio-latest.json" \
  --slurpfile start "${OUT}/pipeline-start-response.json" \
  --slurpfile status "${OUT}/pipeline-status.json" \
  --slurpfile report "${OUT}/run-report.json" \
  --slurpfile feedback "${OUT}/feedback-event.json" \
  '{
    status: (
      if (
        ($physio[0].status // "") == "ok"
        and ($latest[0].status // "") == "ok"
        and (($start[0].run_id // "") == $run_id)
        and (($status[0].status // "") == "done")
        and ($report[0].pipeline_physio.snapshot_available == true)
        and ($report[0].pipeline_physio.used_in_pipeline == true)
        and ($report[0].experiment_flags.hrv_aware == true)
        and ($report[0].physio_event.recording_mode == "bounded")
        and (($report[0].physio_event.triggers | length) >= 1)
        and ($report[0].experiment.experiment_id == $experiment_id)
        and ($feedback[0].event.experiment_condition == "hrv_aware")
      ) then "ok" else "unexpected" end
    ),
    run_id: $run_id,
    experiment_id: $experiment_id,
    pipeline_physio_present: ($report[0].pipeline_physio.snapshot_available == true),
    hrv_aware_flag: ($report[0].experiment_flags.hrv_aware == true),
    physio_event_recorded: ($report[0].physio_event.recording_mode == "bounded"),
    trigger_count: ($report[0].physio_event.triggers | length)
  }' > "${OUT}/smoke.json"

echo "[OK] hrv-aware pipeline smoke completed"
