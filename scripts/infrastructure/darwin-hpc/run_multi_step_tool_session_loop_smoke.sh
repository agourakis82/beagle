#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18107}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/multi-step-tool-session-loop}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b183-multi-step-${STAMP}}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b183-multi-step-${STAMP}-seed}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
TOOL_RETURN_LEDGER_PATH="${TOOL_RETURN_LEDGER_PATH:-/var/lib/beagle/workspace-plane/tool_return_events.jsonl}"
DARWIN_SOURCE_FILE="${DARWIN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_tool_return.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B183_MULTI_STEP_TOOL_SESSION_LOOP.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B183_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B183_KNOWN_LIMITS.md}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/tool-session-step.json}"

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

rollout_service() {
  local restart_log="$1"
  local rollout_log="$2"

  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${rollout_log}"
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

capture_tool_return_ledger_tail() {
  local pod_name=""
  pod_name="$(${KUBECTL} -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=beagle-core -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | tail -n 1)"
  if [[ -z "${pod_name}" ]]; then
    : > "${OUT}/tool-return-ledger-tail.jsonl"
    return 0
  fi

  ${KUBECTL} -n "${NAMESPACE}" exec "${pod_name}" -- sh -lc "if [ -f '${TOOL_RETURN_LEDGER_PATH}' ]; then tail -n 40 '${TOOL_RETURN_LEDGER_PATH}'; fi" \
    > "${OUT}/tool-return-ledger-tail.jsonl"
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

TOOL_RETURN_SOURCE_PRESENT=0
MULTI_STEP_TEST_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
CONTRACT_PRESENT=0

if rg -q "tool_return_events.jsonl|WorkstreamToolReturnPayload|apply_workstream_tool_return" "${DARWIN_SOURCE_FILE}"; then
  TOOL_RETURN_SOURCE_PRESENT=1
fi
if rg -q "apply_tool_return_supports_ordered_multi_step_session_loop" "${DARWIN_SOURCE_FILE}"; then
  MULTI_STEP_TEST_PRESENT=1
fi
if rg -q "tool_return_path|tool-return" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "workstream_tool_return_handler|/tool-return|workstream_tool_return_error" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if [[ -s "${DOC_FILE}" ]]; then
  DOC_PRESENT=1
fi
if [[ -s "${GO_NO_GO_FILE}" ]]; then
  GO_NO_GO_PRESENT=1
fi
if [[ -s "${KNOWN_LIMITS_FILE}" ]]; then
  KNOWN_LIMITS_PRESENT=1
fi
if [[ -s "${CONTRACT_FILE}" ]]; then
  CONTRACT_PRESENT=1
fi

jq -nc \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --argjson tool_return_source_present "${TOOL_RETURN_SOURCE_PRESENT}" \
  --argjson multi_step_test_present "${MULTI_STEP_TEST_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_repo: $expected_repo,
    expected_branch: $expected_branch,
    tool_return_source_present: $tool_return_source_present,
    multi_step_test_present: $multi_step_test_present,
    cockpit_source_present: $cockpit_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    contract_present: $contract_present
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
SEED_PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/seed-pilot.json")"
if [[ -z "${SEED_SESSION_ID}" || "${SEED_SESSION_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing session_id" >&2
  exit 1
fi
if [[ -z "${SEED_PUBLISHED_RESULT_JOB_ID}" || "${SEED_PUBLISHED_RESULT_JOB_ID}" == "null" ]]; then
  echo "[FAIL] seed-pilot.json missing published_result.job_id" >&2
  exit 1
fi
echo "${SEED_SESSION_ID}" > "${OUT}/seed-session-id.txt"
echo "${SEED_PUBLISHED_RESULT_JOB_ID}" > "${OUT}/seed-published-result-job-id.txt"

curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-before.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/cursor" "${OUT}/tool-cursor.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/claude-code" "${OUT}/tool-claude-code.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/codex" "${OUT}/tool-codex.json"

cat > "${OUT}/step-sequence.json" <<EOF
{
  "steps": [
    {
      "step_id": "step-1",
      "tool": "codex",
      "action_type": "implementation",
      "summary": "B183 step 1 implementation for ${WORKSPACE_ID}",
      "memory_text": "B183 multi-step tool session ${WORKSPACE_ID} ${SEED_SESSION_ID} step 1 codex implementation",
      "handoff_patch": "Proceed from implementation to analysis for ${WORKSPACE_ID}.",
      "result_refs": [
        "result:${SEED_PUBLISHED_RESULT_JOB_ID}"
      ],
      "repo_refs": {
        "branch": "${EXPECTED_BRANCH}",
        "commit": "b183-step-1-${STAMP}",
        "paths": [
          "crates/beagle-darwin/src/workstream_tool_return.rs"
        ]
      }
    },
    {
      "step_id": "step-2",
      "tool": "claude-code",
      "action_type": "analysis",
      "summary": "B183 step 2 analysis for ${WORKSPACE_ID}",
      "memory_text": "B183 multi-step tool session ${WORKSPACE_ID} ${SEED_SESSION_ID} step 2 claude-code analysis",
      "handoff_patch": "Use the analysis to drive the final note for ${WORKSPACE_ID}.",
      "result_refs": [
        "result:${SEED_PUBLISHED_RESULT_JOB_ID}"
      ],
      "repo_refs": {
        "branch": "${EXPECTED_BRANCH}",
        "commit": "b183-step-2-${STAMP}",
        "paths": [
          "apps/beagle-monorepo/src/http_darwin_hpc.rs"
        ]
      }
    },
    {
      "step_id": "step-3",
      "tool": "cursor",
      "action_type": "note",
      "summary": "B183 step 3 final note for ${WORKSPACE_ID}",
      "memory_text": "B183 multi-step tool session ${WORKSPACE_ID} ${SEED_SESSION_ID} step 3 cursor note",
      "handoff_patch": "Review the final multi-step tool session coherence for ${WORKSPACE_ID}.",
      "result_refs": [
        "result:${SEED_PUBLISHED_RESULT_JOB_ID}"
      ],
      "repo_refs": {
        "branch": "${EXPECTED_BRANCH}",
        "commit": "b183-step-3-${STAMP}",
        "paths": [
          "docs/darwin/hpc/B183_MULTI_STEP_TOOL_SESSION_LOOP.md"
        ]
      }
    }
  ]
}
EOF

STEP_COUNT="$(jq -r '.steps | length' "${OUT}/step-sequence.json")"
for step_index in $(seq 0 $((STEP_COUNT - 1))); do
  step_num=$((step_index + 1))

  jq \
    --arg workstream_id "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SEED_SESSION_ID}" \
    ".steps[${step_index}] + {workstream_id: \$workstream_id, workspace_id: \$workspace_id, session_id: \$session_id}" \
    "${OUT}/step-sequence.json" \
    > "${OUT}/step-${step_num}-payload.json"

  curl_json POST \
    "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-return" \
    "${OUT}/step-${step_num}-response.json" \
    "${OUT}/step-${step_num}-payload.json"

  curl_json GET \
    "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" \
    "${OUT}/context-packet-after-step-${step_num}.json"
done

cat > "${OUT}/memory-query-request.json" <<EOF
{
  "query": "B183 multi-step tool session ${WORKSPACE_ID} ${SEED_SESSION_ID}",
  "limit": 10,
  "tags": [
    "${EXPECTED_WORKSTREAM}",
    "tool-return"
  ],
  "include_recent_physio": true
}
EOF

curl_json POST "/api/memory/query" "${OUT}/memory-query-after-step-3.json" "${OUT}/memory-query-request.json"
stop_port_forward

rollout_service "${OUT}/restart-for-recovery.txt" "${OUT}/recovery-rollout.log"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/context-packet" "${OUT}/context-packet-after-restart.json"
stop_port_forward

capture_tool_return_ledger_tail
capture_cluster_health

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --slurpfile sequence "${OUT}/step-sequence.json" \
  --slurpfile step1 "${OUT}/step-1-response.json" \
  --slurpfile step2 "${OUT}/step-2-response.json" \
  --slurpfile step3 "${OUT}/step-3-response.json" \
  --slurpfile packet_step3 "${OUT}/context-packet-after-step-3.json" \
  --slurpfile memory_query "${OUT}/memory-query-after-step-3.json" \
  --slurpfile bootstrap_after_restart "${OUT}/bootstrap-after-restart.json" \
  '{
    status: "ok",
    workspace_id: $workspace_id,
    session_id: $session_id,
    expected_workstream: $expected_workstream,
    step_count: (($sequence[0].steps // []) | length),
    tools: (($sequence[0].steps // []) | map(.tool)),
    action_types: (($sequence[0].steps // []) | map(.action_type)),
    final_handoff: ($packet_step3[0].packet.handoff.last_handoff // ""),
    step_return_ids: [
      ($step1[0].return_id // null),
      ($step2[0].return_id // null),
      ($step3[0].return_id // null)
    ],
    memory_hits_after_step_3: (($packet_step3[0].packet.memory_hits // []) | length),
    memory_query_sources: (($memory_query[0].highlights // []) | map(.source) | unique),
    restart_recovered_session: ($bootstrap_after_restart[0].recovered_session // false)
  }' > "${OUT}/smoke.json"

echo "[OK] multi-step tool session loop smoke completed"
