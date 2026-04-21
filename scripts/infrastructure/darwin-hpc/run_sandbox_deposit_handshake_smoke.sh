#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/sandbox-deposit-handshake}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18472}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18292}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_SUBAGENT="${EXPECTED_SUBAGENT:-manuscript}"
EXPECTED_JATS_PROFILE="${EXPECTED_JATS_PROFILE:-jats-1.4-ready}"
SANDBOX_SOURCE_FILE="${SANDBOX_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_sandbox_deposit_handshake.rs}"
EXTERNAL_SOURCE_FILE="${EXTERNAL_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_external_registry_staging.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DATACITE_RECEIPT_CONTRACT_FILE="${DATACITE_RECEIPT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/datacite-test-receipt-schema.yaml}"
CROSSREF_RECEIPT_CONTRACT_FILE="${CROSSREF_RECEIPT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/crossref-test-receipt-schema.yaml}"
LEDGER_CONTRACT_FILE="${LEDGER_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/registry-submission-ledger-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B216_SANDBOX_DEPOSIT_HANDSHAKE_AND_RECEIPT_TRACKING.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B216_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B216_KNOWN_LIMITS.md}"
SECRET_EXAMPLE_FILE="${SECRET_EXAMPLE_FILE:-${ROOT}/k8s/beagle/secret.example.yaml}"
UPSTREAM_RUN_SCRIPT="${UPSTREAM_RUN_SCRIPT:-${ROOT}/scripts/infrastructure/darwin-hpc/run_external_registry_dry_run_smoke.sh}"
CONTEXT_PACKET_FILE="${CONTEXT_PACKET_FILE:-/workspace/beagle/.beagle/context/current-context-packet.json}"
CONTEXT_ENV_FILE="${CONTEXT_ENV_FILE:-/workspace/beagle/.beagle/context/beagle-context.env}"

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
  local service_name="$1"
  local local_port="$2"
  local remote_port="$3"
  local pf_log="$4"
  local pid_var="$5"

  : > "${pf_log}"
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${service_name}" "${local_port}:${remote_port}" >"${pf_log}" 2>&1 &
  local pf_pid=$!

  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
      printf -v "${pid_var}" '%s' "${pf_pid}"
      return 0
    fi
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${local_port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${local_port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

stop_port_forward() {
  local pid_var="$1"
  local pid="${!pid_var:-}"
  if [[ -n "${pid}" ]]; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    printf -v "${pid_var}" '%s' ""
  fi
}

wait_for_workspace_health() {
  local port="$1"
  local target="$2"
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    sleep 2
  done
  echo "[FAIL] workspace IDE did not become ready on local port ${port}" >&2
  exit 1
}

exec_workspace_file() {
  local remote_path="$1"
  local target="$2"
  ${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- sh -lc "cat '${remote_path}'" > "${target}"
}

exec_workspace_command() {
  local command="$1"
  local target="$2"
  ${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- sh -lc "${command}" > "${target}"
}

rollout_deployment() {
  local deployment="$1"
  local restart_log="$2"
  local rollout_log="$3"
  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${deployment}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${deployment}" --timeout=900s > "${rollout_log}"
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
  stop_port_forward BEAGLE_PF_PID
  stop_port_forward WORKSPACE_PF_PID
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"

ROOT="${ROOT}" \
OUT="${OUT}" \
KUBECTL="${KUBECTL}" \
NAMESPACE="${NAMESPACE}" \
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT}" \
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME}" \
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME}" \
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME}" \
SECRET_NAME="${SECRET_NAME}" \
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM}" \
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN}" \
EXPECTED_SUBAGENT="${EXPECTED_SUBAGENT}" \
EXPECTED_JATS_PROFILE="${EXPECTED_JATS_PROFILE}" \
bash "${UPSTREAM_RUN_SCRIPT}"

cp "${OUT}/source-summary.json" "${OUT}/external-staging-source-summary.json"
cp "${OUT}/smoke.json" "${OUT}/external-staging-smoke.json"

BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
WORKSPACE_LOCAL_PORT="$(choose_local_port "${WORKSPACE_LOCAL_PORT}")"

SANDBOX_SOURCE_PRESENT=0
EXTERNAL_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DATACITE_RECEIPT_CONTRACT_PRESENT=0
CROSSREF_RECEIPT_CONTRACT_PRESENT=0
LEDGER_CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
SECRET_EXAMPLE_PRESENT=0
SECRET_EXAMPLE_HAS_TEST_KEYS=0

if rg -q "workspace-sandbox-deposit|record_workspace_sandbox_deposit_handshake|read_workspace_sandbox_deposit_handshake" "${SANDBOX_SOURCE_FILE}"; then
  SANDBOX_SOURCE_PRESENT=1
fi
if rg -q "workspace-external-staging" "${EXTERNAL_SOURCE_FILE}"; then
  EXTERNAL_SOURCE_PRESENT=1
fi
if rg -q "workspace-sandbox-deposit" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DATACITE_RECEIPT_CONTRACT_FILE}" ]] && DATACITE_RECEIPT_CONTRACT_PRESENT=1
[[ -f "${CROSSREF_RECEIPT_CONTRACT_FILE}" ]] && CROSSREF_RECEIPT_CONTRACT_PRESENT=1
[[ -f "${LEDGER_CONTRACT_FILE}" ]] && LEDGER_CONTRACT_PRESENT=1
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
if [[ -f "${SECRET_EXAMPLE_FILE}" ]]; then
  SECRET_EXAMPLE_PRESENT=1
  if rg -q "BEAGLE_DATACITE_TEST_USERNAME|BEAGLE_CROSSREF_TEST_USERNAME" "${SECRET_EXAMPLE_FILE}"; then
    SECRET_EXAMPLE_HAS_TEST_KEYS=1
  fi
fi

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_subagent "${EXPECTED_SUBAGENT}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --argjson sandbox_source_present "${SANDBOX_SOURCE_PRESENT}" \
  --argjson external_source_present "${EXTERNAL_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson datacite_receipt_contract_present "${DATACITE_RECEIPT_CONTRACT_PRESENT}" \
  --argjson crossref_receipt_contract_present "${CROSSREF_RECEIPT_CONTRACT_PRESENT}" \
  --argjson ledger_contract_present "${LEDGER_CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson secret_example_present "${SECRET_EXAMPLE_PRESENT}" \
  --argjson secret_example_has_test_keys "${SECRET_EXAMPLE_HAS_TEST_KEYS}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_subagent: $expected_subagent,
    expected_jats_profile: $expected_jats_profile,
    sandbox_source_present: $sandbox_source_present,
    external_source_present: $external_source_present,
    http_source_present: $http_source_present,
    datacite_receipt_contract_present: $datacite_receipt_contract_present,
    crossref_receipt_contract_present: $crossref_receipt_contract_present,
    ledger_contract_present: $ledger_contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    secret_example_present: $secret_example_present,
    secret_example_has_test_keys: $secret_example_has_test_keys
  }' > "${OUT}/source-summary.json"

API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"manuscript",
    "summary":"Freeze the sandbox deposit handshake for the canonical campaign.",
    "handshake_goal":"Execute live test-registry handshakes and preserve their receipts without crossing into production deposit.",
    "handshake_notes":"Perform real POSTs against the DataCite test API and the Crossref test deposit endpoint, keep the receipts canonical, and leave claim-linked-human-eval-pending explicit.",
    "requested_tool_id":"claude-code"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-sandbox-deposit" \
  > "${OUT}/workspace-sandbox-deposit-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-sandbox-deposit" \
  > "${OUT}/workspace-sandbox-deposit.json"

jq '.datacite_test_receipt' "${OUT}/workspace-sandbox-deposit.json" > "${OUT}/datacite-test-receipt.json"
jq '.crossref_test_receipt' "${OUT}/workspace-sandbox-deposit.json" > "${OUT}/crossref-test-receipt.json"
jq '.registry_submission_ledger' "${OUT}/workspace-sandbox-deposit.json" > "${OUT}/registry-submission-ledger.json"
jq '.sandbox_deposit_bundle' "${OUT}/workspace-sandbox-deposit.json" > "${OUT}/sandbox-deposit-bundle.json"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context.json"
exec_workspace_file "${CONTEXT_ENV_FILE}" "${OUT}/workspace-context.env"
exec_workspace_file "/workspace/beagle/.beagle/context/subagents/manuscript.env" "${OUT}/manuscript.env"
exec_workspace_command ". /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\" \"\$BEAGLE_SUBAGENT_ID\" \"\$BEAGLE_SUBAGENT_ROLE_TAG\" \"\$PWD\"" "${OUT}/manuscript-identity.txt"

rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/workspace-restart.log" "${OUT}/workspace-rollout.log"
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health-after-restart.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-sandbox-deposit" \
  > "${OUT}/workspace-sandbox-deposit-after-restart.json"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context-after-restart.json"
exec_workspace_command ". /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\" \"\$BEAGLE_SUBAGENT_ID\" \"\$BEAGLE_SUBAGENT_ROLE_TAG\" \"\$PWD\"" "${OUT}/manuscript-identity-after-restart.txt"

jq -n \
  --arg phase "B21.6" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "beagle-cluster-pilot" \
  --arg session_id "ws-cluster-workspace-habitat" \
  --arg source_subagent_id "${EXPECTED_SUBAGENT}" \
  --arg registry_handshake_state "$(jq -r '.package.registry_handshake_state' "${OUT}/workspace-sandbox-deposit.json")" \
  --arg technical_external_staging_state "$(jq -r '.package.technical_external_staging_state' "${OUT}/workspace-sandbox-deposit.json")" \
  --arg readiness_state "$(jq -r '.package.readiness_state' "${OUT}/workspace-sandbox-deposit.json")" \
  --arg managed_attach_state "$(jq -r '.package.managed_attach_state' "${OUT}/workspace-sandbox-deposit.json")" \
  --arg stable_attach_alias "$(jq -r '.package.stable_attach_alias' "${OUT}/workspace-sandbox-deposit.json")" \
  --argjson live_registry_response_count "$(jq '.continuity.live_registry_response_count' "${OUT}/workspace-sandbox-deposit.json")" \
  --argjson accepted_registry_count "$(jq '.continuity.accepted_registry_count' "${OUT}/workspace-sandbox-deposit.json")" \
  --argjson auth_blocked_registry_count "$(jq '.continuity.auth_blocked_registry_count' "${OUT}/workspace-sandbox-deposit.json")" \
  --argjson datacite_http_status "$(jq '.datacite_test_receipt.http_status' "${OUT}/workspace-sandbox-deposit.json")" \
  --argjson crossref_http_status "$(jq '.crossref_test_receipt.http_status' "${OUT}/workspace-sandbox-deposit.json")" \
  --argjson restart_recovered_session true \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    source_subagent_id: $source_subagent_id,
    registry_handshake_state: $registry_handshake_state,
    technical_external_staging_state: $technical_external_staging_state,
    readiness_state: $readiness_state,
    managed_attach_state: $managed_attach_state,
    stable_attach_alias: $stable_attach_alias,
    live_registry_response_count: $live_registry_response_count,
    accepted_registry_count: $accepted_registry_count,
    auth_blocked_registry_count: $auth_blocked_registry_count,
    datacite_http_status: $datacite_http_status,
    crossref_http_status: $crossref_http_status,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health

printf '[OK] sandbox deposit handshake smoke completed\n'
