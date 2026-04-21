#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18105}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/memory-aware-workstream-context-packet}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b181-context-packet-${STAMP}}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_GOVERNANCE_STATE="${EXPECTED_GOVERNANCE_STATE:-canonical}"
EXPECTED_RECOMMENDED_RECIPE_KIND="${EXPECTED_RECOMMENDED_RECIPE_KIND:-operator_cpu_loop}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b181-context-packet-${STAMP}-seed}"
EXPECTED_MEMORY_SOURCE="${EXPECTED_MEMORY_SOURCE:-codex}"
EXPECTED_MEMORY_DOMAIN="${EXPECTED_MEMORY_DOMAIN:-beagle-engine}"
EXPECTED_MEMORY_TAG="${EXPECTED_MEMORY_TAG:-context-packet}"
EXPECTED_PROVIDER="${EXPECTED_PROVIDER:-xai}"
EXPECTED_MODEL="${EXPECTED_MODEL:-grok-4-1-fast-reasoning}"
EXPECTED_HRV_AWARE="${EXPECTED_HRV_AWARE:-true}"
EXPECTED_SERENDIPITY_ENABLED="${EXPECTED_SERENDIPITY_ENABLED:-false}"
EXPECTED_TRIAD_ENABLED="${EXPECTED_TRIAD_ENABLED:-false}"
PHYSIO_SOURCE="${PHYSIO_SOURCE:-observer-smoke}"
PHYSIO_HR="${PHYSIO_HR:-74}"
PHYSIO_HRV_MS="${PHYSIO_HRV_MS:-58}"
PHYSIO_SPO2="${PHYSIO_SPO2:-98}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
CONTEXT_PACKET_SOURCE_FILE="${CONTEXT_PACKET_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_context_packet.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
MEMORY_SOURCE_FILE="${MEMORY_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_memory.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B181_MEMORY_AWARE_WORKSTREAM_CONTEXT_PACKETS.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B181_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B181_KNOWN_LIMITS.md}"

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

  if [[ -f /etc/kubernetes/admin.conf ]] && command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
    return 0
  fi

  printf '%s\n' kubectl
}

KUBECTL="$(resolve_kubectl)"
require "${KUBECTL%% *}"

resolve_operator_api_token() {
  if [[ -n "${OPERATOR_API_TOKEN}" ]]; then
    printf '%s\n' "${OPERATOR_API_TOKEN}"
    return 0
  fi

  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi

  if [[ -n "${encoded_token}" ]]; then
    printf '%s' "${encoded_token}" | base64 -d
    return 0
  fi

  echo "[FAIL] missing BEAGLE_OPERATOR_API_TOKEN/BEAGLE_API_TOKEN locally and in secret ${SECRET_NAME}" >&2
  exit 1
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

  echo "[FAIL] unable to find a free local port starting at ${LOCAL_PORT}" >&2
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
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

wait_for_health() {
  local port="$1"
  local target="$2"

  for _ in $(seq 1 20); do
    if curl -fsS \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" \
      > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before health became ready" >&2
      cat "${PF_LOG}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] Beagle health endpoint did not become ready on local port ${port}" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -o wide || true
    echo
    echo "## darwin-gateway"
    ${KUBECTL} -n darwin-platform get deploy,svc,pods -l app.kubernetes.io/name=darwin-hpc-gateway -o wide || true
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

rollout_service() {
  local restart_log="$1"
  local rollout_log="$2"

  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${rollout_log}"
}

curl_json() {
  local method="$1"
  local path="$2"
  local target="$3"
  local body="${4:-}"

  if [[ -n "${body}" ]]; then
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      -H 'Content-Type: application/json' \
      --data @"${body}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${LOCAL_PORT}${path}" \
      > "${target}"
  fi
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
mkdir -p "${OUT}"
LOCAL_PORT="$(choose_local_port)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_WORKSTREAM}" > "${OUT}/expected-workstream.txt"
echo "${EXPECTED_RECOMMENDED_RECIPE_KIND}" > "${OUT}/expected-recommended-recipe-kind.txt"
echo "${EXPECTED_MEMORY_SOURCE}" > "${OUT}/expected-memory-source.txt"
echo "${EXPECTED_PROVIDER}" > "${OUT}/expected-provider.txt"
echo "${EXPECTED_MODEL}" > "${OUT}/expected-model.txt"

CONTEXT_PACKET_SOURCE_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
MEMORY_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "get_workstream_context_packet|WorkstreamContextPacket|recommended_recipe" "${CONTEXT_PACKET_SOURCE_FILE}"; then
  CONTEXT_PACKET_SOURCE_PRESENT=1
fi
if rg -q "context_packet|context-packet|shared_context_fields" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/workstreams/:workstream_id/context-packet|resolve_workstream_context_packet" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if rg -q "latest_physio_snapshot|/api/memory/query|/api/memory/ingest_chat" "${MEMORY_SOURCE_FILE}"; then
  MEMORY_SOURCE_PRESENT=1
fi
[[ -s "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -s "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -s "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1

jq -nc \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_memory_source "${EXPECTED_MEMORY_SOURCE}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --argjson context_packet_source_present "${CONTEXT_PACKET_SOURCE_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson memory_source_present "${MEMORY_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_recommended_recipe_kind: $expected_recommended_recipe_kind,
    expected_memory_source: $expected_memory_source,
    expected_provider: $expected_provider,
    expected_model: $expected_model,
    context_packet_source_present: $context_packet_source_present,
    cockpit_source_present: $cockpit_source_present,
    http_source_present: $http_source_present,
    memory_source_present: $memory_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' \
  > "${OUT}/source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_service "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"

PF_LOG="${OUT}/port-forward.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-before.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-before.json"

cat > "${OUT}/seed-pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "profile_id": "${SEED_PROFILE_ID}",
  "run_label": "${SEED_RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF

curl_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/seed-pilot.json" "${OUT}/seed-pilot-request.json"
SEED_SESSION_ID="$(jq -r '.session_id' "${OUT}/seed-pilot.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/seed-pilot.json")"
if [[ -z "${SEED_SESSION_ID}" || "${SEED_SESSION_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing session_id" >&2
  exit 1
fi
if [[ -z "${PUBLISHED_RESULT_JOB_ID}" || "${PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${SEED_SESSION_ID}" > "${OUT}/seed-session-id.txt"
echo "${PUBLISHED_RESULT_JOB_ID}" > "${OUT}/seed-published-result-job-id.txt"

cat > "${OUT}/physio-request.json" <<EOF
{
  "source": "${PHYSIO_SOURCE}",
  "session_id": "${SEED_SESSION_ID}",
  "hr": ${PHYSIO_HR},
  "hrv_ms": ${PHYSIO_HRV_MS},
  "spo2": ${PHYSIO_SPO2}
}
EOF
curl_json POST "/api/observer/physio" "${OUT}/physio-ingest-response.json" "${OUT}/physio-request.json"
curl_json GET "/api/observer/physio/latest" "${OUT}/physio-attachment.json"

MEMORY_TEXT="Beagle context packet remembers ${EXPECTED_WORKSTREAM} on workspace ${WORKSPACE_ID} and session ${SEED_SESSION_ID}."
cat > "${OUT}/memory-ingest-request.json" <<EOF
{
  "source": "${EXPECTED_MEMORY_SOURCE}",
  "conversation_id": "${SEED_SESSION_ID}",
  "turn_index": 0,
  "role": "assistant",
  "text": "${MEMORY_TEXT}",
  "tags": ["${EXPECTED_WORKSTREAM}", "${EXPECTED_MEMORY_TAG}"],
  "domain": "${EXPECTED_MEMORY_DOMAIN}",
  "provider": "${EXPECTED_PROVIDER}",
  "model": "${EXPECTED_MODEL}",
  "experiment_flags": {
    "hrv_aware": ${EXPECTED_HRV_AWARE},
    "serendipity_enabled": ${EXPECTED_SERENDIPITY_ENABLED},
    "triad_enabled": ${EXPECTED_TRIAD_ENABLED}
  }
}
EOF
curl_json POST "/api/memory/ingest_chat" "${OUT}/ingest-response.json" "${OUT}/memory-ingest-request.json"

cat > "${OUT}/memory-query-request.json" <<EOF
{
  "query": "${WORKSPACE_ID} ${SEED_SESSION_ID} context packet",
  "limit": 3,
  "tags": ["${EXPECTED_WORKSTREAM}"],
  "include_recent_physio": true
}
EOF
curl_json POST "/api/memory/query" "${OUT}/query-response.json" "${OUT}/memory-query-request.json"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cockpit" "${OUT}/cockpit.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/cursor" "${OUT}/tool-cursor.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/claude-code" "${OUT}/tool-claude-code.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/codex" "${OUT}/tool-codex.json"
stop_port_forward

rollout_service "${OUT}/restart-for-recovery.txt" "${OUT}/recovery-rollout.log"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-after-restart.json"
stop_port_forward

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_memory_source "${EXPECTED_MEMORY_SOURCE}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" \
  --slurpfile packet "${OUT}/context-packet.json" \
  --slurpfile cockpit "${OUT}/cockpit.json" \
  --slurpfile cursor "${OUT}/tool-cursor.json" \
  --slurpfile claude "${OUT}/tool-claude-code.json" \
  --slurpfile codex "${OUT}/tool-codex.json" \
  --slurpfile restart "${OUT}/bootstrap-after-restart.json" \
  --slurpfile packet_after_restart "${OUT}/context-packet-after-restart.json" \
  --slurpfile query "${OUT}/query-response.json" \
  '{
    status: (
      if (
        ($packet[0].packet.workstream_id // "") == $expected_workstream
        and ($packet[0].packet.workspace_id // "") == $workspace_id
        and ($packet[0].packet.session_id // "") == $session_id
        and ($packet[0].packet.repo // "") == $expected_repo
        and ($packet[0].packet.branch // "") == $expected_branch
        and ($packet[0].packet.governance_state // "") == $expected_governance_state
        and ($packet[0].packet.handoff.handoff_present // false) == true
        and ($packet[0].packet.last_result.summary.job_id // null) == $published_result_job_id
        and ($packet[0].packet.last_successful_task.profile_id // "") == "cpu-batch-v1"
        and ($packet[0].packet.latest_physio.source // "") != ""
        and ($packet[0].packet.experiment_flags.provider // "") == $expected_provider
        and ($packet[0].packet.experiment_flags.model // "") == $expected_model
        and ($packet[0].packet.experiment_flags.hrv_aware // false) == true
        and ($packet[0].packet.recommended_recipe.kind // "") == $expected_recommended_recipe_kind
        and (($packet[0].packet.memory_hits | length) >= 1)
        and (($packet[0].packet.memory_hits[0].source // "") == $expected_memory_source)
        and ($cockpit[0].context_packet.workspace_id // "") == $workspace_id
        and ($cockpit[0].context_packet.session_id // "") == $session_id
        and ($cursor[0].context_packet.workspace_id // "") == $workspace_id
        and ($cursor[0].context_packet.session_id // "") == $session_id
        and ($claude[0].context_packet.workspace_id // "") == $workspace_id
        and ($claude[0].context_packet.session_id // "") == $session_id
        and ($codex[0].context_packet.workspace_id // "") == $workspace_id
        and ($codex[0].context_packet.session_id // "") == $session_id
        and ($cursor[0].tool.context_packet_path // "") == ("/api/darwin/workstreams/" + $expected_workstream + "/context-packet")
        and ($claude[0].tool.context_packet_path // "") == ("/api/darwin/workstreams/" + $expected_workstream + "/context-packet")
        and ($codex[0].tool.context_packet_path // "") == ("/api/darwin/workstreams/" + $expected_workstream + "/context-packet")
        and ($restart[0].workspace_id // "") == $workspace_id
        and ($restart[0].session_id // "") == $session_id
        and ($restart[0].recovered_session // false) == true
        and ($packet_after_restart[0].packet.workspace_id // "") == $workspace_id
        and ($packet_after_restart[0].packet.session_id // "") == $session_id
        and (($query[0].highlights | length) >= 1)
      ) then "ok" else "unexpected" end
    ),
    workspace_id: $workspace_id,
    session_id: $session_id,
    expected_workstream: $expected_workstream,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    expected_default_dev_plane: $expected_default_dev_plane,
    expected_vm_fallback_role: $expected_vm_fallback_role,
    expected_governance_state: $expected_governance_state,
    expected_recommended_recipe_kind: $expected_recommended_recipe_kind,
    packet_memory_hit_count: ($packet[0].packet.memory_hits | length),
    packet_latest_physio_source: ($packet[0].packet.latest_physio.source // ""),
    packet_experiment_provider: ($packet[0].packet.experiment_flags.provider // ""),
    packet_experiment_model: ($packet[0].packet.experiment_flags.model // ""),
    restart_recovered_session: ($restart[0].recovered_session // false)
  }' \
  > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] memory-aware workstream context packet smoke completed"
