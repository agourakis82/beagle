#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18113}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/jats-manuscript-pack}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
WORKSPACE_ID="${WORKSPACE_ID:-b201-jats-pack-${STAMP}}"
EXPECTED_PROGRAM="${EXPECTED_PROGRAM:-beagle-physio-symbolic-exocortex}"
EXPECTED_CAMPAIGN="${EXPECTED_CAMPAIGN:-expedition-002-hrv-aware}"
EXPECTED_WORKSTREAM="${EXPECTED_WORKSTREAM:-beagle-darwin-hpc-governance}"
EXPECTED_EXPERIMENT="${EXPECTED_EXPERIMENT:-beagle_exp_002_hrv_aware_vs_blind}"
EXPECTED_MANUSCRIPT_TARGET="${EXPECTED_MANUSCRIPT_TARGET:-expedition-002-results}"
EXPECTED_JATS_PROFILE="${EXPECTED_JATS_PROFILE:-jats-1.4-ready}"
EXPECTED_ARTICLE_TYPE="${EXPECTED_ARTICLE_TYPE:-research-article}"
EXPECTED_READINESS_STATE="${EXPECTED_READINESS_STATE:-claim-linked-human-eval-pending}"
EXPECTED_MEMORY_SOURCE="${EXPECTED_MEMORY_SOURCE:-codex}"
EXPECTED_MEMORY_DOMAIN="${EXPECTED_MEMORY_DOMAIN:-beagle-jats-pack}"
EXPECTED_MEMORY_TAG="${EXPECTED_MEMORY_TAG:-jats-pack}"
SEED_PROFILE_ID="${SEED_PROFILE_ID:-cpu-batch-v1}"
SEED_RUN_LABEL="${SEED_RUN_LABEL:-b201-jats-pack-${STAMP}-seed}"
PHYSIO_SOURCE="${PHYSIO_SOURCE:-observer-smoke}"
PHYSIO_HR="${PHYSIO_HR:-76}"
PHYSIO_HRV_MS="${PHYSIO_HRV_MS:-55}"
PHYSIO_SPO2="${PHYSIO_SPO2:-98}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
IMAGE_REF="${IMAGE_REF:-localhost/beagle-core:dev}"
MANUSCRIPT_PACK_SOURCE_FILE="${MANUSCRIPT_PACK_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/manuscript_pack.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B201_JATS_READY_MANUSCRIPT_ASSEMBLY.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B201_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B201_KNOWN_LIMITS.md}"
CONTRACT_FILE="${CONTRACT_FILE:-${ROOT}/docs/darwin/hpc/contracts/jats-manuscript-pack-schema.yaml}"
SECTION_MAP_FILE="${SECTION_MAP_FILE:-${ROOT}/docs/darwin/hpc/contracts/manuscript-section-map.yaml}"

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
echo "${EXPECTED_PROGRAM}" > "${OUT}/expected-program.txt"
echo "${EXPECTED_CAMPAIGN}" > "${OUT}/expected-campaign.txt"
echo "${EXPECTED_WORKSTREAM}" > "${OUT}/expected-workstream.txt"
echo "${EXPECTED_EXPERIMENT}" > "${OUT}/expected-experiment.txt"
echo "${EXPECTED_MANUSCRIPT_TARGET}" > "${OUT}/expected-manuscript-target.txt"
echo "${EXPECTED_JATS_PROFILE}" > "${OUT}/expected-jats-profile.txt"
echo "${EXPECTED_ARTICLE_TYPE}" > "${OUT}/expected-article-type.txt"
echo "${EXPECTED_READINESS_STATE}" > "${OUT}/expected-readiness-state.txt"

MANUSCRIPT_PACK_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
CONTRACT_PRESENT=0
SECTION_MAP_PRESENT=0

if rg -q "JatsManuscriptPack|build_campaign_jats_manuscript_pack|jats_xml" "${MANUSCRIPT_PACK_SOURCE_FILE}"; then
  MANUSCRIPT_PACK_SOURCE_PRESENT=1
fi
if rg -q "/api/darwin/campaigns/:campaign_id/jats-manuscript-pack|resolve_campaign_jats_manuscript_pack|build_campaign_jats_manuscript_pack" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -s "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -s "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -s "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -s "${CONTRACT_FILE}" ]] && CONTRACT_PRESENT=1
[[ -s "${SECTION_MAP_FILE}" ]] && SECTION_MAP_PRESENT=1

jq -nc \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --arg expected_article_type "${EXPECTED_ARTICLE_TYPE}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" \
  --argjson manuscript_pack_source_present "${MANUSCRIPT_PACK_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson contract_present "${CONTRACT_PRESENT}" \
  --argjson section_map_present "${SECTION_MAP_PRESENT}" \
  '{
    expected_program: $expected_program,
    expected_campaign: $expected_campaign,
    expected_workstream: $expected_workstream,
    expected_experiment: $expected_experiment,
    expected_manuscript_target: $expected_manuscript_target,
    expected_jats_profile: $expected_jats_profile,
    expected_article_type: $expected_article_type,
    expected_readiness_state: $expected_readiness_state,
    manuscript_pack_source_present: $manuscript_pack_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    contract_present: $contract_present,
    section_map_present: $section_map_present
  }' > "${OUT}/source-summary.json"

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

MEMORY_TEXT="JATS manuscript pack remembers ${EXPECTED_PROGRAM} ${EXPECTED_CAMPAIGN} ${EXPECTED_WORKSTREAM} on ${WORKSPACE_ID} ${SEED_SESSION_ID}."
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
curl_json POST "/api/memory/ingest_chat" "${OUT}/ingest-response.json" "${OUT}/memory-ingest-request.json"

curl_json GET "/api/darwin/campaigns/${EXPECTED_CAMPAIGN}/jats-manuscript-pack" "${OUT}/jats-manuscript-pack.json"
jq -r '.pack.jats_xml' "${OUT}/jats-manuscript-pack.json" > "${OUT}/jats-article.xml"
stop_port_forward

rollout_service "${OUT}/restart-for-recovery.txt" "${OUT}/recovery-rollout.log"

PF_LOG="${OUT}/port-forward-after-restart.log"
start_port_forward "${LOCAL_PORT}" "${PF_LOG}"
wait_for_health "${LOCAL_PORT}" "${OUT}/beagle-health-after-restart.json"
curl_json GET "/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" "${OUT}/bootstrap-after-restart.json"
curl_json GET "/api/darwin/campaigns/${EXPECTED_CAMPAIGN}/jats-manuscript-pack" "${OUT}/jats-manuscript-pack-after-restart.json"
jq -r '.pack.jats_xml' "${OUT}/jats-manuscript-pack-after-restart.json" > "${OUT}/jats-article-after-restart.xml"
stop_port_forward

jq -nc \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --arg expected_article_type "${EXPECTED_ARTICLE_TYPE}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" \
  --slurpfile pack "${OUT}/jats-manuscript-pack.json" \
  --slurpfile restart "${OUT}/bootstrap-after-restart.json" \
  --slurpfile pack_after_restart "${OUT}/jats-manuscript-pack-after-restart.json" \
  '{
    status: (
      if (
        ($pack[0].pack.program_id // "") == $expected_program
        and ($pack[0].pack.campaign_id // "") == $expected_campaign
        and ($pack[0].pack.active_workstream_id // "") == $expected_workstream
        and ($pack[0].pack.workspace_id // "") == $workspace_id
        and ($pack[0].pack.session_id // "") == $session_id
        and ($pack[0].pack.manuscript_target.id // "") == $expected_manuscript_target
        and ($pack[0].pack.jats_profile // "") == $expected_jats_profile
        and ($pack[0].pack.article_type // "") == $expected_article_type
        and ($pack[0].pack.readiness_state // "") == $expected_readiness_state
        and (($pack[0].pack.claim_ids | length) >= 2)
        and (($pack[0].pack.section_map | length) >= 6)
        and (($pack[0].pack.jats_xml | contains("<article ")) == true)
        and (($pack[0].pack.jats_xml | contains("<front>")) == true)
        and (($pack[0].pack.jats_xml | contains("<body>")) == true)
        and (($pack[0].pack.jats_xml | contains("<ref-list>")) == true)
        and (($restart[0].workspace_id // "") == $workspace_id)
        and (($restart[0].session_id // "") == $session_id)
        and (($restart[0].recovered_session // false) == true)
        and (($pack_after_restart[0].pack.program_id // "") == $expected_program)
        and (($pack_after_restart[0].pack.campaign_id // "") == $expected_campaign)
        and (($pack_after_restart[0].pack.workspace_id // "") == $workspace_id)
        and (($pack_after_restart[0].pack.session_id // "") == $session_id)
      ) then "ok" else "fail" end
    ),
    workspace_id: $workspace_id,
    session_id: $session_id,
    expected_program: $expected_program,
    expected_campaign: $expected_campaign,
    expected_workstream: $expected_workstream,
    expected_experiment: $expected_experiment,
    claim_count: ($pack[0].pack.claim_ids | length),
    section_count: ($pack[0].pack.section_map | length),
    readiness_state: ($pack[0].pack.readiness_state // null),
    restart_recovered_session: ($restart[0].recovered_session // false),
    published_result_job_id: $published_result_job_id
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] jats manuscript pack smoke completed"
