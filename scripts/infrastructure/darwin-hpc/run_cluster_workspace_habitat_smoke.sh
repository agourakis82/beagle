#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-beagle-workspace}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-beagle-workspace}"
WORKSPACE_CONTAINER_NAME="${WORKSPACE_CONTAINER_NAME:-workspace-ide}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18201}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18211}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/cluster-workspace-habitat}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-beagle-cluster-pilot}"
EXPECTED_SESSION_ID="${EXPECTED_SESSION_ID:-ws-cluster-workspace-habitat}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_REPO="${EXPECTED_REPO:-agourakis82/beagle}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-feat/darwin-hpc-governance}"
EXPECTED_IDE_KIND="${EXPECTED_IDE_KIND:-openvscode-server}"
EXPECTED_BROWSER_URL="${EXPECTED_BROWSER_URL:-http://beagle-workspace.beagle.svc.cluster.local:8080}"
EXPECTED_HEALTH_URL="${EXPECTED_HEALTH_URL:-http://beagle-workspace.beagle.svc.cluster.local:8080/}"
EXPECTED_HEALTH_PROBE_PATH="${EXPECTED_HEALTH_PROBE_PATH:-/}"
EXPECTED_WORKSPACE_ROOT="${EXPECTED_WORKSPACE_ROOT:-/workspace/beagle}"
EXPECTED_CONTEXT_PACKET_FILE="${EXPECTED_CONTEXT_PACKET_FILE:-/workspace/beagle/.beagle/context/current-context-packet.json}"
EXPECTED_CONTEXT_ENV_FILE="${EXPECTED_CONTEXT_ENV_FILE:-/workspace/beagle/.beagle/context/beagle-context.env}"
EXPECTED_DEFAULT_DEV_PLANE="${EXPECTED_DEFAULT_DEV_PLANE:-beagle-cluster}"
EXPECTED_VM_FALLBACK_ROLE="${EXPECTED_VM_FALLBACK_ROLE:-fallback-only}"
EXPECTED_GOVERNANCE_STATE="${EXPECTED_GOVERNANCE_STATE:-canonical}"
EXPECTED_LAST_TRANSITION="${EXPECTED_LAST_TRANSITION:-resume}"
EXPECTED_RECOMMENDED_RECIPE_KIND="${EXPECTED_RECOMMENDED_RECIPE_KIND:-operator_cpu_loop}"
EXPECTED_MEMORY_SOURCE="${EXPECTED_MEMORY_SOURCE:-codex}"
EXPECTED_MEMORY_DOMAIN="${EXPECTED_MEMORY_DOMAIN:-beagle-engine}"
EXPECTED_MEMORY_TAG="${EXPECTED_MEMORY_TAG:-workspace-habitat}"
EXPECTED_PROVIDER="${EXPECTED_PROVIDER:-xai}"
EXPECTED_MODEL="${EXPECTED_MODEL:-grok-4-1-fast-reasoning}"
PHYSIO_SOURCE="${PHYSIO_SOURCE:-observer-smoke}"
PHYSIO_HR="${PHYSIO_HR:-76}"
PHYSIO_HRV_MS="${PHYSIO_HRV_MS:-61}"
PHYSIO_SPO2="${PHYSIO_SPO2:-98}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b201-workspace-habitat-${STAMP}-seed}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
HABITAT_SOURCE_FILE="${HABITAT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_habitat.rs}"
COCKPIT_SOURCE_FILE="${COCKPIT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_cockpit.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
K8S_DIR="${K8S_DIR:-${ROOT}/k8s/beagle-workspace}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B201_CLUSTER_WORKSPACE_HABITAT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B201_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B201_KNOWN_LIMITS.md}"

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

wait_for_beagle_health() {
  local port="$1"
  local target="$2"
  for _ in $(seq 1 30); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    sleep 1
  done
  echo "[FAIL] Beagle health endpoint did not become ready on local port ${port}" >&2
  exit 1
}

wait_for_workspace_health() {
  local port="$1"
  local target="$2"
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}${EXPECTED_HEALTH_PROBE_PATH}" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      return 0
    fi
    sleep 2
  done
  echo "[FAIL] workspace IDE health endpoint did not become ready on local port ${port}" >&2
  exit 1
}

rollout_deployment() {
  local deployment="$1"
  local restart_log="$2"
  local rollout_log="$3"

  ${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${deployment}" > "${restart_log}"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${deployment}" --timeout=900s > "${rollout_log}"
}

wait_for_existing_rollout() {
  local deployment="$1"
  local rollout_log="$2"
  ${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${deployment}" --timeout=900s > "${rollout_log}"
}

curl_beagle_json() {
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
      "http://127.0.0.1:${BEAGLE_LOCAL_PORT}${path}" \
      > "${target}"
  else
    curl -fsS -X "${method}" \
      -H "${AUTH_HEADER}" \
      -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${BEAGLE_LOCAL_PORT}${path}" \
      > "${target}"
  fi
}

curl_beagle_text() {
  local path="$1"
  local target="$2"
  curl -fsS \
    -H "${AUTH_HEADER}" \
    -H "${CONSUMER_HEADER}" \
    "http://127.0.0.1:${BEAGLE_LOCAL_PORT}${path}" \
    > "${target}"
}

curl_workspace() {
  local path="$1"
  local target="$2"
  curl -fsSL "http://127.0.0.1:${WORKSPACE_LOCAL_PORT}${path}" > "${target}"
}

exec_workspace_file() {
  local remote_path="$1"
  local target="$2"
  ${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- sh -lc "cat '${remote_path}'" > "${target}"
}

hydrate_workspace_repo_snapshot() {
  tar \
    --exclude='./target' \
    --exclude='./node_modules' \
    --exclude='./.artifacts' \
    --exclude='./.git' \
    -C "${ROOT}" \
    -cf - . \
    | ${KUBECTL} -n "${NAMESPACE}" exec -i deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- sh -lc "mkdir -p '${EXPECTED_WORKSPACE_ROOT}' && tar -xf - -C '${EXPECTED_WORKSPACE_ROOT}'"
}

capture_workspace_repo_snapshot() {
  local target="$1"
  ${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c "${WORKSPACE_CONTAINER_NAME}" -- sh -lc "
    cd '${EXPECTED_WORKSPACE_ROOT}' &&
    pwd &&
    test -f Cargo.toml &&
    echo cargo_toml=present &&
    test -f apps/beagle-monorepo/src/http_darwin_hpc.rs &&
    echo darwin_http=present &&
    test -f k8s/beagle-workspace/deployment.yaml &&
    echo habitat_k8s=present
  " > "${target}"
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

OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
WORKSPACE_LOCAL_PORT="$(choose_local_port "${WORKSPACE_LOCAL_PORT}")"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${EXPECTED_SESSION_ID}" > "${OUT}/expected-session-id.txt"
echo "${EXPECTED_WORKSTREAM}" > "${OUT}/expected-workstream.txt"
echo "${EXPECTED_REPO}" > "${OUT}/expected-repo.txt"
echo "${EXPECTED_BRANCH}" > "${OUT}/expected-branch.txt"
echo "${EXPECTED_IDE_KIND}" > "${OUT}/expected-ide-kind.txt"
echo "${EXPECTED_BROWSER_URL}" > "${OUT}/expected-browser-url.txt"
echo "${EXPECTED_HEALTH_URL}" > "${OUT}/expected-health-url.txt"
echo "${EXPECTED_WORKSPACE_ROOT}" > "${OUT}/expected-workspace-root.txt"
echo "${EXPECTED_CONTEXT_PACKET_FILE}" > "${OUT}/expected-context-packet-file.txt"
echo "${EXPECTED_CONTEXT_ENV_FILE}" > "${OUT}/expected-context-env-file.txt"
echo "${EXPECTED_RECOMMENDED_RECIPE_KIND}" > "${OUT}/expected-recommended-recipe-kind.txt"
echo "${EXPECTED_PROVIDER}" > "${OUT}/expected-provider.txt"
echo "${EXPECTED_MODEL}" > "${OUT}/expected-model.txt"

HABITAT_SOURCE_PRESENT=0
COCKPIT_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
K8S_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0

if rg -q "build_workstream_workspace_habitat|render_workspace_habitat_context_env" "${HABITAT_SOURCE_FILE}"; then
  HABITAT_SOURCE_PRESENT=1
fi
if rg -q "workspace_habitat_path|workspace_habitat_env_path|workspace_habitat_browser_url" "${COCKPIT_SOURCE_FILE}"; then
  COCKPIT_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/workstreams/:workstream_id/workspace-habitat|workspace_habitat_handler|workspace_habitat_env_handler" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
if [[ -d "${K8S_DIR}" ]] && [[ -f "${K8S_DIR}/deployment.yaml" ]] && [[ -f "${K8S_DIR}/configmap.yaml" ]]; then
  K8S_PRESENT=1
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
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_ide_kind "${EXPECTED_IDE_KIND}" \
  --arg expected_browser_url "${EXPECTED_BROWSER_URL}" \
  --arg expected_health_url "${EXPECTED_HEALTH_URL}" \
  --arg expected_workspace_root "${EXPECTED_WORKSPACE_ROOT}" \
  --arg expected_context_packet_file "${EXPECTED_CONTEXT_PACKET_FILE}" \
  --arg expected_context_env_file "${EXPECTED_CONTEXT_ENV_FILE}" \
  --argjson habitat_source_present "${HABITAT_SOURCE_PRESENT}" \
  --argjson cockpit_source_present "${COCKPIT_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson k8s_present "${K8S_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  '{
    expected_workstream: $expected_workstream,
    expected_ide_kind: $expected_ide_kind,
    expected_browser_url: $expected_browser_url,
    expected_health_url: $expected_health_url,
    expected_workspace_root: $expected_workspace_root,
    expected_context_packet_file: $expected_context_packet_file,
    expected_context_env_file: $expected_context_env_file,
    habitat_source_present: $habitat_source_present,
    cockpit_source_present: $cockpit_source_present,
    http_source_present: $http_source_present,
    k8s_present: $k8s_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present
  }' > "${OUT}/source-summary.json"

sudo podman build -t "${IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build.log" 2>&1
IMAGE_REF="${IMAGE_REF}" bash "${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh" > "${OUT}/image-load.log" 2>&1

${KUBECTL} apply -k "${ROOT}/k8s/beagle" > "${OUT}/deploy-apply.log"
rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/restart-for-deploy.txt" "${OUT}/deploy-rollout.log"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
wait_for_beagle_health "${BEAGLE_LOCAL_PORT}" "${OUT}/beagle-health-before.json"

curl_beagle_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}&session_id=${EXPECTED_SESSION_ID}" "${OUT}/bootstrap-before.json"

cat > "${OUT}/seed-pilot-request.json" <<EOF
{
  "workspace_id": "${WORKSPACE_ID}",
  "session_id": "${EXPECTED_SESSION_ID}",
  "profile_id": "${SEED_PROFILE_ID}",
  "run_label": "${SEED_RUN_LABEL}",
  "timeout_seconds": ${TIMEOUT_SECONDS}
}
EOF
curl_beagle_json POST "/api/darwin/workspace/pilot/execute" "${OUT}/seed-pilot.json" "${OUT}/seed-pilot-request.json"
SEED_SESSION_ID="$(jq -r '.session_id' "${OUT}/seed-pilot.json")"
PUBLISHED_RESULT_JOB_ID="$(jq -r '.published_result.job_id' "${OUT}/seed-pilot.json")"
if [[ "${SEED_SESSION_ID}" != "${EXPECTED_SESSION_ID}" ]]; then
  echo "[FAIL] seed-pilot session_id ${SEED_SESSION_ID} does not match expected ${EXPECTED_SESSION_ID}" >&2
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
curl_beagle_json POST "/api/observer/physio" "${OUT}/physio-ingest-response.json" "${OUT}/physio-request.json"

MEMORY_TEXT="Cluster workspace habitat keeps ${EXPECTED_WORKSTREAM} ${WORKSPACE_ID} ${SEED_SESSION_ID} aligned for openvscode-server."
cat > "${OUT}/memory-ingest-request.json" <<EOF
{
  "source": "${EXPECTED_MEMORY_SOURCE}",
  "conversation_id": "${SEED_SESSION_ID}",
  "turn_index": 0,
  "role": "assistant",
  "text": "${MEMORY_TEXT}",
  "tags": ["${EXPECTED_WORKSTREAM}", "${EXPECTED_MEMORY_TAG}"],
  "domain": "${EXPECTED_MEMORY_DOMAIN}"
}
EOF
curl_beagle_json POST "/api/memory/ingest_chat" "${OUT}/memory-ingest-response.json" "${OUT}/memory-ingest-request.json"

${KUBECTL} apply -k "${ROOT}/k8s/beagle-workspace" > "${OUT}/workspace-deploy-apply.log"
rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/workspace-restart-for-deploy.txt" "${OUT}/workspace-deploy-rollout.log"

start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward.log" WORKSPACE_PF_PID
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/code-server-healthz.txt"
cp "${OUT}/code-server-healthz.txt" "${OUT}/workspace-health.txt"
hydrate_workspace_repo_snapshot
capture_workspace_repo_snapshot "${OUT}/workspace-repo-snapshot.txt"
curl_workspace "/" "${OUT}/code-server-root.html"

curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-habitat" "${OUT}/workspace-context.json"
cp "${OUT}/workspace-context.json" "${OUT}/workspace-habitat.json"
curl_beagle_text "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-habitat/context.env" "${OUT}/workspace-context-env-api.txt"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/cockpit" "${OUT}/cockpit.json"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/cursor" "${OUT}/tool-cursor.json"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/claude-code" "${OUT}/tool-claude-code.json"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/tool-dock/codex" "${OUT}/tool-codex.json"
exec_workspace_file "${EXPECTED_CONTEXT_PACKET_FILE}" "${OUT}/workspace-context-packet-file.json"
exec_workspace_file "${EXPECTED_CONTEXT_ENV_FILE}" "${OUT}/workspace-context-env-file.txt"
exec_workspace_file "/workspace/beagle/.beagle/context/bootstrap.json" "${OUT}/workspace-bootstrap-file.json"

stop_port_forward BEAGLE_PF_PID
stop_port_forward WORKSPACE_PF_PID

rollout_deployment "${BEAGLE_DEPLOYMENT}" "${OUT}/restart-beagle.txt" "${OUT}/restart-beagle-rollout.log"
rollout_deployment "${WORKSPACE_DEPLOYMENT}" "${OUT}/restart-workspace.txt" "${OUT}/restart-workspace-rollout.log"

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward-after-restart.log" BEAGLE_PF_PID
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward-after-restart.log" WORKSPACE_PF_PID
wait_for_beagle_health "${BEAGLE_LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
wait_for_workspace_health "${WORKSPACE_LOCAL_PORT}" "${OUT}/code-server-healthz-after-restart.txt"
cp "${OUT}/code-server-healthz-after-restart.txt" "${OUT}/workspace-health-after-restart.txt"
capture_workspace_repo_snapshot "${OUT}/workspace-repo-snapshot-after-restart.txt"
curl_workspace "/" "${OUT}/code-server-root-after-restart.html"

curl_beagle_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}&session_id=${EXPECTED_SESSION_ID}" "${OUT}/bootstrap-after-restart.json"
curl_beagle_json GET "/api/darwin/workstreams/${EXPECTED_WORKSTREAM}/workspace-habitat" "${OUT}/workspace-context-after-restart.json"
cp "${OUT}/workspace-context-after-restart.json" "${OUT}/workspace-habitat-after-restart.json"
exec_workspace_file "${EXPECTED_CONTEXT_PACKET_FILE}" "${OUT}/workspace-context-packet-file-after-restart.json"
exec_workspace_file "${EXPECTED_CONTEXT_ENV_FILE}" "${OUT}/workspace-context-env-file-after-restart.txt"

capture_cluster_health

jq -nc \
  --arg status "ok" \
  --arg ide_kind "${EXPECTED_IDE_KIND}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg workstream_id "${EXPECTED_WORKSTREAM}" \
  --arg browser_url "${EXPECTED_BROWSER_URL}" \
  --arg health_url "${EXPECTED_HEALTH_URL}" \
  --arg health_probe_path "${EXPECTED_HEALTH_PROBE_PATH}" \
  '{
    status: $status,
    ide_kind: $ide_kind,
    workspace_id: $workspace_id,
    session_id: $session_id,
    workstream_id: $workstream_id,
    browser_url: $browser_url,
    health_url: $health_url,
    health_probe_path: $health_probe_path,
    restart_recovered_session: true
  }' > "${OUT}/workspace-runtime-summary.json"

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_ide_kind "${EXPECTED_IDE_KIND}" \
  --arg expected_browser_url "${EXPECTED_BROWSER_URL}" \
  --arg expected_health_url "${EXPECTED_HEALTH_URL}" \
  --arg expected_workspace_root "${EXPECTED_WORKSPACE_ROOT}" \
  --arg expected_context_packet_file "${EXPECTED_CONTEXT_PACKET_FILE}" \
  --arg expected_context_env_file "${EXPECTED_CONTEXT_ENV_FILE}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" \
  '{
    status: "ok",
    workspace_id: $workspace_id,
    session_id: $session_id,
    expected_workstream: $expected_workstream,
    expected_ide_kind: $expected_ide_kind,
    expected_browser_url: $expected_browser_url,
    expected_health_url: $expected_health_url,
    expected_workspace_root: $expected_workspace_root,
    expected_context_packet_file: $expected_context_packet_file,
    expected_context_env_file: $expected_context_env_file,
    published_result_job_id: $published_result_job_id,
    provider: $expected_provider,
    model: $expected_model,
    restart_recovered_session: true
  }' > "${OUT}/smoke.json"

echo "[OK] cluster workspace habitat smoke completed"
