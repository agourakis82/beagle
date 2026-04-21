#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/study-continuation}"
PROOF_OUT="${PROOF_OUT:-${OUT}/container-proof}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18550}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B266_BASE_OUT="${B266_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/baseline-adoption}"

STUDY_CONTINUATION_SOURCE_FILE="${STUDY_CONTINUATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_continuation.rs}"
NEXT_STUDY_SEED_SOURCE_FILE="${NEXT_STUDY_SEED_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/next_study_seed.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B271_STUDY_CONTINUATION_FROM_BOUNDED_BASELINE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B271_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B271_KNOWN_LIMITS.md}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require base64
require curl
require jq
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
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
    return 0
  fi
  printf '%s\n' kubectl
}

resolve_operator_api_token() {
  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token in secret ${SECRET_NAME}" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

choose_local_port() {
  local port="$1"
  local tries=0
  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done
  echo "[FAIL] unable to find a free local port starting at $1" >&2
  exit 1
}

start_port_forward() {
  local port="$1"
  local log_file="$2"
  : > "${log_file}"
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${port}:8080" >"${log_file}" 2>&1 &
  PF_PID=$!
  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${log_file}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${log_file}" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${log_file}" >&2 || true
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
  local ready=0
  for _ in $(seq 1 30); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != "1" ]]; then
    echo "[FAIL] Beagle health endpoint did not become ready on port ${port}" >&2
    exit 1
  fi
}

fetch_json() {
  local port="$1"
  local path="$2"
  local output="$3"
  curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${port}${path}" \
    > "${output}"
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -l app.kubernetes.io/part-of=beagle -o wide || true
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

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}" "${PROOF_OUT}"

SOURCE_SUMMARY="${OUT}/source-summary.json"
B266_BASE_SMOKE="${B266_BASE_OUT}/smoke.json"

SOURCE_STUDY_CONTINUATION_PRESENT=0
SOURCE_NEXT_SEED_PRESENT=0
SOURCE_HTTP_PRESENT=0
SOURCE_LIB_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
B266_BASE_PRESENT=0

if rg -q "StudyContinuationState|study_continuation_state|read_study_continuation_state" "${STUDY_CONTINUATION_SOURCE_FILE}"; then
  SOURCE_STUDY_CONTINUATION_PRESENT=1
fi
if rg -q "NextStudySeed|build_next_study_seed" "${NEXT_STUDY_SEED_SOURCE_FILE}"; then
  SOURCE_NEXT_SEED_PRESENT=1
fi
if rg -q "study-continuation|workstream_study_continuation_handler" "${HTTP_SOURCE_FILE}"; then
  SOURCE_HTTP_PRESENT=1
fi
if rg -q "pub mod study_continuation" "${LIB_SOURCE_FILE}"; then
  SOURCE_LIB_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${B266_BASE_SMOKE}" ]] && B266_BASE_PRESENT=1

jq -n \
  --argjson study_cont "${SOURCE_STUDY_CONTINUATION_PRESENT}" \
  --argjson next_seed "${SOURCE_NEXT_SEED_PRESENT}" \
  --argjson http_present "${SOURCE_HTTP_PRESENT}" \
  --argjson lib_present "${SOURCE_LIB_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson b266_base_present "${B266_BASE_PRESENT}" \
  '{
    source_study_continuation_present: $study_cont,
    source_next_study_seed_present: $next_seed,
    source_http_present: $http_present,
    source_lib_present: $lib_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    b266_base_present: $b266_base_present
  }' > "${SOURCE_SUMMARY}"

[[ "${SOURCE_STUDY_CONTINUATION_PRESENT}" == "1" ]] || { echo "[FAIL] study continuation source missing" >&2; exit 1; }
[[ "${SOURCE_NEXT_SEED_PRESENT}" == "1" ]] || { echo "[FAIL] next study seed source missing" >&2; exit 1; }
[[ "${SOURCE_HTTP_PRESENT}" == "1" ]] || { echo "[FAIL] http source missing (study-continuation endpoint)" >&2; exit 1; }
[[ "${SOURCE_LIB_PRESENT}" == "1" ]] || { echo "[FAIL] lib source missing" >&2; exit 1; }
[[ "${DOC_PRESENT}" == "1" ]] || { echo "[FAIL] doc missing" >&2; exit 1; }
[[ "${GO_NO_GO_PRESENT}" == "1" ]] || { echo "[FAIL] go/no-go missing" >&2; exit 1; }
[[ "${KNOWN_LIMITS_PRESENT}" == "1" ]] || { echo "[FAIL] known limits missing" >&2; exit 1; }
[[ "${B266_BASE_PRESENT}" == "1" ]] || { echo "[FAIL] B26.6 baseline smoke missing (run baseline-adoption smoke first)" >&2; exit 1; }

AUTH_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${AUTH_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

# B27.1 endpoints
FETCH_CONTINUATION="/api/darwin/workstreams/${WORKSTREAM_ID}/study-continuation"
FETCH_NEXT_SEED="/api/darwin/workstreams/${WORKSTREAM_ID}/next-study-seed"
FETCH_CONTEXT="/api/darwin/workstreams/${WORKSTREAM_ID}/context-packet"

CONTINUATION_FILE="${OUT}/study-continuation-state.json"
NEXT_SEED_FILE="${OUT}/next-study-seed.json"
CONTEXT_FILE="${OUT}/context-packet.json"

# Fetch study continuation state (B27.1 endpoint)
fetch_json "${LOCAL_PORT}" "${FETCH_CONTINUATION}" "${CONTINUATION_FILE}"

# Also fetch next-study-seed and context for cross-validation
fetch_json "${LOCAL_PORT}" "${FETCH_NEXT_SEED}" "${NEXT_SEED_FILE}"
fetch_json "${LOCAL_PORT}" "${FETCH_CONTEXT}" "${CONTEXT_FILE}"

# Generate smoke report
jq -n \
  --argjson continuation "$(jq -c '.' "${CONTINUATION_FILE}")" \
  --argjson seed "$(jq -c '.' "${NEXT_SEED_FILE}")" \
  --argjson ctx "$(jq -c '.' "${CONTEXT_FILE}")" \
  --argjson b266 "$(jq -c '.' "${B266_BASE_SMOKE}")" \
  '{
    status: "ok",
    phase: "B27.1",
    study_id: $continuation.study_id,
    workstream_id: $continuation.workstream_id,
    workspace_id: $continuation.workspace_id,
    session_id: $continuation.session_id,
    same_beagle_owned_identity: $continuation.same_beagle_owned_identity,
    continuation_state_id: $continuation.continuation_state_id,
    previous_run_count: $continuation.previous_run_count,
    updated_run_count: $continuation.updated_run_count,
    next_study_auto_launch: $seed.auto_launch_new_study,
    seed_ready_for_continuation: ($seed.seed_id != null and $seed.seed_id != ""),
    bounded_baseline_on_context: ($ctx.packet.bounded_study_baseline != null),
    b266_baseline_preserved: (
      $b266.study_id == $continuation.study_id and
      $b266.workspace_id == $continuation.workspace_id and
      $b266.session_id == $continuation.session_id
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] study continuation (B27.1) smoke artifacts captured"
echo "  - continuation state: ${CONTINUATION_FILE}"
echo "  - smoke report: ${OUT}/smoke.json"
