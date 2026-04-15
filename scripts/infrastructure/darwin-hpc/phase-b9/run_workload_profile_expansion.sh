#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b9"

BASE_URL=${GATEWAY_BASE_URL:-}
if [[ -z "${BASE_URL}" ]]; then
  echo "GATEWAY_BASE_URL is required" >&2
  exit 1
fi

RUN_ID=${RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/workload-profiles"
PROFILES_ENDPOINT=${PROFILES_ENDPOINT:-/profiles}
SUBMIT_ENDPOINT=${SUBMIT_ENDPOINT:-/jobs/submit}
JOB_STATUS_PATH_TEMPLATE=${JOB_STATUS_PATH_TEMPLATE:-/jobs/%s}
ARTIFACT_PATH_TEMPLATE=${ARTIFACT_PATH_TEMPLATE:-/jobs/%s/artifact-manifest}
STDOUT_PATH_TEMPLATE=${STDOUT_PATH_TEMPLATE:-/jobs/%s/stdout}
STDERR_PATH_TEMPLATE=${STDERR_PATH_TEMPLATE:-/jobs/%s/stderr}
POLL_INTERVAL_SECONDS=${POLL_INTERVAL_SECONDS:-5}
POLL_TIMEOUT_SECONDS=${POLL_TIMEOUT_SECONDS:-180}
JOB_ID_JQ=${JOB_ID_JQ:-'.job_id // .id // .slurm_job_id // empty'}
JOB_STATE_JQ=${JOB_STATE_JQ:-'.state // .status // .job_state // .slurm_state // empty'}
STATUS_SUCCESS_REGEX=${STATUS_SUCCESS_REGEX:-'^(COMPLETED|SUCCEEDED|SUCCESS)$'}
STATUS_FAILURE_REGEX=${STATUS_FAILURE_REGEX:-'^(FAILED|CANCELLED|TIMEOUT|ERROR)$'}

readonly SCRIPT_DIR REPO_ROOT PHASE_ROOT RESULT_DIR

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq

mkdir -p "${RESULT_DIR}"

declare -A JOB_IDS
declare -A FINAL_STATES
declare -A SUBMIT_CODES
declare -A STATUS_CODES
declare -A ARTIFACT_CODES
declare -A PROFILE_RESULTS

LAST_HTTP_STATUS=""
LAST_BODY_FILE=""

curl_common_args=(
  -sS
  -L
  --connect-timeout "${CURL_CONNECT_TIMEOUT:-10}"
  --max-time "${CURL_MAX_TIME:-60}"
  -H "Accept: application/json"
)

if [[ -n "${GATEWAY_AUTH_HEADER:-}" ]]; then
  curl_common_args+=(-H "${GATEWAY_AUTH_HEADER}")
fi

extract_http_status() {
  local header_file=$1
  awk 'toupper($1) ~ /^HTTP/ { code = $2 } END { print code }' "${header_file}"
}

perform_request() {
  local method=$1
  local endpoint=$2
  local payload_file=$3
  local output_file=$4
  local url="${BASE_URL%/}${endpoint}"
  local body_tmp
  local header_tmp
  local curl_rc=0

  body_tmp=$(mktemp)
  header_tmp=$(mktemp)

  local curl_args=("${curl_common_args[@]}" -X "${method}" -D "${header_tmp}" "${url}")
  if [[ -n "${payload_file}" ]]; then
    curl_args+=(-H "Content-Type: application/json" --data @"${payload_file}")
  fi

  if ! curl "${curl_args[@]}" -o "${body_tmp}"; then
    curl_rc=$?
  fi

  LAST_HTTP_STATUS=$(extract_http_status "${header_tmp}")
  LAST_BODY_FILE="${body_tmp}"

  {
    echo "request_method=${method}"
    echo "request_url=${url}"
    echo "http_status=${LAST_HTTP_STATUS:-000}"
    echo "curl_exit_code=${curl_rc}"
    echo "captured_at=$(date -Iseconds)"
    echo
    if [[ -s "${body_tmp}" ]] && jq empty "${body_tmp}" >/dev/null 2>&1; then
      jq . "${body_tmp}"
    else
      cat "${body_tmp}"
    fi
  } > "${output_file}"

  rm -f "${header_tmp}"
  return "${curl_rc}"
}

fetch_profiles() {
  local url="${BASE_URL%/}${PROFILES_ENDPOINT}"
  local body_tmp
  local header_tmp

  body_tmp=$(mktemp)
  header_tmp=$(mktemp)

  curl "${curl_common_args[@]}" -D "${header_tmp}" "${url}" -o "${body_tmp}"
  LAST_HTTP_STATUS=$(extract_http_status "${header_tmp}")
  LAST_BODY_FILE="${body_tmp}"

  if [[ "${LAST_HTTP_STATUS}" != "200" ]]; then
    echo "GET ${PROFILES_ENDPOINT} returned HTTP ${LAST_HTTP_STATUS}" >&2
    cat "${body_tmp}" >&2
    rm -f "${header_tmp}" "${body_tmp}"
    exit 1
  fi

  if jq empty "${body_tmp}" >/dev/null 2>&1; then
    jq . "${body_tmp}" > "${RESULT_DIR}/profiles-response.json"
  else
    cat "${body_tmp}" > "${RESULT_DIR}/profiles-response.json"
  fi

  rm -f "${header_tmp}" "${body_tmp}"
}

submit_profile() {
  local profile_id=$1
  local request_file=$2
  local output_prefix=$3
  local submit_path="${RESULT_DIR}/${output_prefix}-submit.txt"
  local status_path="${RESULT_DIR}/${output_prefix}-status.txt"
  local artifact_path="${RESULT_DIR}/${output_prefix}-artifact.txt"
  local stdout_path="${RESULT_DIR}/${output_prefix}-stdout.txt"
  local stderr_path="${RESULT_DIR}/${output_prefix}-stderr.txt"
  local started_at
  local job_id
  local job_state=""
  local success=0

  perform_request "POST" "${SUBMIT_ENDPOINT}" "${request_file}" "${submit_path}"
  SUBMIT_CODES["${profile_id}"]=${LAST_HTTP_STATUS:-000}

  if [[ "${SUBMIT_CODES[${profile_id}]}" != "200" && "${SUBMIT_CODES[${profile_id}]}" != "201" && "${SUBMIT_CODES[${profile_id}]}" != "202" ]]; then
    PROFILE_RESULTS["${profile_id}"]="submit-http-${SUBMIT_CODES[${profile_id}]}"
    rm -f "${LAST_BODY_FILE}"
    return 1
  fi

  if ! job_id=$(jq -r "${JOB_ID_JQ}" "${LAST_BODY_FILE}" 2>/dev/null); then
    PROFILE_RESULTS["${profile_id}"]="missing-job-id"
    rm -f "${LAST_BODY_FILE}"
    return 1
  fi
  rm -f "${LAST_BODY_FILE}"

  if [[ -z "${job_id}" || "${job_id}" == "null" ]]; then
    PROFILE_RESULTS["${profile_id}"]="missing-job-id"
    return 1
  fi

  JOB_IDS["${profile_id}"]=${job_id}
  started_at=$(date +%s)

  while true; do
    local status_endpoint
    status_endpoint=$(printf "${JOB_STATUS_PATH_TEMPLATE}" "${job_id}")
    perform_request "GET" "${status_endpoint}" "" "${status_path}"
    STATUS_CODES["${profile_id}"]=${LAST_HTTP_STATUS:-000}

    if jq empty "${LAST_BODY_FILE}" >/dev/null 2>&1; then
      job_state=$(jq -r "${JOB_STATE_JQ}" "${LAST_BODY_FILE}" 2>/dev/null || true)
    else
      job_state=""
    fi

    if [[ -n "${job_state}" && "${job_state}" =~ ${STATUS_SUCCESS_REGEX} ]]; then
      success=1
      break
    fi

    if [[ -n "${job_state}" && "${job_state}" =~ ${STATUS_FAILURE_REGEX} ]]; then
      break
    fi

    if (( $(date +%s) - started_at >= POLL_TIMEOUT_SECONDS )); then
      job_state="TIMEOUT_WAITING_FOR_TERMINAL_STATE"
      break
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
    rm -f "${LAST_BODY_FILE}"
  done

  FINAL_STATES["${profile_id}"]=${job_state:-UNKNOWN}
  rm -f "${LAST_BODY_FILE}"

  local artifact_endpoint
  artifact_endpoint=$(printf "${ARTIFACT_PATH_TEMPLATE}" "${job_id}")
  perform_request "GET" "${artifact_endpoint}" "" "${artifact_path}"
  ARTIFACT_CODES["${profile_id}"]=${LAST_HTTP_STATUS:-000}
  rm -f "${LAST_BODY_FILE}"

  local stdout_endpoint
  stdout_endpoint=$(printf "${STDOUT_PATH_TEMPLATE}" "${job_id}")
  perform_request "GET" "${stdout_endpoint}" "" "${stdout_path}" || true
  rm -f "${LAST_BODY_FILE}"

  local stderr_endpoint
  stderr_endpoint=$(printf "${STDERR_PATH_TEMPLATE}" "${job_id}")
  perform_request "GET" "${stderr_endpoint}" "" "${stderr_path}" || true
  rm -f "${LAST_BODY_FILE}"

  if (( success == 1 )) && [[ "${ARTIFACT_CODES[${profile_id}]}" == "200" ]]; then
    PROFILE_RESULTS["${profile_id}"]="PASS"
    return 0
  fi

  PROFILE_RESULTS["${profile_id}"]="FAIL"
  return 1
}

collect_cluster_health() {
  local output_file="${RESULT_DIR}/final-cluster-health.txt"

  {
    echo "captured_at=$(date -Iseconds)"
    echo
    if [[ -n "${B95_CLUSTER_HEALTH_CMD:-}" ]]; then
      echo "## custom-health-command"
      bash -lc "${B95_CLUSTER_HEALTH_CMD}" || true
      echo
    fi

    if command -v kubectl >/dev/null 2>&1; then
      echo "## kubernetes-nodes"
      kubectl get nodes -o wide || true
      echo
      echo "## kubernetes-pods"
      kubectl get pods -A || true
      echo
    else
      echo "kubectl unavailable"
      echo
    fi

    if command -v sinfo >/dev/null 2>&1; then
      echo "## slurm-sinfo"
      sinfo || true
      echo
    else
      echo "sinfo unavailable"
      echo
    fi

    if command -v squeue >/dev/null 2>&1; then
      echo "## slurm-squeue"
      squeue || true
      echo
    else
      echo "squeue unavailable"
      echo
    fi
  } > "${output_file}"
}

render_result_markdown() {
  local decision="NO-GO"

  if [[ "${PROFILE_RESULTS[cpu-short-v1]:-FAIL}" == "PASS" && "${PROFILE_RESULTS[cpu-batch-v1]:-FAIL}" == "PASS" && "${PROFILE_RESULTS[gpu-single-v1]:-FAIL}" == "PASS" ]]; then
    decision="GO"
  elif [[ "${PROFILE_RESULTS[cpu-short-v1]:-FAIL}" == "PASS" && "${PROFILE_RESULTS[cpu-batch-v1]:-FAIL}" == "PASS" ]]; then
    decision="GO-WITH-BLOCKER"
  fi

  {
    echo "# B9.5 Workload Class Expansion Result"
    echo
    echo "- Run ID: ${RUN_ID}"
    echo "- Gateway base URL: ${BASE_URL}"
    echo "- Captured at: $(date -Iseconds)"
    echo "- Preliminary decision: ${decision}"
    echo "- Note: this automation checks gateway flows and artifact capture only; policy reopening remains a manual review."
    echo
    echo "## Profile Matrix"
    echo
    echo "| Profile | Job ID | Final state | Submit HTTP | Status HTTP | Artifact HTTP | Result |"
    echo "| --- | --- | --- | --- | --- | --- | --- |"
    for profile in cpu-short-v1 cpu-batch-v1 gpu-single-v1; do
      echo "| ${profile} | ${JOB_IDS[${profile}]:--} | ${FINAL_STATES[${profile}]:--} | ${SUBMIT_CODES[${profile}]:--} | ${STATUS_CODES[${profile}]:--} | ${ARTIFACT_CODES[${profile}]:--} | ${PROFILE_RESULTS[${profile}]:--} |"
    done
    echo
    echo "## Artifact Bundle"
    echo
    echo "- profiles-response.json"
    echo "- cpu-short-submit.txt / cpu-short-status.txt / cpu-short-artifact.txt"
    echo "- cpu-batch-submit.txt / cpu-batch-status.txt / cpu-batch-artifact.txt"
    echo "- gpu-submit.txt / gpu-status.txt / gpu-artifact.txt"
    echo "- final-cluster-health.txt"
  } > "${RESULT_DIR}/B95_RESULT.md"
}

main() {
  fetch_profiles

  submit_profile "cpu-short-v1" "${CONTRACT_ROOT}/cpu-short-job.json" "cpu-short" || true
  submit_profile "cpu-batch-v1" "${CONTRACT_ROOT}/cpu-batch-job.json" "cpu-batch" || true
  submit_profile "gpu-single-v1" "${CONTRACT_ROOT}/gpu-single-job.json" "gpu" || true

  collect_cluster_health
  render_result_markdown

  echo "B9.5 workload profile expansion artifacts written to ${RESULT_DIR}"
}

main "$@"
