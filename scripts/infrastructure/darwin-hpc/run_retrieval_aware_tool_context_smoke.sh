#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/retrieval-aware-tool-context}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18476}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_WORKSPACE="${EXPECTED_WORKSPACE:-beagle-cluster-pilot}"
EXPECTED_SESSION="${EXPECTED_SESSION:-ws-cluster-workspace-habitat}"
EXPECTED_DENSE_BACKEND="${EXPECTED_DENSE_BACKEND:-voyage-4-large}"
EXPECTED_SPARSE_BACKEND="${EXPECTED_SPARSE_BACKEND:-local-lexical}"
WORKSTREAM_CONTEXT_SOURCE_FILE="${WORKSTREAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
PROGRAM_CONTEXT_SOURCE_FILE="${PROGRAM_CONTEXT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/program_context_packet.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
ROUTING_SOURCE_FILE="${ROUTING_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_routing.rs}"
HANDOFF_SOURCE_FILE="${HANDOFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_subagent_handoff.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B224_RETRIEVAL_AWARE_TOOL_CONTEXT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B224_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B224_KNOWN_LIMITS.md}"
QUERY_TEXT="${QUERY_TEXT:-beagle-darwin-hpc-governance agourakis82/beagle feat/darwin-hpc-governance manuscript claims evidence jats editorial}"
MANUSCRIPT_MARKER="${MANUSCRIPT_MARKER:-B224 retrieval-aware tool context canonical manuscript memory}"
SUPPORT_MARKER="${SUPPORT_MARKER:-B224 retrieval-aware tool context supporting editorial memory}"

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
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"

WORKSTREAM_CONTEXT_SOURCE_PRESENT=0
PROGRAM_CONTEXT_SOURCE_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
ROUTING_SOURCE_PRESENT=0
HANDOFF_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "pub retrieval_context: Option<WorkstreamContextPacketRetrievalContext>" "${WORKSTREAM_CONTEXT_SOURCE_FILE}"; then
  WORKSTREAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "pub retrieval_context: Option<ProgramContextPacketRetrievalContext>" "${PROGRAM_CONTEXT_SOURCE_FILE}"; then
  PROGRAM_CONTEXT_SOURCE_PRESENT=1
fi
if rg -q "retrieval_context_present|retrieval_launch_reason|retrieval_recommended_subagent_id" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "retrieval-context|select_role_from_retrieval_context" "${ROUTING_SOURCE_FILE}"; then
  ROUTING_SOURCE_PRESENT=1
fi
if rg -q "retrieval_context_present|retrieval_memory_ids|retrieval_suggested_subagent_id" "${HANDOFF_SOURCE_FILE}"; then
  HANDOFF_SOURCE_PRESENT=1
fi
if rg -q "context_packet_retrieval_context_from_result|retrieval_guidance_from_hits" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1

jq -nc \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_workspace "${EXPECTED_WORKSPACE}" \
  --arg expected_session "${EXPECTED_SESSION}" \
  --arg expected_dense_backend "${EXPECTED_DENSE_BACKEND}" \
  --arg expected_sparse_backend "${EXPECTED_SPARSE_BACKEND}" \
  --argjson workstream_context_source_present "${WORKSTREAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson program_context_source_present "${PROGRAM_CONTEXT_SOURCE_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson routing_source_present "${ROUTING_SOURCE_PRESENT}" \
  --argjson handoff_source_present "${HANDOFF_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_campaign: $expected_campaign,
    expected_program: $expected_program,
    expected_workspace: $expected_workspace,
    expected_session: $expected_session,
    expected_dense_backend: $expected_dense_backend,
    expected_sparse_backend: $expected_sparse_backend,
    workstream_context_source_present: $workstream_context_source_present,
    program_context_source_present: $program_context_source_present,
    cockpit_source_present: $cockpit_source_present,
    routing_source_present: $routing_source_present,
    handoff_source_present: $handoff_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
WORKSTREAM_URL="${BASE_URL}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}"

jq -n \
  --arg source "claude-code" \
  --arg conversation_id "b224-retrieval-aware-manuscript" \
  --arg role "assistant" \
  --arg text "${MANUSCRIPT_MARKER}. ${QUERY_TEXT}. resume from managed launch operator_cpu_loop manuscript editorial claim evidence review bundle jats crossref datacite ${EXPECTED_CAMPAIGN} ${EXPECTED_PROGRAM}." \
  --arg domain "darwin-hpc" \
  --arg provider "claude-code" \
  --arg model "sonnet" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 1,
    role: $role,
    text: $text,
    tags: [$workstream_id, "b224", "manuscript", "editorial", "claim", "jats"],
    domain: $domain,
    provider: $provider,
    model: $model,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b224-retrieval-aware-tool-context"],
    claim_refs: ["claim:b224-retrieval-aware-tool-context"]
  }' > "${OUT}/manuscript-memory-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/manuscript-memory-ingest.json" \
  "${BASE_URL}/api/memory/ingest_chat" \
  > "${OUT}/manuscript-memory-ingest-response.json"

jq -n \
  --arg source "claude-code" \
  --arg conversation_id "b224-retrieval-aware-manuscript" \
  --arg role "assistant" \
  --arg text "${SUPPORT_MARKER}. ${QUERY_TEXT}. manuscript assembly publication package claims evidence editorial review bundle." \
  --arg domain "darwin-hpc" \
  --arg provider "claude-code" \
  --arg model "sonnet" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  '{
    source: $source,
    conversation_id: $conversation_id,
    turn_index: 2,
    role: $role,
    text: $text,
    tags: [$workstream_id, "b224", "manuscript", "editorial", "review"],
    domain: $domain,
    provider: $provider,
    model: $model,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    result_refs: ["result:b224-retrieval-aware-tool-context-support"],
    claim_refs: ["claim:b224-retrieval-aware-tool-context-support"]
  }' > "${OUT}/support-memory-ingest.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/support-memory-ingest.json" \
  "${BASE_URL}/api/memory/ingest_chat" \
  > "${OUT}/support-memory-ingest-response.json"

jq -n \
  --arg query_text "${QUERY_TEXT}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg session_id "${EXPECTED_SESSION}" \
  '{
    query_text: $query_text,
    top_k: 3,
    dense_enabled: true,
    sparse_enabled: true,
    dense_weight: 0.65,
    sparse_weight: 0.35,
    filters: {
      workstream_id: $workstream_id,
      campaign_id: $campaign_id,
      session_id: $session_id,
      source: "claude-code",
      role: "assistant",
      domain: "darwin-hpc",
      tags: [$workstream_id, "b224"]
    },
    rerank_hint: "b224-retrieval-aware-tool-context"
  }' > "${OUT}/retrieval-query.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data @"${OUT}/retrieval-query.json" \
  "${BASE_URL}/api/memory/retrieval/query" \
  > "${OUT}/retrieval-result.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/workstream-context-packet.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${BASE_URL}/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" \
  > "${OUT}/program-context-packet.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${BASE_URL}/api/darwin/campaigns/${EXPECTED_CAMPAIGN}/context-packet" \
  > "${OUT}/campaign-context-packet.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-launch-resume" \
  > "${OUT}/workspace-launch-resume.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/tool-dock/claude-code" \
  > "${OUT}/tool-claude-code.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-subagent-route?tool_id=claude-code" \
  > "${OUT}/workspace-subagent-route.json"

cat > "${OUT}/subagent-handoff-request.json" <<'EOF'
{
  "source_subagent_id": "experiments",
  "target_subagent_id": "manuscript",
  "requested_tool_id": "claude-code",
  "intent": "manuscript-continuity",
  "summary": "Carry the retrieval-ranked claims and evidence context into manuscript authoring without changing Beagle-owned identity."
}
EOF

curl -fsS \
  -X POST \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  -H "Content-Type: application/json" \
  --data @"${OUT}/subagent-handoff-request.json" \
  "${WORKSTREAM_URL}/workspace-subagent-handoff" \
  > "${OUT}/workspace-subagent-handoff-post.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-subagent-handoff" \
  > "${OUT}/workspace-subagent-handoff.json"

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/beagle-core-rollout-restart.log" "${OUT}/beagle-core-rollout-status.log"
stop_port_forward BEAGLE_PF_PID
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID
BASE_URL="http://127.0.0.1:${BEAGLE_LOCAL_PORT}"
WORKSTREAM_URL="${BASE_URL}/api/darwin/workstreams/${EXPECTED_WORKSTREAM}"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/context-packet" \
  > "${OUT}/workstream-context-packet-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${BASE_URL}/api/darwin/programs/${EXPECTED_PROGRAM}/context-packet" \
  > "${OUT}/program-context-packet-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-launch-resume" \
  > "${OUT}/workspace-launch-resume-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/tool-dock/claude-code" \
  > "${OUT}/tool-claude-code-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-subagent-route?tool_id=claude-code" \
  > "${OUT}/workspace-subagent-route-after-restart.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "${WORKSTREAM_URL}/workspace-subagent-handoff" \
  > "${OUT}/workspace-subagent-handoff-after-restart.json"

jq -n \
  --arg phase "B22.4" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg campaign_id "${EXPECTED_CAMPAIGN}" \
  --arg program_id "${EXPECTED_PROGRAM}" \
  --arg workspace_id "${EXPECTED_WORKSPACE}" \
  --arg session_id "${EXPECTED_SESSION}" \
  --slurpfile retrieval "${OUT}/retrieval-result.json" \
  --slurpfile workstream "${OUT}/workstream-context-packet.json" \
  --slurpfile workstream_restart "${OUT}/workstream-context-packet-after-restart.json" \
  --slurpfile program_packet "${OUT}/program-context-packet.json" \
  --slurpfile launch_resume "${OUT}/workspace-launch-resume.json" \
  --slurpfile tool_launch "${OUT}/tool-claude-code.json" \
  --slurpfile route "${OUT}/workspace-subagent-route.json" \
  --slurpfile route_restart "${OUT}/workspace-subagent-route-after-restart.json" \
  --slurpfile handoff "${OUT}/workspace-subagent-handoff-post.json" \
  --slurpfile handoff_restart "${OUT}/workspace-subagent-handoff-after-restart.json" \
  '{
    phase: $phase,
    workstream_id: $workstream_id,
    campaign_id: $campaign_id,
    program_id: $program_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    retrieval_hit_count: ($retrieval[0].hits | length),
    retrieval_top_memory_ids: ($retrieval[0].hits | map(.point.payload.memory_id)),
    workstream_retrieval_present: ($workstream[0].packet.retrieval_context != null),
    program_retrieval_present: ($program_packet[0].packet.retrieval_context != null),
    launch_resume_retrieval_present: ($launch_resume[0].context_packet.retrieval_context != null),
    tool_retrieval_context_present: $tool_launch[0].tool.retrieval_context_present,
    tool_recommended_subagent: $tool_launch[0].tool.recommended_subagent_id,
    route_selection_source: $route[0].route.selection.selection_source,
    route_selected_subagent: $route[0].route.selection.selected_subagent_id,
    handoff_retrieval_context_present: $handoff[0].propagation.retrieval_context_present,
    handoff_retrieval_suggested_subagent: $handoff[0].propagation.retrieval_suggested_subagent_id,
    context_packet_contains_top_memory: (
      ($workstream[0].packet.retrieval_context.top_memory_ids // []) as $ids
      | any($retrieval[0].hits[]; (.point.payload.memory_id as $id | $ids | index($id)))
    ),
    restart_recovered_session: (
      $workstream[0].packet.session_id == $workstream_restart[0].packet.session_id and
      $route[0].route.selection.selected_subagent_id == $route_restart[0].route.selection.selected_subagent_id and
      $handoff[0].handoff.handoff_id == $handoff_restart[0].handoff.handoff_id
    )
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] retrieval-aware tool context smoke completed"
