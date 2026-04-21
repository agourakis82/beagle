#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/study-convergence}"
PROOF_OUT="${PROOF_OUT:-${OUT}/container-proof}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18534}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B263_BASE_OUT="${B263_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/study-proposal-dispatch}"
B262_BASE_OUT="${B262_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/study-decision-engine}"
B261_BASE_OUT="${B261_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/study-registry-sweep}"

STUDY_CONVERGENCE_SOURCE_FILE="${STUDY_CONVERGENCE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_convergence.rs}"
STUDY_DECISION_SOURCE_FILE="${STUDY_DECISION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_decision.rs}"
STUDY_CONTINUATION_SOURCE_FILE="${STUDY_CONTINUATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_continuation.rs}"
STUDY_PROPOSAL_DISPATCH_SOURCE_FILE="${STUDY_PROPOSAL_DISPATCH_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_proposal_dispatch.rs}"
NEXT_RUN_PROPOSAL_SOURCE_FILE="${NEXT_RUN_PROPOSAL_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/next_run_proposal.rs}"
STUDY_REGISTRY_SOURCE_FILE="${STUDY_REGISTRY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_registry.rs}"
STUDY_DAG_SOURCE_FILE="${STUDY_DAG_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_dag.rs}"
STUDY_SWEEP_SOURCE_FILE="${STUDY_SWEEP_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/study_sweep.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B264_STUDY_CONVERGENCE_AND_VARIANT_PROMOTION_GATE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B264_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B264_KNOWN_LIMITS.md}"
STUDY_CONVERGENCE_SCHEMA_FILE="${STUDY_CONVERGENCE_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-convergence-schema.yaml}"
VARIANT_PROMOTION_DECISION_SCHEMA_FILE="${VARIANT_PROMOTION_DECISION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/variant-promotion-decision-schema.yaml}"
STUDY_CLOSEOUT_SUMMARY_SCHEMA_FILE="${STUDY_CLOSEOUT_SUMMARY_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/study-closeout-summary-schema.yaml}"

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
BASELINE_B263_SMOKE="${B263_BASE_OUT}/smoke.json"
BASELINE_B262_SMOKE="${B262_BASE_OUT}/smoke.json"
BASELINE_B261_SMOKE="${B261_BASE_OUT}/smoke.json"

SOURCE_CONVERGENCE_PRESENT=0
SOURCE_DECISION_PRESENT=0
SOURCE_CONTINUATION_PRESENT=0
SOURCE_DISPATCH_PRESENT=0
SOURCE_NEXT_RUN_PRESENT=0
SOURCE_REGISTRY_PRESENT=0
SOURCE_DAG_PRESENT=0
SOURCE_SWEEP_PRESENT=0
SOURCE_LIB_PRESENT=0
SOURCE_HTTP_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
SCHEMA_CONVERGENCE_PRESENT=0
SCHEMA_PROMOTION_PRESENT=0
SCHEMA_CLOSEOUT_PRESENT=0
B263_BASE_PRESENT=0
B262_BASE_PRESENT=0
B261_BASE_PRESENT=0

if rg -q "StudyConvergence|ensure_study_convergence|study-convergence" "${STUDY_CONVERGENCE_SOURCE_FILE}"; then
  SOURCE_CONVERGENCE_PRESENT=1
fi
if rg -q "StudyDecision|StudyDecisionBasis|study-decision" "${STUDY_DECISION_SOURCE_FILE}"; then
  SOURCE_DECISION_PRESENT=1
fi
if rg -q "StudyContinuationState|StudyRunUpdate|study-run-update" "${STUDY_CONTINUATION_SOURCE_FILE}"; then
  SOURCE_CONTINUATION_PRESENT=1
fi
if rg -q "StudyProposalDispatch|study-proposal-dispatch" "${STUDY_PROPOSAL_DISPATCH_SOURCE_FILE}"; then
  SOURCE_DISPATCH_PRESENT=1
fi
if rg -q "NextRunProposal|next-run-proposal" "${NEXT_RUN_PROPOSAL_SOURCE_FILE}"; then
  SOURCE_NEXT_RUN_PRESENT=1
fi
if rg -q "StudyRegistry|ComparativeResultSummary|study-registry" "${STUDY_REGISTRY_SOURCE_FILE}"; then
  SOURCE_REGISTRY_PRESENT=1
fi
if rg -q "StudyDag|study-dag" "${STUDY_DAG_SOURCE_FILE}"; then
  SOURCE_DAG_PRESENT=1
fi
if rg -q "StudySweep|study-sweep" "${STUDY_SWEEP_SOURCE_FILE}"; then
  SOURCE_SWEEP_PRESENT=1
fi
if rg -q "pub mod study_convergence|ensure_study_convergence|VariantPromotionDecision" "${LIB_SOURCE_FILE}"; then
  SOURCE_LIB_PRESENT=1
fi
if rg -q "study-convergence" "${HTTP_SOURCE_FILE}"; then
  SOURCE_HTTP_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${STUDY_CONVERGENCE_SCHEMA_FILE}" ]] && SCHEMA_CONVERGENCE_PRESENT=1
[[ -f "${VARIANT_PROMOTION_DECISION_SCHEMA_FILE}" ]] && SCHEMA_PROMOTION_PRESENT=1
[[ -f "${STUDY_CLOSEOUT_SUMMARY_SCHEMA_FILE}" ]] && SCHEMA_CLOSEOUT_PRESENT=1
[[ -f "${BASELINE_B263_SMOKE}" ]] && B263_BASE_PRESENT=1
[[ -f "${BASELINE_B262_SMOKE}" ]] && B262_BASE_PRESENT=1
[[ -f "${BASELINE_B261_SMOKE}" ]] && B261_BASE_PRESENT=1

jq -n \
  --argjson source_convergence_present "${SOURCE_CONVERGENCE_PRESENT}" \
  --argjson source_decision_present "${SOURCE_DECISION_PRESENT}" \
  --argjson source_continuation_present "${SOURCE_CONTINUATION_PRESENT}" \
  --argjson source_dispatch_present "${SOURCE_DISPATCH_PRESENT}" \
  --argjson source_next_run_present "${SOURCE_NEXT_RUN_PRESENT}" \
  --argjson source_registry_present "${SOURCE_REGISTRY_PRESENT}" \
  --argjson source_dag_present "${SOURCE_DAG_PRESENT}" \
  --argjson source_sweep_present "${SOURCE_SWEEP_PRESENT}" \
  --argjson source_lib_present "${SOURCE_LIB_PRESENT}" \
  --argjson source_http_present "${SOURCE_HTTP_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson schema_convergence_present "${SCHEMA_CONVERGENCE_PRESENT}" \
  --argjson schema_promotion_present "${SCHEMA_PROMOTION_PRESENT}" \
  --argjson schema_closeout_present "${SCHEMA_CLOSEOUT_PRESENT}" \
  --argjson b263_base_present "${B263_BASE_PRESENT}" \
  --argjson b262_base_present "${B262_BASE_PRESENT}" \
  --argjson b261_base_present "${B261_BASE_PRESENT}" \
  '{
    source_convergence_present: $source_convergence_present,
    source_decision_present: $source_decision_present,
    source_continuation_present: $source_continuation_present,
    source_dispatch_present: $source_dispatch_present,
    source_next_run_present: $source_next_run_present,
    source_registry_present: $source_registry_present,
    source_dag_present: $source_dag_present,
    source_sweep_present: $source_sweep_present,
    source_lib_present: $source_lib_present,
    source_http_present: $source_http_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    schema_convergence_present: $schema_convergence_present,
    schema_promotion_present: $schema_promotion_present,
    schema_closeout_present: $schema_closeout_present,
    b263_base_present: $b263_base_present,
    b262_base_present: $b262_base_present,
    b261_base_present: $b261_base_present
  }' > "${SOURCE_SUMMARY}"

[[ "${SOURCE_CONVERGENCE_PRESENT}" == "1" ]] || { echo "[FAIL] convergence source missing" >&2; exit 1; }
[[ "${SOURCE_DECISION_PRESENT}" == "1" ]] || { echo "[FAIL] decision source missing" >&2; exit 1; }
[[ "${SOURCE_CONTINUATION_PRESENT}" == "1" ]] || { echo "[FAIL] continuation source missing" >&2; exit 1; }
[[ "${SOURCE_DISPATCH_PRESENT}" == "1" ]] || { echo "[FAIL] dispatch source missing" >&2; exit 1; }
[[ "${SOURCE_NEXT_RUN_PRESENT}" == "1" ]] || { echo "[FAIL] next-run source missing" >&2; exit 1; }
[[ "${SOURCE_REGISTRY_PRESENT}" == "1" ]] || { echo "[FAIL] registry source missing" >&2; exit 1; }
[[ "${SOURCE_DAG_PRESENT}" == "1" ]] || { echo "[FAIL] dag source missing" >&2; exit 1; }
[[ "${SOURCE_SWEEP_PRESENT}" == "1" ]] || { echo "[FAIL] sweep source missing" >&2; exit 1; }
[[ "${SOURCE_LIB_PRESENT}" == "1" ]] || { echo "[FAIL] lib source missing" >&2; exit 1; }
[[ "${SOURCE_HTTP_PRESENT}" == "1" ]] || { echo "[FAIL] http source missing" >&2; exit 1; }
[[ "${DOC_PRESENT}" == "1" ]] || { echo "[FAIL] doc missing" >&2; exit 1; }
[[ "${GO_NO_GO_PRESENT}" == "1" ]] || { echo "[FAIL] go/no-go missing" >&2; exit 1; }
[[ "${KNOWN_LIMITS_PRESENT}" == "1" ]] || { echo "[FAIL] known limits missing" >&2; exit 1; }
[[ "${SCHEMA_CONVERGENCE_PRESENT}" == "1" ]] || { echo "[FAIL] convergence schema missing" >&2; exit 1; }
[[ "${SCHEMA_PROMOTION_PRESENT}" == "1" ]] || { echo "[FAIL] promotion schema missing" >&2; exit 1; }
[[ "${SCHEMA_CLOSEOUT_PRESENT}" == "1" ]] || { echo "[FAIL] closeout schema missing" >&2; exit 1; }
[[ "${B263_BASE_PRESENT}" == "1" ]] || { echo "[FAIL] B26.3 baseline missing" >&2; exit 1; }
[[ "${B262_BASE_PRESENT}" == "1" ]] || { echo "[FAIL] B26.2 baseline missing" >&2; exit 1; }
[[ "${B261_BASE_PRESENT}" == "1" ]] || { echo "[FAIL] B26.1 baseline missing" >&2; exit 1; }

AUTH_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${AUTH_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

FETCH_PATH="/api/darwin/workstreams/${WORKSTREAM_ID}/study-convergence"
BUNDLE_BEFORE="${OUT}/study-convergence-bundle-before.json"
BUNDLE_AFTER="${PROOF_OUT}/study-convergence-bundle-after-restart.json"
fetch_json "${LOCAL_PORT}" "${FETCH_PATH}" "${BUNDLE_BEFORE}"

jq '.study_convergence' "${BUNDLE_BEFORE}" > "${OUT}/study-convergence.json"
jq '.variant_promotion_decision' "${BUNDLE_BEFORE}" > "${OUT}/variant-promotion-decision.json"
jq '.study_closeout_summary' "${BUNDLE_BEFORE}" > "${OUT}/study-closeout-summary.json"

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" >/dev/null
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s >/dev/null
sleep 2

fetch_json "${LOCAL_PORT}" "${FETCH_PATH}" "${BUNDLE_AFTER}"

jq '.study_convergence' "${BUNDLE_AFTER}" > "${PROOF_OUT}/study-convergence-after-restart.json"
jq '.variant_promotion_decision' "${BUNDLE_AFTER}" > "${PROOF_OUT}/variant-promotion-decision-after-restart.json"
jq '.study_closeout_summary' "${BUNDLE_AFTER}" > "${PROOF_OUT}/study-closeout-summary-after-restart.json"

jq -n \
  --argjson before "$(jq -c '.' "${BUNDLE_BEFORE}")" \
  --argjson after "$(jq -c '.' "${BUNDLE_AFTER}")" \
  --argjson convergence "$(jq -c '.study_convergence' "${BUNDLE_BEFORE}")" \
  --argjson promotion "$(jq -c '.variant_promotion_decision' "${BUNDLE_BEFORE}")" \
  --argjson closeout "$(jq -c '.study_closeout_summary' "${BUNDLE_BEFORE}")" \
  '{
    phase: "B26.4",
    study_id: $convergence.study_id,
    workstream_id: $convergence.workstream_id,
    workspace_id: $convergence.workspace_id,
    session_id: $convergence.session_id,
    same_beagle_owned_identity: $convergence.same_beagle_owned_identity,
    convergence_state: $convergence.convergence_state,
    recommended_action: $convergence.recommended_action,
    enough_evidence_to_stop: $convergence.enough_evidence_to_stop,
    promoted_variant_id: $promotion.promoted_variant_id,
    promoted_variant_label: $promotion.promoted_variant_label,
    promoted_run_id: $promotion.promoted_run_id,
    promoted_run_label: $promotion.promoted_run_label,
    archived_variant_count: $promotion.archived_variant_count,
    final_study_state: $closeout.final_study_state,
    final_comparative_decision: $closeout.final_comparative_decision,
    final_variant_promotion_state: $closeout.final_variant_promotion_state,
    restart_recovered_identity: (
      $before.study_convergence.study_id == $after.study_convergence.study_id and
      $before.study_convergence.workspace_id == $after.study_convergence.workspace_id and
      $before.study_convergence.session_id == $after.study_convergence.session_id and
      $before.study_convergence.same_beagle_owned_identity == $after.study_convergence.same_beagle_owned_identity and
      $before.variant_promotion_decision.decision_action == $after.variant_promotion_decision.decision_action and
      $before.study_closeout_summary.final_comparative_decision == $after.study_closeout_summary.final_comparative_decision
    ),
    restart_recovered_summary: (
      $before.study_convergence.convergence_state == $after.study_convergence.convergence_state and
      $before.study_closeout_summary.final_study_state == $after.study_closeout_summary.final_study_state and
      $before.study_closeout_summary.final_variant_promotion_state == $after.study_closeout_summary.final_variant_promotion_state
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] study convergence smoke artifacts captured"
