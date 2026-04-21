#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-jats-assembly}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18451}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18271}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_SECTION_PROFILE="${EXPECTED_SECTION_PROFILE:-jats-1.4-ready}"
ASSEMBLY_SOURCE_FILE="${ASSEMBLY_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_manuscript_assembly.rs}"
MANUSCRIPT_HANDOFF_SOURCE_FILE="${MANUSCRIPT_HANDOFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_manuscript_handoff.rs}"
MANUSCRIPT_PACK_SOURCE_FILE="${MANUSCRIPT_PACK_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/manuscript_pack.rs}"
REVIEW_BUNDLE_SOURCE_FILE="${REVIEW_BUNDLE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/review_bundle.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-manuscript-assembly-schema.yaml}"
JATS_CONTRACT_FILE="${JATS_CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/jats-manuscript-pack-schema.yaml}"
SECTION_MAP_FILE="${SECTION_MAP_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-section-map.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B212_JATS_READY_MANUSCRIPT_ASSEMBLY_IN_THE_MANUSCRIPT_SUBAGENT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B212_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B212_KNOWN_LIMITS.md}"
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
  # shellcheck disable=SC2086
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

ASSEMBLY_SOURCE_PRESENT=0
MANUSCRIPT_HANDOFF_SOURCE_PRESENT=0
MANUSCRIPT_PACK_SOURCE_PRESENT=0
REVIEW_BUNDLE_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
CONTRACT_PRESENT=0
JATS_CONTRACT_PRESENT=0
SECTION_MAP_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "workspace-manuscript-assembly|record_workspace_manuscript_assembly|read_workspace_manuscript_assembly" "${ASSEMBLY_SOURCE_FILE}"; then
  ASSEMBLY_SOURCE_PRESENT=1
fi
if rg -q "workspace-manuscript-handoff|record_workspace_manuscript_handoff|read_workspace_manuscript_handoff" "${MANUSCRIPT_HANDOFF_SOURCE_FILE}"; then
  MANUSCRIPT_HANDOFF_SOURCE_PRESENT=1
fi
if rg -q "JatsManuscriptPack|build_campaign_jats_manuscript_pack|jats_xml" "${MANUSCRIPT_PACK_SOURCE_FILE}"; then
  MANUSCRIPT_PACK_SOURCE_PRESENT=1
fi
if rg -q "build_campaign_review_bundle|ReviewBundle" "${REVIEW_BUNDLE_SOURCE_FILE}"; then
  REVIEW_BUNDLE_SOURCE_PRESENT=1
fi
if rg -q "workspace-manuscript-assembly" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if [[ -f "${CONTRACT_FILE}" ]]; then
  CONTRACT_PRESENT=1
fi
if [[ -f "${JATS_CONTRACT_FILE}" ]]; then
  JATS_CONTRACT_PRESENT=1
fi
if [[ -f "${SECTION_MAP_FILE}" ]]; then
  SECTION_MAP_PRESENT=1
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
  --arg expected_section_profile "${EXPECTED_SECTION_PROFILE}" \
  --argjson assembly_source_present "${ASSEMBLY_SOURCE_PRESENT}" \
  --argjson manuscript_handoff_source_present "${MANUSCRIPT_HANDOFF_SOURCE_PRESENT}" \
  --argjson manuscript_pack_source_present "${MANUSCRIPT_PACK_SOURCE_PRESENT}" \
  --argjson review_bundle_source_present "${REVIEW_BUNDLE_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson jats_contract_present "${JATS_CONTRACT_PRESENT}" \
  --argjson section_map_present "${SECTION_MAP_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_campaign: $expected_campaign,
    expected_workstream: $expected_workstream,
    expected_section_profile: $expected_section_profile,
    assembly_source_present: $assembly_source_present,
    manuscript_handoff_source_present: $manuscript_handoff_source_present,
    manuscript_pack_source_present: $manuscript_pack_source_present,
    review_bundle_source_present: $review_bundle_source_present,
    http_source_present: $http_source_present,
    contract_present: $contract_present,
    jats_contract_present: $jats_contract_present,
    section_map_present: $section_map_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
WORKSTREAM_URL="${BASE_URL}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health.txt"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-subagent-list" \
  > "${OUT}/workspace-subagent-list.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-subagent-route?tool_id=claude-code&work_mode=manuscript" \
  > "${OUT}/route-manuscript.json"

cat > "${OUT}/subagent-handoff-request.json" <<'EOF'
{
  "source_subagent_id": "core",
  "target_subagent_id": "experiments",
  "requested_work_mode": "analysis",
  "requested_tool_id": "claude-code",
  "intent": "analysis",
  "summary": "Shift the current canonical session into experiments review with the same handoff and last result."
}
EOF

curl -fsS \
  -X POST \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  --data @"${OUT}/subagent-handoff-request.json" \
  "${WORKSTREAM_URL}/workspace-subagent-handoff" \
  > "${OUT}/handoff-core-to-experiments.json"

cat > "${OUT}/manuscript-handoff-request.json" <<'EOF'
{
  "source_subagent_id": "experiments",
  "requested_work_mode": "manuscript",
  "requested_tool_id": "claude-code",
  "intent": "manuscript",
  "summary": "Carry the bounded experiment evidence into manuscript-oriented campaign work without minting a new session.",
  "manuscript_goal": "Prepare the canonical Expedition 002 manuscript surface with coherent claims, evidence, and discussion continuity."
}
EOF

curl -fsS \
  -X POST \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  --data @"${OUT}/manuscript-handoff-request.json" \
  "${WORKSTREAM_URL}/workspace-manuscript-handoff" \
  > "${OUT}/workspace-manuscript-handoff-post.json"

cat > "${OUT}/manuscript-assembly-request.json" <<EOF
{
  "source_subagent_id": "manuscript",
  "requested_tool_id": "claude-code",
  "section_profile": "${EXPECTED_SECTION_PROFILE}",
  "intent": "editorial-assembly",
  "summary": "Freeze the claim/evidence/manuscript context into a JATS-ready editorial artifact inside the manuscript subagent.",
  "assembly_goal": "Keep claims, evidence, provenance, and editorial sections explicitly linked without minting a new workspace session."
}
EOF

curl -fsS \
  -X POST \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  --data @"${OUT}/manuscript-assembly-request.json" \
  "${WORKSTREAM_URL}/workspace-manuscript-assembly" \
  > "${OUT}/workspace-manuscript-assembly-post.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-manuscript-assembly" \
  > "${OUT}/workspace-manuscript-assembly.json"

CAMPAIGN_ID="$(jq -r '.assembly.campaign_id' "${OUT}/workspace-manuscript-assembly-post.json")"
if [[ -z "${CAMPAIGN_ID}" || "${CAMPAIGN_ID}" == "null" ]]; then
  echo "[FAIL] manuscript assembly did not expose campaign_id" >&2
  exit 1
fi
CAMPAIGN_URL="${BASE_URL}/api/darwin/campaigns/${CAMPAIGN_ID}"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${CAMPAIGN_URL}/context-packet" \
  > "${OUT}/campaign-context-packet.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${CAMPAIGN_URL}/evidence-pack" \
  > "${OUT}/campaign-evidence-pack.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${CAMPAIGN_URL}/claims" \
  > "${OUT}/campaign-claims.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${CAMPAIGN_URL}/manuscript-pack" \
  > "${OUT}/campaign-manuscript-pack.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${CAMPAIGN_URL}/review-bundle" \
  > "${OUT}/campaign-review-bundle.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${CAMPAIGN_URL}/jats-manuscript-pack" \
  > "${OUT}/campaign-jats-manuscript-pack.json"

jq -r '.pack.jats_xml' "${OUT}/campaign-jats-manuscript-pack.json" > "${OUT}/jats-article.xml"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context.json"
exec_workspace_file "${CONTEXT_ENV_FILE}" "${OUT}/workspace-context.env"
exec_workspace_file "/workspace/beagle/.beagle/context/subagents/manuscript.env" "${OUT}/manuscript.env"
exec_workspace_command '. /workspace/beagle/.beagle/context/subagents/core.env && cd /workspace/beagle && printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${BEAGLE_WORKSTREAM_ID}" "${BEAGLE_WORKSPACE_ID}" "${BEAGLE_SESSION_ID}" "${BEAGLE_SUBAGENT_ID}" "${BEAGLE_SUBAGENT_ROLE_TAG:-}" "$(pwd)"' "${OUT}/core-identity.txt"
exec_workspace_command '. /workspace/beagle/.beagle/context/subagents/experiments.env && cd /workspace/beagle/crates/beagle-experiments && printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${BEAGLE_WORKSTREAM_ID}" "${BEAGLE_WORKSPACE_ID}" "${BEAGLE_SESSION_ID}" "${BEAGLE_SUBAGENT_ID}" "${BEAGLE_SUBAGENT_ROLE_TAG:-}" "$(pwd)"' "${OUT}/experiments-identity.txt"
exec_workspace_command '. /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${BEAGLE_WORKSTREAM_ID}" "${BEAGLE_WORKSPACE_ID}" "${BEAGLE_SESSION_ID}" "${BEAGLE_SUBAGENT_ID}" "${BEAGLE_SUBAGENT_ROLE_TAG:-}" "$(pwd)"' "${OUT}/manuscript-identity.txt"

stop_port_forward WORKSPACE_PF_PID
rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/workspace-restart.txt" "${OUT}/workspace-rollout.txt"
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward-after-restart.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/workspace-health-after-restart.txt"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-manuscript-assembly" \
  > "${OUT}/workspace-manuscript-assembly-after-restart.json"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context-after-restart.json"
exec_workspace_command '. /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${BEAGLE_WORKSTREAM_ID}" "${BEAGLE_WORKSPACE_ID}" "${BEAGLE_SESSION_ID}" "${BEAGLE_SUBAGENT_ID}" "${BEAGLE_SUBAGENT_ROLE_TAG:-}" "$(pwd)"' "${OUT}/manuscript-identity-after-restart.txt"

capture_cluster_health

jq -nc \
  --arg expected_section_profile "${EXPECTED_SECTION_PROFILE}" \
  --slurpfile route "${OUT}/route-manuscript.json" \
  --slurpfile handoff "${OUT}/workspace-manuscript-handoff-post.json" \
  --slurpfile post "${OUT}/workspace-manuscript-assembly-post.json" \
  --slurpfile restart "${OUT}/workspace-manuscript-assembly-after-restart.json" \
  '{
    phase: "B21.2",
    workstream_id: $post[0].assembly.workstream_id,
    workspace_id: $post[0].assembly.workspace_id,
    session_id: $post[0].assembly.session_id,
    campaign_id: $post[0].assembly.campaign_id,
    source_subagent_id: $post[0].assembly.source_subagent_id,
    upstream_manuscript_handoff_id: $post[0].assembly.upstream_manuscript_handoff_id,
    route_selected_subagent: $route[0].route.selection.selected_subagent_id,
    claim_count: $post[0].continuity.claim_count,
    section_count: $post[0].continuity.section_count,
    jats_profile: $post[0].continuity.jats_profile,
    readiness_state: $post[0].continuity.readiness_state,
    managed_attach_state: $post[0].assembly.managed_attach_state,
    stable_attach_alias: $post[0].assembly.stable_attach_alias,
    restart_recovered_session: (
      $restart[0].assembly.assembly_id == $post[0].assembly.assembly_id and
      $restart[0].assembly.session_id == $post[0].assembly.session_id and
      $restart[0].assembly.campaign_id == $post[0].assembly.campaign_id and
      $restart[0].continuity.jats_profile == $expected_section_profile and
      $handoff[0].manuscript_handoff.manuscript_handoff_id == $post[0].assembly.upstream_manuscript_handoff_id
    )
  }' > "${OUT}/smoke.json"

echo "[OK] manuscript jats assembly smoke completed"
