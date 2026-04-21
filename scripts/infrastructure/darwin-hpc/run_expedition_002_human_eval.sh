#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
CONTAINER_NAME="${CONTAINER_NAME:-core-server}"
LOCAL_PORT="${LOCAL_PORT:-18175}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/expedition-002-human-eval}"
RUNTIME_DATA="${RUNTIME_DATA:-${OUT}/runtime-data}"
SOURCE_OUT="${SOURCE_OUT:-${ROOT}/.artifacts/darwin-hpc/expedition-002-live-execution}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
RUST_IMAGE="${RUST_IMAGE:-docker.io/library/rust:1.89-bookworm}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
SESSION_ID="${SESSION_ID:-b175-exp002-human-eval-${STAMP}}"
EXPERIMENT_ID="${EXPERIMENT_ID:-beagle_exp_002_hrv_aware_vs_blind}"
HUMAN_RATINGS_FILE="${HUMAN_RATINGS_FILE:-}"

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
require python3
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

to_work_path() {
  local path="$1"
  printf '/work/%s' "${path#${ROOT}/}"
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

[[ -f "${SOURCE_OUT}/run-ids.txt" ]] || {
  echo "[FAIL] missing canonical Expedition 002 run ids at ${SOURCE_OUT}/run-ids.txt" >&2
  exit 1
}

mkdir -p \
  "${OUT}" \
  "${RUNTIME_DATA}/experiments" \
  "${RUNTIME_DATA}/feedback" \
  "${RUNTIME_DATA}/logs/beagle-pipeline" \
  "${RUNTIME_DATA}/papers/drafts"
cp "${SOURCE_OUT}/run-ids.txt" "${OUT}/run-ids.txt"
if [[ -f "${SOURCE_OUT}/run-matrix.json" ]]; then
  cp "${SOURCE_OUT}/run-matrix.json" "${OUT}/run-matrix.json"
fi

LOCAL_PORT="$(choose_local_port)"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

jq -nc \
  --arg session_id "${SESSION_ID}" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --arg source_out "${SOURCE_OUT}" \
  --arg human_ratings_file "${HUMAN_RATINGS_FILE}" \
  '{
    session_id: $session_id,
    experiment_id: $experiment_id,
    source_out: $source_out,
    human_ratings_file: (if $human_ratings_file == "" then null else $human_ratings_file end)
  }' > "${OUT}/source-summary.json"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health.json"

POD_NAME="$(resolve_beagle_pod)"
DATA_DIR="$(pod_data_dir "${POD_NAME}")"
capture_pod_file "${POD_NAME}" "${DATA_DIR}/experiments/events.jsonl" "${RUNTIME_DATA}/experiments/events.jsonl"

RAW_FEEDBACK="${OUT}/feedback-events.raw.jsonl"
: > "${RAW_FEEDBACK}"

while read -r RUN_ID; do
  [[ -n "${RUN_ID}" ]] || continue

  ${KUBECTL} -n "${NAMESPACE}" exec "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "grep -h '${RUN_ID}' '${DATA_DIR}/feedback/feedback_events.jsonl' || true" >> "${RAW_FEEDBACK}"

  RUN_REPORT_PATH="$(${KUBECTL} -n "${NAMESPACE}" exec "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "ls -1 ${DATA_DIR}/logs/beagle-pipeline/*_${RUN_ID}.json | tail -n 1")"
  [[ -n "${RUN_REPORT_PATH}" ]] || {
    echo "[FAIL] unable to resolve run report for ${RUN_ID}" >&2
    exit 1
  }
  capture_pod_file "${POD_NAME}" "${RUN_REPORT_PATH}" "${RUNTIME_DATA}/logs/beagle-pipeline/$(basename "${RUN_REPORT_PATH}")"
done < "${OUT}/run-ids.txt"

while read -r REMOTE_PATH; do
  [[ -n "${REMOTE_PATH}" ]] || continue
  TARGET="${RUNTIME_DATA}/papers/drafts/$(basename "${REMOTE_PATH}")"
  capture_pod_file "${POD_NAME}" "${REMOTE_PATH}" "${TARGET}"
done < <(jq -r '.event.draft_md // empty' "${RAW_FEEDBACK}" | sort -u)

while read -r REMOTE_PATH; do
  [[ -n "${REMOTE_PATH}" ]] || continue
  TARGET="${RUNTIME_DATA}/papers/drafts/$(basename "${REMOTE_PATH}")"
  if ! capture_pod_file "${POD_NAME}" "${REMOTE_PATH}" "${TARGET}"; then
    rm -f "${TARGET}"
  fi
done < <(jq -r '.event.draft_pdf // empty' "${RAW_FEEDBACK}" | sort -u)

python3 - "${RAW_FEEDBACK}" "${RUNTIME_DATA}/feedback/feedback_events.jsonl" "${RUNTIME_DATA}/papers/drafts" <<'PY'
import json
import pathlib
import sys

raw_path = pathlib.Path(sys.argv[1])
target_path = pathlib.Path(sys.argv[2])
draft_dir = pathlib.Path(sys.argv[3])
container_draft_dir = pathlib.Path("/tmp/beagle-data/papers/drafts")
target_path.parent.mkdir(parents=True, exist_ok=True)

with raw_path.open() as src, target_path.open("w") as dst:
    for line in src:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        event = obj.get("event", {})
        for field in ("draft_md", "draft_pdf"):
            current = event.get(field)
            if current:
                localized = draft_dir / pathlib.Path(current).name
                if localized.exists():
                    event[field] = str(container_draft_dir / localized.name)
        dst.write(json.dumps(obj, ensure_ascii=False) + "\n")
PY

OUT_WORK="$(to_work_path "${OUT}")"
RUN_IDS_WORK="$(to_work_path "${OUT}/run-ids.txt")"

podman run --rm \
  -e BEAGLE_DATA_DIR=/tmp/beagle-data \
  -v "${ROOT}:/work" \
  -v "${RUNTIME_DATA}:/tmp/beagle-data" \
  -w /work \
  "${RUST_IMAGE}" \
  cargo run -p beagle-experiments --bin prepare_expedition_002_human_eval -- \
    --experiment-id "${EXPERIMENT_ID}" \
    --run-ids-file "${RUN_IDS_WORK}" \
    --output-dir "${OUT_WORK}" \
    --packet-id "${SESSION_ID}" > "${OUT}/prepare.log" 2>&1

run_analysis() {
  : > "${OUT}/analysis-terminal.txt"
  podman run --rm \
    -e BEAGLE_DATA_DIR=/tmp/beagle-data \
    -v "${ROOT}:/work" \
    -v "${RUNTIME_DATA}:/tmp/beagle-data" \
    -w /work \
    "${RUST_IMAGE}" \
    cargo run -p beagle-experiments --bin analyze_experiments -- \
      "${EXPERIMENT_ID}" \
      --output-format json \
      --output-file "$(to_work_path "${OUT}/analysis-summary.json")" >> "${OUT}/analysis-terminal.txt" 2>&1

  podman run --rm \
    -e BEAGLE_DATA_DIR=/tmp/beagle-data \
    -v "${ROOT}:/work" \
    -v "${RUNTIME_DATA}:/tmp/beagle-data" \
    -w /work \
    "${RUST_IMAGE}" \
    cargo run -p beagle-experiments --bin analyze_experiments -- \
      "${EXPERIMENT_ID}" \
      --output-format csv \
      --output-file "$(to_work_path "${OUT}/analysis-summary.csv")" >> "${OUT}/analysis-terminal.txt" 2>&1
}

run_analysis

SMOKE_STATUS="ready_for_human_eval"
RATINGS_APPLIED=0

if [[ -n "${HUMAN_RATINGS_FILE}" ]]; then
  [[ -f "${HUMAN_RATINGS_FILE}" ]] || {
    echo "[FAIL] HUMAN_RATINGS_FILE does not exist: ${HUMAN_RATINGS_FILE}" >&2
    exit 1
  }
  cp "${HUMAN_RATINGS_FILE}" "${OUT}/human-ratings.json"

  podman run --rm \
    -e BEAGLE_DATA_DIR=/tmp/beagle-data \
    -v "${ROOT}:/work" \
    -v "${RUNTIME_DATA}:/tmp/beagle-data" \
    -w /work \
    "${RUST_IMAGE}" \
    cargo run -p beagle-experiments --bin apply_expedition_002_human_eval -- \
      --ratings-file "$(to_work_path "${OUT}/human-ratings.json")" \
      --packet-key-file "$(to_work_path "${OUT}/human-eval-key.json")" \
      --appended-events-file "$(to_work_path "${OUT}/appended-human-feedback.json")" > "${OUT}/apply.log" 2>&1

  jq -c '.[] | {event:.}' "${OUT}/appended-human-feedback.json" > "${OUT}/appended-human-feedback.jsonl"
  RATINGS_APPLIED="$(jq 'length' "${OUT}/appended-human-feedback.json")"

  if [[ "${RATINGS_APPLIED}" -gt 0 ]]; then
    ${KUBECTL} -n "${NAMESPACE}" exec -i "${POD_NAME}" -c "${CONTAINER_NAME}" -- sh -lc "cat >> '${DATA_DIR}/feedback/feedback_events.jsonl'" < "${OUT}/appended-human-feedback.jsonl"
    SMOKE_STATUS="ok"
  fi

  run_analysis
fi

capture_cluster_health

jq -nc \
  --arg status "${SMOKE_STATUS}" \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --arg packet_id "${SESSION_ID}" \
  --argjson ratings_applied "${RATINGS_APPLIED}" \
  --argjson items "$(jq '.items | length' "${OUT}/human-eval-packet.json")" \
  '{
    status: $status,
    experiment_id: $experiment_id,
    packet_id: $packet_id,
    items: $items,
    ratings_applied: $ratings_applied
  }' > "${OUT}/smoke.json"

echo "[OK] Expedition 002 human-eval smoke complete: ${SMOKE_STATUS}"
