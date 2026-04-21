#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/deposit-ready-publication-package}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18452}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18272}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_SUBAGENT="${EXPECTED_SUBAGENT:-manuscript}"
EXPECTED_JATS_PROFILE="${EXPECTED_JATS_PROFILE:-jats-1.4-ready}"
PUBLICATION_SOURCE_FILE="${PUBLICATION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_publication_package.rs}"
RELEASE_SOURCE_FILE="${RELEASE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_scholarly_release.rs}"
ASSEMBLY_SOURCE_FILE="${ASSEMBLY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_manuscript_assembly.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DATACITE_DEPOSIT_CONTRACT_FILE="${DATACITE_DEPOSIT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/datacite-deposit-payload-schema.yaml}"
CROSSREF_DEPOSIT_CONTRACT_FILE="${CROSSREF_DEPOSIT_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/crossref-deposit-bundle-schema.yaml}"
READINESS_CONTRACT_FILE="${READINESS_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/publication-readiness-report-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B214_DEPOSIT_READY_PUBLICATION_PACKAGE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B214_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B214_KNOWN_LIMITS.md}"
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

PUBLICATION_SOURCE_PRESENT=0
RELEASE_SOURCE_PRESENT=0
ASSEMBLY_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DATACITE_DEPOSIT_CONTRACT_PRESENT=0
CROSSREF_DEPOSIT_CONTRACT_PRESENT=0
READINESS_CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "workspace-publication-package|record_workspace_publication_package|read_workspace_publication_package" "${PUBLICATION_SOURCE_FILE}"; then
  PUBLICATION_SOURCE_PRESENT=1
fi
if rg -q "workspace-scholarly-release|record_workspace_scholarly_release|read_workspace_scholarly_release" "${RELEASE_SOURCE_FILE}"; then
  RELEASE_SOURCE_PRESENT=1
fi
if rg -q "workspace-manuscript-assembly|record_workspace_manuscript_assembly|read_workspace_manuscript_assembly" "${ASSEMBLY_SOURCE_FILE}"; then
  ASSEMBLY_SOURCE_PRESENT=1
fi
if rg -q "workspace-publication-package" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if [[ -f "${DATACITE_DEPOSIT_CONTRACT_FILE}" ]]; then
  DATACITE_DEPOSIT_CONTRACT_PRESENT=1
fi
if [[ -f "${CROSSREF_DEPOSIT_CONTRACT_FILE}" ]]; then
  CROSSREF_DEPOSIT_CONTRACT_PRESENT=1
fi
if [[ -f "${READINESS_CONTRACT_FILE}" ]]; then
  READINESS_CONTRACT_PRESENT=1
fi
if [[ -f "${DOC_FILE}" ]]; then
  DOC_PRESENT=1
fi
if [[ -f "${GO_NO_GO_FILE}" ]]; then
  GO_NO_GO_PRESENT=1
fi
if [[ -f "${KNOWN_LIMITS_FILE}" ]]; then
  KNOWN_LIMITS_PRESENT=1
fi

jq -nc \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_subagent "${EXPECTED_SUBAGENT}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --argjson publication_source_present "${PUBLICATION_SOURCE_PRESENT}" \
  --argjson release_source_present "${RELEASE_SOURCE_PRESENT}" \
  --argjson assembly_source_present "${ASSEMBLY_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson datacite_deposit_contract_present "${DATACITE_DEPOSIT_CONTRACT_PRESENT}" \
  --argjson crossref_deposit_contract_present "${CROSSREF_DEPOSIT_CONTRACT_PRESENT}" \
  --argjson readiness_contract_present "${READINESS_CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_campaign: $expected_campaign,
    expected_workstream: $expected_workstream,
    expected_subagent: $expected_subagent,
    expected_jats_profile: $expected_jats_profile,
    publication_source_present: $publication_source_present,
    release_source_present: $release_source_present,
    assembly_source_present: $assembly_source_present,
    http_source_present: $http_source_present,
    datacite_deposit_contract_present: $datacite_deposit_contract_present,
    crossref_deposit_contract_present: $crossref_deposit_contract_present,
    readiness_contract_present: $readiness_contract_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health.txt"

BEAGLE_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${BEAGLE_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-list" \
  > "${OUT}/workspace-subagent-list.json"

curl -fsS -G -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  --data-urlencode "tool_id=claude-code" \
  --data-urlencode "work_mode=manuscript" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-route" \
  > "${OUT}/route-manuscript.json"

jq -nc '{
  source_subagent_id: "core",
  target_subagent_id: "experiments",
  requested_work_mode: "analysis",
  requested_tool_id: "claude-code",
  intent: "analysis",
  summary: "Carry the canonical session into bounded experiments review."
}' > "${OUT}/subagent-handoff-request.json"

curl -fsS -X POST -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'content-type: application/json' \
  --data @"${OUT}/subagent-handoff-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-subagent-handoff" \
  > "${OUT}/handoff-core-to-experiments.json"

jq -nc '{
  source_subagent_id: "experiments",
  requested_work_mode: "manuscript",
  requested_tool_id: "claude-code",
  intent: "manuscript",
  summary: "Shift the experiments interpretation into manuscript drafting.",
  manuscript_goal: "Freeze a bounded manuscript-oriented packet for the active campaign."
}' > "${OUT}/manuscript-handoff-request.json"

curl -fsS -X POST -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'content-type: application/json' \
  --data @"${OUT}/manuscript-handoff-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-manuscript-handoff" \
  > "${OUT}/workspace-manuscript-handoff-post.json"

jq -nc '{
  source_subagent_id: "manuscript",
  requested_tool_id: "claude-code",
  section_profile: "jats-1.4-ready",
  intent: "editorial-assembly",
  summary: "Freeze the claim/evidence/manuscript context into a JATS-ready editorial artifact inside the manuscript subagent.",
  assembly_goal: "Keep claims, evidence, provenance, and editorial sections explicitly linked without minting a new workspace session."
}' > "${OUT}/manuscript-assembly-request.json"

curl -fsS -X POST -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'content-type: application/json' \
  --data @"${OUT}/manuscript-assembly-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-manuscript-assembly" \
  > "${OUT}/workspace-manuscript-assembly-post.json"

jq -nc '{
  source_subagent_id: "manuscript",
  requested_tool_id: "claude-code",
  summary: "Freeze the manuscript subagent output into a release-grade scholarly package.",
  release_goal: "Assemble a bounded release bundle with JATS QA, RO-Crate, DataCite-ready metadata, and a Crossref-compatible article stub.",
  release_notes: "Keep readiness and provenance explicit while preparing externalizable crosswalk exports."
}' > "${OUT}/scholarly-release-request.json"

curl -fsS -X POST -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'content-type: application/json' \
  --data @"${OUT}/scholarly-release-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-scholarly-release" \
  > "${OUT}/workspace-scholarly-release-post.json"

jq -nc '{
  source_subagent_id: "manuscript",
  requested_tool_id: "claude-code",
  summary: "Freeze technical deposit artifacts while keeping human-eval pending explicit.",
  publication_goal: "Stage the scholarly release as a deposit-ready publication package without performing real DOI or Crossref submission.",
  staging_notes: "Prepare DataCite draft staging payloads, Crossref deposit-ready XML, and a publication readiness report without opening the real deposit boundary."
}' > "${OUT}/publication-package-request.json"

curl -fsS -X POST -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'content-type: application/json' \
  --data @"${OUT}/publication-package-request.json" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-publication-package" \
  > "${OUT}/workspace-publication-package-post.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-publication-package" \
  > "${OUT}/workspace-publication-package.json"

CAMPAIGN_ID="$(jq -r '.package.campaign_id' "${OUT}/workspace-publication-package.json")"
curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/campaigns/${CAMPAIGN_ID}/review-bundle" \
  > "${OUT}/campaign-review-bundle.json"
curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/campaigns/${CAMPAIGN_ID}/jats-manuscript-pack" \
  > "${OUT}/campaign-jats-manuscript-pack.json"

jq '.publication_readiness_report' "${OUT}/workspace-publication-package.json" > "${OUT}/publication-readiness-report.json"
jq '.datacite_deposit_payload' "${OUT}/workspace-publication-package.json" > "${OUT}/datacite-deposit-payload.json"
jq '.crossref_deposit_bundle' "${OUT}/workspace-publication-package.json" > "${OUT}/crossref-deposit-bundle.json"
jq '.publication_package_bundle' "${OUT}/workspace-publication-package.json" > "${OUT}/publication-package-bundle.json"
jq '.scholarly_release.jats_qa_report' "${OUT}/workspace-publication-package.json" > "${OUT}/jats-qa-report.json"
jq '.scholarly_release.ro_crate_export.metadata' "${OUT}/workspace-publication-package.json" > "${OUT}/ro-crate-metadata.json"
jq '.scholarly_release.datacite_metadata' "${OUT}/workspace-publication-package.json" > "${OUT}/datacite-metadata.json"
jq -r '.scholarly_release.crossref_article_stub.xml_stub' "${OUT}/workspace-publication-package.json" > "${OUT}/crossref-article.xml"
jq -r '.scholarly_release.jats_pack.jats_xml' "${OUT}/workspace-publication-package.json" > "${OUT}/jats-article.xml"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" \
  > "${OUT}/workspace-context.json"
exec_workspace_file "${CONTEXT_ENV_FILE}" "${OUT}/workspace-context.env"
exec_workspace_command ". /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \"\${BEAGLE_WORKSTREAM_ID}\" \"\${BEAGLE_WORKSPACE_ID}\" \"\${BEAGLE_SESSION_ID}\" \"\${BEAGLE_SUBAGENT_ID}\" \"\${BEAGLE_SUBAGENT_ROLE_TAG}\" \"\${PWD}\"" "${OUT}/manuscript-identity.txt"
exec_workspace_file "/workspace/beagle/.beagle/context/subagents/manuscript.env" "${OUT}/manuscript.env"

rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/workspace-restart.txt" "${OUT}/workspace-rollout.txt"
stop_port_forward WORKSPACE_PF_PID
WORKSPACE_LOCAL_PORT="$(choose_local_port "${WORKSPACE_LOCAL_PORT}")"
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward-after-restart.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health-after-restart.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-publication-package" \
  > "${OUT}/workspace-publication-package-after-restart.json"
curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" \
  > "${OUT}/workspace-context-after-restart.json"
exec_workspace_command ". /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \"\${BEAGLE_WORKSTREAM_ID}\" \"\${BEAGLE_WORKSPACE_ID}\" \"\${BEAGLE_SESSION_ID}\" \"\${BEAGLE_SUBAGENT_ID}\" \"\${BEAGLE_SUBAGENT_ROLE_TAG}\" \"\${PWD}\"" "${OUT}/manuscript-identity-after-restart.txt"

jq -nc \
  --arg phase "B21.4" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "$(jq -r '.package.workspace_id' "${OUT}/workspace-publication-package.json")" \
  --arg session_id "$(jq -r '.package.session_id' "${OUT}/workspace-publication-package.json")" \
  --arg campaign_id "${CAMPAIGN_ID}" \
  --arg source_subagent_id "$(jq -r '.package.source_subagent_id' "${OUT}/workspace-publication-package.json")" \
  --arg package_id "$(jq -r '.package.package_id' "${OUT}/workspace-publication-package.json")" \
  --arg qa_state "$(jq -r '.continuity.qa_state' "${OUT}/workspace-publication-package.json")" \
  --arg technical_deposit_state "$(jq -r '.package.technical_deposit_state' "${OUT}/workspace-publication-package.json")" \
  --arg readiness_state "$(jq -r '.package.readiness_state' "${OUT}/workspace-publication-package.json")" \
  --arg managed_attach_state "$(jq -r '.package.managed_attach_state' "${OUT}/workspace-publication-package.json")" \
  --arg stable_attach_alias "$(jq -r '.package.stable_attach_alias' "${OUT}/workspace-publication-package.json")" \
  --argjson claim_count "$(jq '.continuity.claim_count' "${OUT}/workspace-publication-package.json")" \
  --argjson technical_blocker_count "$(jq '.continuity.technical_blocker_count' "${OUT}/workspace-publication-package.json")" \
  --argjson ro_crate_payload_count "$(jq '.continuity.ro_crate_payload_count' "${OUT}/workspace-publication-package.json")" \
  --argjson restart_recovered_session "$(
    jq -n \
      --arg pre "$(jq -r '.package.session_id' "${OUT}/workspace-publication-package.json")" \
      --arg post "$(jq -r '.package.session_id' "${OUT}/workspace-publication-package-after-restart.json")" \
      '$pre == $post'
  )" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    campaign_id: $campaign_id,
    source_subagent_id: $source_subagent_id,
    package_id: $package_id,
    qa_state: $qa_state,
    technical_deposit_state: $technical_deposit_state,
    readiness_state: $readiness_state,
    managed_attach_state: $managed_attach_state,
    stable_attach_alias: $stable_attach_alias,
    claim_count: $claim_count,
    technical_blocker_count: $technical_blocker_count,
    ro_crate_payload_count: $ro_crate_payload_count,
    restart_recovered_session: $restart_recovered_session
  }' > "${OUT}/smoke.json"

capture_cluster_health
printf '[OK] deposit-ready publication package smoke completed\n'
