#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/baseline-adoption}"
PROOF_OUT="${PROOF_OUT:-${OUT}/container-proof}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18540}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B265_BASE_OUT="${B265_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/study-promotion-execution}"

BASELINE_ADOPTION_SOURCE_FILE="${BASELINE_ADOPTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/baseline_adoption.rs}"
NEXT_STUDY_SEED_SOURCE_FILE="${NEXT_STUDY_SEED_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/next_study_seed.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
INTENT_PLANNER_SOURCE_FILE="${INTENT_PLANNER_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/intent_planner.rs}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B266_PROMOTED_VARIANT_ADOPTION_BASELINE_ASSIMILATION.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B266_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B266_KNOWN_LIMITS.md}"
RECEIPT_SCHEMA_FILE="${RECEIPT_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/promoted-variant-receipt-schema.yaml}"
ADOPTION_SCHEMA_FILE="${ADOPTION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/baseline-adoption-schema.yaml}"
ROLLBACK_SCHEMA_FILE="${ROLLBACK_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/baseline-rollback-schema.yaml}"
SEED_SCHEMA_FILE="${SEED_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/next-study-seed-schema.yaml}"
WORKBENCH_CTX_SCHEMA_FILE="${WORKBENCH_CTX_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/workbench-context-after-baseline-schema.yaml}"

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
require podman
require ctr

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
BASELINE_B265_SMOKE="${B265_BASE_OUT}/smoke.json"

SOURCE_BASELINE_ADOPTION_PRESENT=0
SOURCE_NEXT_SEED_PRESENT=0
SOURCE_LIB_PRESENT=0
SOURCE_HTTP_PRESENT=0
SOURCE_CONTEXT_PACKET_PRESENT=0
SOURCE_INTENT_PLANNER_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
SCHEMA_RECEIPT_PRESENT=0
SCHEMA_ADOPTION_PRESENT=0
SCHEMA_ROLLBACK_PRESENT=0
SCHEMA_SEED_PRESENT=0
SCHEMA_WORKBENCH_CTX_PRESENT=0
B265_BASE_PRESENT=0

if rg -q "ensure_baseline_adoption|BaselineAdoptionBundle|baseline-adoption" "${BASELINE_ADOPTION_SOURCE_FILE}"; then
  SOURCE_BASELINE_ADOPTION_PRESENT=1
fi
if rg -q "NextStudySeed|build_next_study_seed|next-study-seed" "${NEXT_STUDY_SEED_SOURCE_FILE}"; then
  SOURCE_NEXT_SEED_PRESENT=1
fi
if rg -q "pub mod baseline_adoption|bounded_study_baseline_summary_from_plane" "${LIB_SOURCE_FILE}"; then
  SOURCE_LIB_PRESENT=1
fi
if rg -q "baseline-adoption|workstream_baseline_adoption_handler" "${HTTP_SOURCE_FILE}"; then
  SOURCE_HTTP_PRESENT=1
fi
if rg -q "BoundedStudyBaselineSummary|bounded_study_baseline" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  SOURCE_CONTEXT_PACKET_PRESENT=1
fi
if rg -q "bounded_study_baseline|B26.6 bounded baseline" "${INTENT_PLANNER_SOURCE_FILE}"; then
  SOURCE_INTENT_PLANNER_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${RECEIPT_SCHEMA_FILE}" ]] && SCHEMA_RECEIPT_PRESENT=1
[[ -f "${ADOPTION_SCHEMA_FILE}" ]] && SCHEMA_ADOPTION_PRESENT=1
[[ -f "${ROLLBACK_SCHEMA_FILE}" ]] && SCHEMA_ROLLBACK_PRESENT=1
[[ -f "${SEED_SCHEMA_FILE}" ]] && SCHEMA_SEED_PRESENT=1
[[ -f "${WORKBENCH_CTX_SCHEMA_FILE}" ]] && SCHEMA_WORKBENCH_CTX_PRESENT=1
[[ -f "${BASELINE_B265_SMOKE}" ]] && B265_BASE_PRESENT=1

jq -n \
  --argjson baseline_adoption "${SOURCE_BASELINE_ADOPTION_PRESENT}" \
  --argjson next_seed "${SOURCE_NEXT_SEED_PRESENT}" \
  --argjson lib_present "${SOURCE_LIB_PRESENT}" \
  --argjson http_present "${SOURCE_HTTP_PRESENT}" \
  --argjson context_packet "${SOURCE_CONTEXT_PACKET_PRESENT}" \
  --argjson intent_planner "${SOURCE_INTENT_PLANNER_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson schema_receipt "${SCHEMA_RECEIPT_PRESENT}" \
  --argjson schema_adoption "${SCHEMA_ADOPTION_PRESENT}" \
  --argjson schema_rollback "${SCHEMA_ROLLBACK_PRESENT}" \
  --argjson schema_seed "${SCHEMA_SEED_PRESENT}" \
  --argjson schema_workbench "${SCHEMA_WORKBENCH_CTX_PRESENT}" \
  --argjson b265_base_present "${B265_BASE_PRESENT}" \
  '{
    source_baseline_adoption_present: $baseline_adoption,
    source_next_study_seed_present: $next_seed,
    source_lib_present: $lib_present,
    source_http_present: $http_present,
    source_context_packet_present: $context_packet,
    source_intent_planner_present: $intent_planner,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    schema_receipt_present: $schema_receipt,
    schema_adoption_present: $schema_adoption,
    schema_rollback_present: $schema_rollback,
    schema_seed_present: $schema_seed,
    schema_workbench_context_present: $schema_workbench,
    b265_base_present: $b265_base_present
  }' > "${SOURCE_SUMMARY}"

[[ "${SOURCE_BASELINE_ADOPTION_PRESENT}" == "1" ]] || { echo "[FAIL] baseline adoption source missing" >&2; exit 1; }
[[ "${SOURCE_NEXT_SEED_PRESENT}" == "1" ]] || { echo "[FAIL] next study seed source missing" >&2; exit 1; }
[[ "${SOURCE_LIB_PRESENT}" == "1" ]] || { echo "[FAIL] lib source missing" >&2; exit 1; }
[[ "${SOURCE_HTTP_PRESENT}" == "1" ]] || { echo "[FAIL] http source missing" >&2; exit 1; }
[[ "${SOURCE_CONTEXT_PACKET_PRESENT}" == "1" ]] || { echo "[FAIL] context packet source missing" >&2; exit 1; }
[[ "${SOURCE_INTENT_PLANNER_PRESENT}" == "1" ]] || { echo "[FAIL] intent planner source missing" >&2; exit 1; }
[[ "${DOC_PRESENT}" == "1" ]] || { echo "[FAIL] doc missing" >&2; exit 1; }
[[ "${GO_NO_GO_PRESENT}" == "1" ]] || { echo "[FAIL] go/no-go missing" >&2; exit 1; }
[[ "${KNOWN_LIMITS_PRESENT}" == "1" ]] || { echo "[FAIL] known limits missing" >&2; exit 1; }
[[ "${SCHEMA_RECEIPT_PRESENT}" == "1" ]] || { echo "[FAIL] receipt schema missing" >&2; exit 1; }
[[ "${SCHEMA_ADOPTION_PRESENT}" == "1" ]] || { echo "[FAIL] adoption schema missing" >&2; exit 1; }
[[ "${SCHEMA_ROLLBACK_PRESENT}" == "1" ]] || { echo "[FAIL] rollback schema missing" >&2; exit 1; }
[[ "${SCHEMA_SEED_PRESENT}" == "1" ]] || { echo "[FAIL] seed schema missing" >&2; exit 1; }
[[ "${SCHEMA_WORKBENCH_CTX_PRESENT}" == "1" ]] || { echo "[FAIL] workbench context schema missing" >&2; exit 1; }
[[ "${B265_BASE_PRESENT}" == "1" ]] || { echo "[FAIL] B26.5 baseline smoke missing (run study promotion smoke first)" >&2; exit 1; }

AUTH_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${AUTH_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

FETCH_BASELINE="/api/darwin/workstreams/${WORKSTREAM_ID}/baseline-adoption"
FETCH_CONTEXT="/api/darwin/workstreams/${WORKSTREAM_ID}/context-packet"
BUNDLE_BEFORE="${OUT}/baseline-adoption-bundle-before.json"
BUNDLE_AFTER="${PROOF_OUT}/baseline-adoption-bundle-after-restart.json"
CONTEXT_BEFORE="${OUT}/context-packet-before.json"

fetch_json "${LOCAL_PORT}" "${FETCH_BASELINE}" "${BUNDLE_BEFORE}"
fetch_json "${LOCAL_PORT}" "${FETCH_CONTEXT}" "${CONTEXT_BEFORE}"

jq '.promoted_variant_receipt' "${BUNDLE_BEFORE}" > "${OUT}/promoted-variant-receipt.json"
jq '.baseline_adoption' "${BUNDLE_BEFORE}" > "${OUT}/baseline-adoption.json"
jq '.baseline_rollback_plan' "${BUNDLE_BEFORE}" > "${OUT}/baseline-rollback-plan.json"
jq '.next_study_seed' "${BUNDLE_BEFORE}" > "${OUT}/next-study-seed.json"
jq '.workbench_context_after_baseline' "${BUNDLE_BEFORE}" > "${OUT}/workbench-context-after-baseline.json"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" >/dev/null
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s >/dev/null
sleep 2

fetch_json "${LOCAL_PORT}" "${FETCH_BASELINE}" "${BUNDLE_AFTER}"

jq '.promoted_variant_receipt' "${BUNDLE_AFTER}" > "${PROOF_OUT}/promoted-variant-receipt-after-restart.json"
jq '.baseline_adoption' "${BUNDLE_AFTER}" > "${PROOF_OUT}/baseline-adoption-after-restart.json"
jq '.next_study_seed' "${BUNDLE_AFTER}" > "${PROOF_OUT}/next-study-seed-after-restart.json"

jq -n \
  --argjson before "$(jq -c '.' "${BUNDLE_BEFORE}")" \
  --argjson after "$(jq -c '.' "${BUNDLE_AFTER}")" \
  --argjson ctx "$(jq -c '.' "${CONTEXT_BEFORE}")" \
  --argjson adoption "$(jq -c '.baseline_adoption' "${BUNDLE_BEFORE}")" \
  --argjson seed "$(jq -c '.next_study_seed' "${BUNDLE_BEFORE}")" \
  '{
    status: "ok",
    phase: "B26.6",
    study_id: $adoption.study_id,
    workstream_id: $adoption.workstream_id,
    workspace_id: $adoption.workspace_id,
    session_id: $adoption.session_id,
    same_beagle_owned_identity: $adoption.same_beagle_owned_identity,
    adopted_variant_id: $adoption.adopted_variant_id,
    adopted_run_id: $adoption.adopted_run_id,
    next_study_auto_launch: $seed.auto_launch_new_study,
    bounded_study_baseline_on_context_packet: ($ctx.packet.bounded_study_baseline != null),
    context_baseline_phase: ($ctx.packet.bounded_study_baseline.phase // null),
    restart_recovered_identity: (
      $before.baseline_adoption.study_id == $after.baseline_adoption.study_id and
      $before.baseline_adoption.workspace_id == $after.baseline_adoption.workspace_id and
      $before.baseline_adoption.session_id == $after.baseline_adoption.session_id and
      $before.baseline_adoption.same_beagle_owned_identity == $after.baseline_adoption.same_beagle_owned_identity
    ),
    restart_recovered_adoption_ids: (
      $before.baseline_adoption.adoption_id == $after.baseline_adoption.adoption_id and
      $before.promoted_variant_receipt.receipt_id == $after.promoted_variant_receipt.receipt_id
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] baseline adoption smoke artifacts captured"
