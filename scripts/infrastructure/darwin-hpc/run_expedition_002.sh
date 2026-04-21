#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
CONTAINER_NAME="${CONTAINER_NAME:-core-server}"
LOCAL_PORT="${LOCAL_PORT:-18174}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/expedition-002-live-execution}"
RUNTIME_DATA="${RUNTIME_DATA:-${OUT}/runtime-data}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
RUST_IMAGE="${RUST_IMAGE:-docker.io/library/rust:1.89-bookworm}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
SESSION_ID="${SESSION_ID:-b174-exp002-${STAMP}}"
EXPERIMENT_ID="${EXPERIMENT_ID:-beagle_exp_002_hrv_aware_vs_blind}"
N_TOTAL="${N_TOTAL:-4}"
INTERVAL_SECS="${INTERVAL_SECS:-1}"
QUESTION_TEMPLATE="${QUESTION_TEMPLATE:-}"

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

if [[ -z "${QUESTION_TEMPLATE}" ]]; then
  QUESTION_TEMPLATE='Expedition 002 run {i}: compare HRV-aware versus blind Beagle synthesis under the same bounded observer envelope.'
fi

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
  for _ in $(seq 1 30); do
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

lookup_condition() {
  local run_id="$1"
  jq -r --arg run_id "${run_id}" 'select(.tag? and .tag.run_id == $run_id) | .tag.condition' "${OUT}/experiment-tags.jsonl" | tail -n 1
}

sync_experiment_tags_to_pod() {
  local pod="$1"
  local data_dir="$2"
  local source="$3"
  if [[ -s "${source}" ]]; then
    ${KUBECTL} -n "${NAMESPACE}" exec -i "${pod}" -c "${CONTAINER_NAME}" -- sh -lc "mkdir -p '${data_dir}/experiments'; cat >> '${data_dir}/experiments/events.jsonl'" < "${source}"
  fi
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

mkdir -p "${OUT}" "${RUNTIME_DATA}/experiments" "${RUNTIME_DATA}/feedback" "${RUNTIME_DATA}/logs/beagle-pipeline" "${OUT}/run-reports"
LOCAL_PORT="$(choose_local_port)"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

jq -nc \
  --arg session_id "${SESSION_ID}" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --argjson n_total "${N_TOTAL}" \
  --arg question_template "${QUESTION_TEMPLATE}" \
  '{
    session_id: $session_id,
    experiment_id: $experiment_id,
    n_total: $n_total,
    question_template: $question_template
  }' > "${OUT}/source-summary.json"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"

cat > "${OUT}/physio-ingest-request.json" <<EOF
{
  "source": "observer-b174",
  "session_id": "${SESSION_ID}",
  "timestamp": "$(date -Iseconds)",
  "hr": 118,
  "hrv_ms": 21,
  "spo2": 94
}
EOF
curl_json POST "/api/observer/physio" "${OUT}/physio-ingest-response.json" "${OUT}/physio-ingest-request.json"
curl_json GET "/api/observer/physio/latest" "${OUT}/physio-latest.json"

podman run --rm --network host \
  -e BEAGLE_OPERATOR_API_TOKEN="${OPERATOR_API_TOKEN}" \
  -e BEAGLE_DATA_DIR=/tmp/beagle-data \
  -v "${ROOT}:/work" \
  -v "${RUNTIME_DATA}:/tmp/beagle-data" \
  -w /work \
  "${RUST_IMAGE}" \
  cargo run -p beagle-experiments --bin run_experiment_hrv_aware_vs_blind -- \
    --experiment-id "${EXPERIMENT_ID}" \
    --n-total "${N_TOTAL}" \
    --batch-label "${SESSION_ID}" \
    --question-template "${QUESTION_TEMPLATE}" \
    --beagle-core-url "http://127.0.0.1:${LOCAL_PORT}" \
    --consumer "beagle-operator" \
    --interval-secs "${INTERVAL_SECS}" > "${OUT}/runner.log" 2>&1

cp "${RUNTIME_DATA}/experiments/events.jsonl" "${OUT}/experiment-tags.jsonl"
jq -r 'select(.tag? != null) | .tag.run_id' "${OUT}/experiment-tags.jsonl" > "${OUT}/run-ids.txt"

if [[ "$(wc -l < "${OUT}/run-ids.txt")" -lt 2 ]]; then
  echo "[FAIL] expedition runner did not produce enough run ids" >&2
  exit 1
fi

POD_NAME="$(resolve_beagle_pod)"
DATA_DIR="$(pod_data_dir "${POD_NAME}")"
FEEDBACK_FILE="${RUNTIME_DATA}/feedback/feedback_events.jsonl"
: > "${FEEDBACK_FILE}"
: > "${OUT}/run-matrix.jsonl"

while read -r RUN_ID; do
  [[ -n "${RUN_ID}" ]] || continue
  CONDITION="$(lookup_condition "${RUN_ID}")"
  if [[ -z "${CONDITION}" ]]; then
    echo "[FAIL] unable to resolve condition for ${RUN_ID}" >&2
    exit 1
  fi

  RUN_REPORT_PATH="$(${KUBECTL} -n "${NAMESPACE}" exec "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "ls -1 ${DATA_DIR}/logs/beagle-pipeline/*_${RUN_ID}.json | tail -n 1")"
  if [[ -z "${RUN_REPORT_PATH}" ]]; then
    echo "[FAIL] unable to resolve run report for ${RUN_ID}" >&2
    exit 1
  fi

  LOCAL_REPORT="${OUT}/run-reports/${CONDITION}_${RUN_ID}.json"
  capture_pod_file "${POD_NAME}" "${RUN_REPORT_PATH}" "${LOCAL_REPORT}"
  cp "${LOCAL_REPORT}" "${RUNTIME_DATA}/logs/beagle-pipeline/$(basename "${RUN_REPORT_PATH}")"

  ${KUBECTL} -n "${NAMESPACE}" exec "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "grep -h '${RUN_ID}' '${DATA_DIR}/feedback/feedback_events.jsonl' || true" >> "${FEEDBACK_FILE}"

  jq -nc \
    --arg run_id "${RUN_ID}" \
    --arg condition "${CONDITION}" \
    --slurpfile report "${LOCAL_REPORT}" \
    '{
      run_id: $run_id,
      condition: $condition,
      experiment: $report[0].experiment,
      experiment_flags: $report[0].experiment_flags,
      pipeline_physio: $report[0].pipeline_physio,
      observer: $report[0].observer,
      llm_stats: $report[0].llm_stats
    }' >> "${OUT}/run-matrix.jsonl"
done < "${OUT}/run-ids.txt"

jq -s '.' "${OUT}/run-matrix.jsonl" > "${OUT}/run-matrix.json"
rm -f "${OUT}/run-matrix.jsonl"
sync_experiment_tags_to_pod "${POD_NAME}" "${DATA_DIR}" "${OUT}/experiment-tags.jsonl"

podman run --rm --network host \
  -e BEAGLE_DATA_DIR=/tmp/beagle-data \
  -v "${ROOT}:/work" \
  -v "${RUNTIME_DATA}:/tmp/beagle-data" \
  -w /work \
  "${RUST_IMAGE}" \
  cargo run -p beagle-experiments --bin analyze_experiments -- "${EXPERIMENT_ID}" > "${OUT}/analysis-terminal.txt" 2>&1

podman run --rm --network host \
  -e BEAGLE_DATA_DIR=/tmp/beagle-data \
  -v "${ROOT}:/work" \
  -v "${RUNTIME_DATA}:/tmp/beagle-data" \
  -v "${OUT}:/artifacts" \
  -w /work \
  "${RUST_IMAGE}" \
  cargo run -p beagle-experiments --bin analyze_experiments -- "${EXPERIMENT_ID}" --output-format json --output-file /artifacts/analysis-summary.json > "${OUT}/analysis-json.log" 2>&1

podman run --rm --network host \
  -e BEAGLE_DATA_DIR=/tmp/beagle-data \
  -v "${ROOT}:/work" \
  -v "${RUNTIME_DATA}:/tmp/beagle-data" \
  -v "${OUT}:/artifacts" \
  -w /work \
  "${RUST_IMAGE}" \
  cargo run -p beagle-experiments --bin analyze_experiments -- "${EXPERIMENT_ID}" --output-format csv --output-file /artifacts/analysis-summary.csv > "${OUT}/analysis-csv.log" 2>&1

jq -nc \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --slurpfile latest "${OUT}/physio-latest.json" \
  --slurpfile analysis "${OUT}/analysis-summary.json" \
  --slurpfile matrix "${OUT}/run-matrix.json" \
  '{
    experiment_id: $experiment_id,
    latest_physio: $latest[0].snapshot,
    total_runs: ($matrix[0] | length),
    hrv_aware_runs: (($matrix[0] | map(select(.condition == "hrv_aware"))) | length),
    hrv_blind_runs: (($matrix[0] | map(select(.condition == "hrv_blind"))) | length),
    conditions: ($analysis[0].conditions // {}),
    bounded_pipeline_physio: (($matrix[0] | map(select(.pipeline_physio.snapshot_available == true))) | length),
    used_in_pipeline_count: (($matrix[0] | map(select(.pipeline_physio.used_in_pipeline == true))) | length)
  }' > "${OUT}/results-summary.json"

capture_cluster_health

jq -nc \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --slurpfile ingest "${OUT}/physio-ingest-response.json" \
  --slurpfile latest "${OUT}/physio-latest.json" \
  --slurpfile analysis "${OUT}/analysis-summary.json" \
  --slurpfile matrix "${OUT}/run-matrix.json" \
  '{
    status: (
      if (
        ($ingest[0].status // "") == "ok"
        and ($latest[0].status // "") == "ok"
        and (($analysis[0].conditions.hrv_aware.n_runs // 0) >= 1)
        and (($analysis[0].conditions.hrv_blind.n_runs // 0) >= 1)
        and ((($matrix[0] | map(select(.condition == "hrv_aware" and .experiment_flags.hrv_aware == true and .pipeline_physio.used_in_pipeline == true and .pipeline_physio.snapshot_available == true))) | length) >= 1)
        and ((($matrix[0] | map(select(.condition == "hrv_blind" and .experiment_flags.hrv_aware == false and .pipeline_physio.used_in_pipeline == false and .pipeline_physio.snapshot_available == true))) | length) >= 1)
        and (($matrix[0] | map(select(.experiment.experiment_id == $experiment_id)) | length) == ($matrix[0] | length))
      ) then "ok" else "unexpected" end
    ),
    experiment_id: $experiment_id,
    total_runs: ($matrix[0] | length),
    hrv_aware_runs: (($matrix[0] | map(select(.condition == "hrv_aware"))) | length),
    hrv_blind_runs: (($matrix[0] | map(select(.condition == "hrv_blind"))) | length),
    physio_snapshot_attached_runs: (($matrix[0] | map(select(.pipeline_physio.snapshot_available == true))) | length),
    used_in_pipeline_count: (($matrix[0] | map(select(.pipeline_physio.used_in_pipeline == true))) | length)
  }' > "${OUT}/smoke.json"

echo "[OK] Expedition 002 live execution completed"
