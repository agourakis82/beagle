#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/external-registry-dry-run}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18462}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18282}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_SUBAGENT="${EXPECTED_SUBAGENT:-manuscript}"
EXPECTED_JATS_PROFILE="${EXPECTED_JATS_PROFILE:-jats-1.4-ready}"
EXTERNAL_SOURCE_FILE="${EXTERNAL_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_external_registry_staging.rs}"
PUBLICATION_SOURCE_FILE="${PUBLICATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_publication_package.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DATACITE_TEST_CONTRACT_FILE="${DATACITE_TEST_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/datacite-test-staging-payload-schema.yaml}"
CROSSREF_DRY_RUN_CONTRACT_FILE="${CROSSREF_DRY_RUN_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/crossref-dry-run-bundle-schema.yaml}"
READINESS_CONTRACT_FILE="${READINESS_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/external-staging-readiness-report-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B215_EXTERNAL_REGISTRY_DRY_RUN_TEST_DEPOSIT_STAGING.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B215_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B215_KNOWN_LIMITS.md}"
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
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
WORKSPACE_LOCAL_PORT="$(choose_local_port "${WORKSPACE_LOCAL_PORT}")"

EXTERNAL_SOURCE_PRESENT=0
PUBLICATION_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DATACITE_TEST_CONTRACT_PRESENT=0
CROSSREF_DRY_RUN_CONTRACT_PRESENT=0
READINESS_CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "workspace-external-staging|record_workspace_external_registry_staging|read_workspace_external_registry_staging" "${EXTERNAL_SOURCE_FILE}"; then
  EXTERNAL_SOURCE_PRESENT=1
fi
if rg -q "workspace-publication-package" "${PUBLICATION_SOURCE_FILE}"; then
  PUBLICATION_SOURCE_PRESENT=1
fi
if rg -q "workspace-external-staging" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DATACITE_TEST_CONTRACT_FILE}" ]] && DATACITE_TEST_CONTRACT_PRESENT=1
[[ -f "${CROSSREF_DRY_RUN_CONTRACT_FILE}" ]] && CROSSREF_DRY_RUN_CONTRACT_PRESENT=1
[[ -f "${READINESS_CONTRACT_FILE}" ]] && READINESS_CONTRACT_PRESENT=1
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1

jq -n \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_subagent "${EXPECTED_SUBAGENT}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --argjson external_source_present "${EXTERNAL_SOURCE_PRESENT}" \
  --argjson publication_source_present "${PUBLICATION_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson datacite_test_contract_present "${DATACITE_TEST_CONTRACT_PRESENT}" \
  --argjson crossref_dry_run_contract_present "${CROSSREF_DRY_RUN_CONTRACT_PRESENT}" \
  --argjson readiness_contract_present "${READINESS_CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_subagent: $expected_subagent,
    expected_jats_profile: $expected_jats_profile,
    external_source_present: $external_source_present,
    publication_source_present: $publication_source_present,
    http_source_present: $http_source_present,
    datacite_test_contract_present: $datacite_test_contract_present,
    crossref_dry_run_contract_present: $crossref_dry_run_contract_present,
    readiness_contract_present: $readiness_contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-list" \
  > "${OUT}/workspace-subagent-list.json"

curl -fsS -G -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  --data-urlencode "tool_id=claude-code" \
  --data-urlencode "work_mode=manuscript" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-route" \
  > "${OUT}/route-manuscript.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"core",
    "target_subagent_id":"experiments",
    "intent":"Prepare the experiments workspace",
    "summary":"Shift implementation results into experiments analysis.",
    "requested_work_mode":"analysis",
    "requested_tool_id":"codex"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-handoff" \
  > "${OUT}/handoff-core-to-experiments.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"experiments",
    "intent":"Move experiments output into manuscript drafting",
    "summary":"Shift the experiments interpretation into manuscript drafting.",
    "manuscript_goal":"Create the canonical manuscript surface.",
    "requested_work_mode":"manuscript",
    "requested_tool_id":"claude-code"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-manuscript-handoff" \
  > "${OUT}/workspace-manuscript-handoff-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"manuscript",
    "intent":"Assemble the canonical editorial artifact",
    "summary":"Freeze the bounded editorial assembly for Expedition 002.",
    "assembly_goal":"Produce a JATS-ready manuscript package.",
    "requested_tool_id":"claude-code",
    "section_profile":"jats-1.4-ready"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-manuscript-assembly" \
  > "${OUT}/workspace-manuscript-assembly-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"manuscript",
    "summary":"Freeze the canonical scholarly release bundle.",
    "release_goal":"Produce the release-grade scholarly package.",
    "release_notes":"Keep JATS QA, RO-Crate, DataCite metadata, and Crossref article XML explicit.",
    "requested_tool_id":"claude-code"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-scholarly-release" \
  > "${OUT}/workspace-scholarly-release-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"manuscript",
    "summary":"Freeze the canonical campaign as a deposit-ready publication package.",
    "publication_goal":"Stage the scholarly release as a deposit-ready publication package without performing real DOI or Crossref submission.",
    "staging_notes":"Prepare DataCite draft staging payloads, Crossref deposit-ready XML, and a publication readiness report without opening the real deposit boundary.",
    "requested_tool_id":"claude-code"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-publication-package" \
  > "${OUT}/workspace-publication-package-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_subagent_id":"manuscript",
    "summary":"Freeze the external registry dry-run package for the canonical campaign.",
    "staging_goal":"Prepare the canonical campaign package for external test staging without performing real registry calls.",
    "dry_run_notes":"Keep registry calls disabled while making the transport boundary explicit.",
    "requested_tool_id":"claude-code"
  }' \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-external-staging" \
  > "${OUT}/workspace-external-staging-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-external-staging" \
  > "${OUT}/workspace-external-staging.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/campaigns/${EXPECTED_CAMPAIGN}/review-bundle" \
  > "${OUT}/campaign-review-bundle.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/campaigns/${EXPECTED_CAMPAIGN}/jats-manuscript-pack" \
  > "${OUT}/campaign-jats-manuscript-pack.json"

jq '.external_staging_readiness_report' "${OUT}/workspace-external-staging.json" > "${OUT}/external-staging-readiness-report.json"
jq '.datacite_test_staging_payload' "${OUT}/workspace-external-staging.json" > "${OUT}/datacite-test-staging-payload.json"
jq '.crossref_dry_run_bundle' "${OUT}/workspace-external-staging.json" > "${OUT}/crossref-dry-run-bundle.json"
jq '.external_staging_bundle' "${OUT}/workspace-external-staging.json" > "${OUT}/external-registry-staging-bundle.json"
jq '.publication_package.publication_readiness_report' "${OUT}/workspace-external-staging.json" > "${OUT}/publication-readiness-report.json"
jq '.publication_package.scholarly_release.jats_qa_report' "${OUT}/workspace-external-staging.json" > "${OUT}/jats-qa-report.json"
jq '.publication_package.scholarly_release.ro_crate_export.ro_crate_metadata' "${OUT}/workspace-external-staging.json" > "${OUT}/ro-crate-metadata.json"
jq '.publication_package.scholarly_release.datacite_metadata' "${OUT}/workspace-external-staging.json" > "${OUT}/datacite-metadata.json"
jq -r '.publication_package.scholarly_release.crossref_article_stub.xml_stub' "${OUT}/workspace-external-staging.json" > "${OUT}/crossref-article.xml"
jq -r '.publication_package.scholarly_release.jats_pack.jats_xml' "${OUT}/workspace-external-staging.json" > "${OUT}/jats-article.xml"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context.json"
exec_workspace_file "${CONTEXT_ENV_FILE}" "${OUT}/workspace-context.env"
exec_workspace_file "/workspace/beagle/.beagle/context/subagents/manuscript.env" "${OUT}/manuscript.env"
exec_workspace_command ". /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\" \"\$BEAGLE_SUBAGENT_ID\" \"\$BEAGLE_SUBAGENT_ROLE_TAG\" \"\$PWD\"" "${OUT}/manuscript-identity.txt"

rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/workspace-restart.log" "${OUT}/workspace-rollout.log"
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health-after-restart.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-external-staging" \
  > "${OUT}/workspace-external-staging-after-restart.json"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context-after-restart.json"
exec_workspace_command ". /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \"\$BEAGLE_WORKSTREAM_ID\" \"\$BEAGLE_WORKSPACE_ID\" \"\$BEAGLE_SESSION_ID\" \"\$BEAGLE_SUBAGENT_ID\" \"\$BEAGLE_SUBAGENT_ROLE_TAG\" \"\$PWD\"" "${OUT}/manuscript-identity-after-restart.txt"

jq -n \
  --arg phase "B21.5" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "beagle-cluster-pilot" \
  --arg session_id "ws-cluster-workspace-habitat" \
  --arg source_subagent_id "${EXPECTED_SUBAGENT}" \
  --arg technical_external_staging_state "$(jq -r '.package.technical_external_staging_state' "${OUT}/workspace-external-staging.json")" \
  --arg readiness_state "$(jq -r '.package.readiness_state' "${OUT}/workspace-external-staging.json")" \
  --arg managed_attach_state "$(jq -r '.package.managed_attach_state' "${OUT}/workspace-external-staging.json")" \
  --arg stable_attach_alias "$(jq -r '.package.stable_attach_alias' "${OUT}/workspace-external-staging.json")" \
  --arg qa_state "$(jq -r '.continuity.qa_state' "${OUT}/workspace-external-staging.json")" \
  --argjson claim_count "$(jq '.continuity.claim_count' "${OUT}/workspace-external-staging.json")" \
  --argjson technical_blocker_count "$(jq '.external_staging_readiness_report.technical_blocker_count' "${OUT}/workspace-external-staging.json")" \
  --argjson ro_crate_payload_count "$(jq '.continuity.ro_crate_payload_count' "${OUT}/workspace-external-staging.json")" \
  --argjson restart_recovered_session true \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    source_subagent_id: $source_subagent_id,
    qa_state: $qa_state,
    technical_external_staging_state: $technical_external_staging_state,
    readiness_state: $readiness_state,
    managed_attach_state: $managed_attach_state,
    stable_attach_alias: $stable_attach_alias,
    claim_count: $claim_count,
    technical_blocker_count: $technical_blocker_count,
    ro_crate_payload_count: $ro_crate_payload_count,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health

printf '[OK] external registry dry-run smoke completed\n'
