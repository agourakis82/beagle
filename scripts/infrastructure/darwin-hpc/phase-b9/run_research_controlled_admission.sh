#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
DARWIN_V2_ROOT=${DARWIN_V2_ROOT:-/root/darwin-v2}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b9"
RUN_ID=${RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/research-admission"

RESEARCH_NAMESPACE=${RESEARCH_NAMESPACE:-darwin-research}
GATEWAY_NAMESPACE=${GATEWAY_NAMESPACE:-darwin-platform}
JOB_TIMEOUT=${JOB_TIMEOUT:-300s}
KEEP_JOB=${KEEP_JOB:-0}

readonly SCRIPT_DIR REPO_ROOT DOC_ROOT ARTIFACT_ROOT DARWIN_V2_ROOT PHASE_ROOT RESULT_DIR

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd jq
require_cmd sed
require_cmd awk

if [[ -z "${KUBECONFIG:-}" && -f /etc/kubernetes/admin.conf ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
fi

mkdir -p "${RESULT_DIR}"

extract_section() {
  local section=$1
  local source_file=$2
  local output_file=$3

  awk -v start="<<<${section}>>>" -v stop="<<<end-${section}>>>" '
    $0 == start { capture = 1; next }
    $0 == stop { capture = 0; exit }
    capture { print }
  ' "${source_file}" > "${output_file}"
}

collect_cluster_health() {
  local output_file="${RESULT_DIR}/final-cluster-health.txt"
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## kubernetes-nodes"
    kubectl get nodes -o wide || true
    echo
    echo "## kubernetes-pods"
    kubectl get pods -A || true
    echo
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

render_result() {
  local profiles_code rejection_code submit_code status_code artifact_code stdout_code stderr_code job_state decision

  profiles_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/profiles-via-research.txt" 2>/dev/null || true)
  rejection_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/rejection-via-research.txt" 2>/dev/null || true)
  submit_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/submit-via-research.txt" 2>/dev/null || true)
  status_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/status-via-research.txt" 2>/dev/null || true)
  artifact_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/artifact-via-research.txt" 2>/dev/null || true)
  stdout_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/stdout-via-research.txt" 2>/dev/null || true)
  stderr_code=$(jq -r '.http_status // empty' "${RESULT_DIR}/stderr-via-research.txt" 2>/dev/null || true)
  job_state=$(jq -r '.body.state // .body.status // .body.job_state // .body.slurm_state // .state // empty' "${RESULT_DIR}/status-via-research.txt" 2>/dev/null || true)

  decision="NO-GO"
  if [[ "${profiles_code}" == "200" ]] \
    && [[ "${rejection_code}" == 4* ]] \
    && [[ "${submit_code}" == "200" || "${submit_code}" == "201" || "${submit_code}" == "202" ]] \
    && [[ "${status_code}" == "200" ]] \
    && [[ "${artifact_code}" == "200" ]] \
    && [[ "${stdout_code}" == "200" ]] \
    && [[ "${stderr_code}" == "200" ]] \
    && [[ "${job_state}" =~ ^(COMPLETED|SUCCEEDED|SUCCESS)$ ]]; then
    decision="GO"
  fi

  {
    echo "# B9.6 Research-facing Controlled Admission Result"
    echo
    echo "- Run ID: ${RUN_ID}"
    echo "- Research namespace: ${RESEARCH_NAMESPACE}"
    echo "- Gateway namespace: ${GATEWAY_NAMESPACE}"
    echo "- Captured at: $(date -Iseconds)"
    echo "- Preliminary decision: ${decision}"
    echo "- Note: final policy review remains manual."
    echo
    echo "## Flow Summary"
    echo
    echo "| Check | HTTP / State |"
    echo "| --- | --- |"
    echo "| GET /profiles via darwin-research | ${profiles_code:-missing} |"
    echo "| invalid submit rejected via darwin-research | ${rejection_code:-missing} |"
    echo "| POST /jobs/submit via darwin-research | ${submit_code:-missing} |"
    echo "| GET /jobs/{job_id} via darwin-research | ${status_code:-missing} / ${job_state:-missing} |"
    echo "| GET /jobs/{job_id}/artifact-manifest | ${artifact_code:-missing} |"
    echo "| GET /jobs/{job_id}/stdout | ${stdout_code:-missing} |"
    echo "| GET /jobs/{job_id}/stderr | ${stderr_code:-missing} |"
    echo
    echo "## Artifact Bundle"
    echo
    echo "- profiles-via-research.txt"
    echo "- rejection-via-research.txt"
    echo "- submit-via-research.txt"
    echo "- status-via-research.txt"
    echo "- artifact-via-research.txt"
    echo "- stdout-via-research.txt"
    echo "- stderr-via-research.txt"
    echo "- final-cluster-health.txt"
  } > "${RESULT_DIR}/B96_RESULT.md"
}

main() {
  local manifest_root="${DARWIN_V2_ROOT}/phase-b9/manifests/darwin-hpc-gateway"
  local sa_manifest="${manifest_root}/research-client-serviceaccount.yaml"
  local policy_manifest="${manifest_root}/research-networkpolicy.yaml"
  local job_manifest="${manifest_root}/research-canary-job.yaml"
  local rendered_job
  local job_name="darwin-research-hpc-canary-${RUN_ID}"
  local log_file="${RESULT_DIR}/research-canary.log"

  kubectl apply -f "${sa_manifest}"
  kubectl apply -f "${policy_manifest}"

  rendered_job=$(mktemp)
  sed "s/__RUN_ID__/${RUN_ID}/g" "${job_manifest}" > "${rendered_job}"
  kubectl apply -f "${rendered_job}"
  rm -f "${rendered_job}"

  kubectl wait --for=condition=complete --timeout="${JOB_TIMEOUT}" -n "${RESEARCH_NAMESPACE}" "job/${job_name}" || true
  kubectl logs -n "${RESEARCH_NAMESPACE}" "job/${job_name}" > "${log_file}" 2>&1 || true

  extract_section "profiles-via-research" "${log_file}" "${RESULT_DIR}/profiles-via-research.txt"
  extract_section "rejection-via-research" "${log_file}" "${RESULT_DIR}/rejection-via-research.txt"
  extract_section "submit-via-research" "${log_file}" "${RESULT_DIR}/submit-via-research.txt"
  extract_section "status-via-research" "${log_file}" "${RESULT_DIR}/status-via-research.txt"
  extract_section "artifact-via-research" "${log_file}" "${RESULT_DIR}/artifact-via-research.txt"
  extract_section "stdout-via-research" "${log_file}" "${RESULT_DIR}/stdout-via-research.txt"
  extract_section "stderr-via-research" "${log_file}" "${RESULT_DIR}/stderr-via-research.txt"

  collect_cluster_health
  render_result

  if [[ "${KEEP_JOB}" != "1" ]]; then
    kubectl delete job -n "${RESEARCH_NAMESPACE}" "${job_name}" --ignore-not-found >/dev/null 2>&1 || true
  fi

  echo "B9.6 research admission artifacts written to ${RESULT_DIR}"
}

main "$@"
