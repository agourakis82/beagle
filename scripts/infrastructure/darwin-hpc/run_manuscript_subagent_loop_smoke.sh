#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/manuscript-subagent-loop}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18441}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18261}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
MANUSCRIPT_SOURCE_FILE="${MANUSCRIPT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_manuscript_handoff.rs}"
HANDOFF_SOURCE_FILE="${HANDOFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_handoff.rs}"
ROUTING_SOURCE_FILE="${ROUTING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_routing.rs}"
SUBAGENTS_SOURCE_FILE="${SUBAGENTS_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagents.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
K8S_CONFIGMAP_FILE="${K8S_CONFIGMAP_FILE:-${ROOT}/k8s/beagle-workspace/configmap.yaml}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-manuscript-handoff-schema.yaml}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B211_MANUSCRIPT_SUBAGENT_EVIDENCE_TO_MANUSCRIPT_LOOP.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B211_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B211_KNOWN_LIMITS.md}"
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

MANUSCRIPT_SOURCE_PRESENT=0
HANDOFF_SOURCE_PRESENT=0
ROUTING_SOURCE_PRESENT=0
SUBAGENTS_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
CONFIGMAP_PRESENT=0
CONTRACT_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "workspace-manuscript-handoff|record_workspace_manuscript_handoff|read_workspace_manuscript_handoff" "${MANUSCRIPT_SOURCE_FILE}"; then
  MANUSCRIPT_SOURCE_PRESENT=1
fi
if rg -q "workspace-subagent-handoff|record_workspace_subagent_handoff|read_workspace_subagent_handoff" "${HANDOFF_SOURCE_FILE}"; then
  HANDOFF_SOURCE_PRESENT=1
fi
if rg -q "workspace-subagent-route|selected_subagent_id|manuscript" "${ROUTING_SOURCE_FILE}"; then
  ROUTING_SOURCE_PRESENT=1
fi
if rg -q "manuscript|manuscript-authoring" "${SUBAGENTS_SOURCE_FILE}"; then
  SUBAGENTS_SOURCE_PRESENT=1
fi
if rg -q "workspace-manuscript-handoff" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if rg -q "manuscript.env|beagle-manuscript/devcontainer.json|manuscript-authoring" "${K8S_CONFIGMAP_FILE}"; then
  CONFIGMAP_PRESENT=1
fi
if [[ -f "${CONTRACT_FILE}" ]]; then
  CONTRACT_PRESENT=1
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
  --argjson manuscript_source_present "${MANUSCRIPT_SOURCE_PRESENT}" \
  --argjson handoff_source_present "${HANDOFF_SOURCE_PRESENT}" \
  --argjson routing_source_present "${ROUTING_SOURCE_PRESENT}" \
  --argjson subagents_source_present "${SUBAGENTS_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson configmap_present "${CONFIGMAP_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    manuscript_source_present: $manuscript_source_present,
    handoff_source_present: $handoff_source_present,
    routing_source_present: $routing_source_present,
    subagents_source_present: $subagents_source_present,
    http_source_present: $http_source_present,
    configmap_present: $configmap_present,
    contract_present: $contract_present,
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

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-manuscript-handoff" \
  > "${OUT}/workspace-manuscript-handoff.json"

CAMPAIGN_ID="$(jq -r '.manuscript_handoff.campaign_id' "${OUT}/workspace-manuscript-handoff-post.json")"
if [[ -z "${CAMPAIGN_ID}" || "${CAMPAIGN_ID}" == "null" ]]; then
  echo "[FAIL] manuscript handoff did not expose campaign_id" >&2
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

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context.json"
exec_workspace_file "${CONTEXT_ENV_FILE}" "${OUT}/workspace-context.env"
exec_workspace_file "/workspace/beagle/.beagle/context/subagents/experiments.env" "${OUT}/experiments.env"
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
  "${WORKSTREAM_URL}/workspace-manuscript-handoff" \
  > "${OUT}/workspace-manuscript-handoff-after-restart.json"

exec_workspace_file "${CONTEXT_PACKET_FILE}" "${OUT}/workspace-context-after-restart.json"
exec_workspace_command '. /workspace/beagle/.beagle/context/subagents/experiments.env && cd /workspace/beagle/crates/beagle-experiments && printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${BEAGLE_WORKSTREAM_ID}" "${BEAGLE_WORKSPACE_ID}" "${BEAGLE_SESSION_ID}" "${BEAGLE_SUBAGENT_ID}" "${BEAGLE_SUBAGENT_ROLE_TAG:-}" "$(pwd)"' "${OUT}/experiments-identity-after-restart.txt"
exec_workspace_command '. /workspace/beagle/.beagle/context/subagents/manuscript.env && cd /workspace/beagle/docs/darwin/hpc && printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${BEAGLE_WORKSTREAM_ID}" "${BEAGLE_WORKSPACE_ID}" "${BEAGLE_SESSION_ID}" "${BEAGLE_SUBAGENT_ID}" "${BEAGLE_SUBAGENT_ROLE_TAG:-}" "$(pwd)"' "${OUT}/manuscript-identity-after-restart.txt"

capture_cluster_health

jq -nc \
  --slurpfile route "${OUT}/route-manuscript.json" \
  --slurpfile upstream "${OUT}/handoff-core-to-experiments.json" \
  --slurpfile post "${OUT}/workspace-manuscript-handoff-post.json" \
  --slurpfile restart "${OUT}/workspace-manuscript-handoff-after-restart.json" \
  '{
    phase: "B21.1",
    workstream_id: $post[0].manuscript_handoff.workstream_id,
    workspace_id: $post[0].manuscript_handoff.workspace_id,
    session_id: $post[0].manuscript_handoff.session_id,
    campaign_id: $post[0].manuscript_handoff.campaign_id,
    source_subagent_id: $post[0].manuscript_handoff.source_subagent_id,
    target_subagent_id: $post[0].manuscript_handoff.target_subagent_id,
    upstream_handoff_id: $post[0].manuscript_handoff.upstream_handoff_id,
    manuscript_handoff_id: $post[0].manuscript_handoff.manuscript_handoff_id,
    target_selected_subagent: $route[0].route.selection.selected_subagent_id,
    claim_count: $post[0].continuity.claim_count,
    evidence_pack_ref: $post[0].manuscript_handoff.evidence_pack_ref,
    manuscript_pack_ref: $post[0].manuscript_handoff.manuscript_pack_ref,
    managed_attach_state: $post[0].manuscript_handoff.managed_attach_state,
    stable_attach_alias: $post[0].manuscript_handoff.stable_attach_alias,
    restart_recovered_session: ($restart[0].manuscript_handoff.manuscript_handoff_id == $post[0].manuscript_handoff.manuscript_handoff_id and $restart[0].manuscript_handoff.session_id == $post[0].manuscript_handoff.session_id and $restart[0].manuscript_handoff.campaign_id == $post[0].manuscript_handoff.campaign_id)
  }' > "${OUT}/smoke.json"

echo "[OK] manuscript subagent loop smoke completed"
