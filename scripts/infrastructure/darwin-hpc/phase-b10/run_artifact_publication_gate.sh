#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
DARWIN_V2_ROOT=${DARWIN_V2_ROOT:-/root/darwin-v2}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_ID=${RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/artifact-publication"

PUBLISHER_NAMESPACE=${PUBLISHER_NAMESPACE:-darwin-platform}
SOURCE_JOB_ID=${SOURCE_JOB_ID:-source-job-placeholder}
SOURCE_PROFILE_ID=${SOURCE_PROFILE_ID:-cpu-short-v1}
PUBLICATION_TARGET_ID=${PUBLICATION_TARGET_ID:-research-results-v1}
PUBLICATION_LABEL=${PUBLICATION_LABEL:-b10-${RUN_ID}}
JOB_TIMEOUT=${JOB_TIMEOUT:-180s}
KEEP_JOB=${KEEP_JOB:-0}

readonly SCRIPT_DIR REPO_ROOT ARTIFACT_ROOT DARWIN_V2_ROOT PHASE_ROOT RESULT_DIR

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd kubectl
require_cmd sed

if [[ -z "${KUBECONFIG:-}" && -f /etc/kubernetes/admin.conf ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
fi

mkdir -p "${RESULT_DIR}"

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
    fi
  } > "${output_file}"
}

write_request() {
  jq -n \
    --arg job_id "${SOURCE_JOB_ID}" \
    --arg profile_id "${SOURCE_PROFILE_ID}" \
    --arg publication_target_id "${PUBLICATION_TARGET_ID}" \
    --arg publication_label "${PUBLICATION_LABEL}" \
    '{
      job_id: $job_id,
      profile_id: $profile_id,
      publication_target_id: $publication_target_id,
      publication_label: $publication_label
    }' > "${RESULT_DIR}/publication-request.json"
}

write_result() {
  cat > "${RESULT_DIR}/B10_RESULT.md" <<EOF
# B10 Artifact Publication Result

- Run ID: ${RUN_ID}
- Publisher namespace: ${PUBLISHER_NAMESPACE}
- Source job id: ${SOURCE_JOB_ID}
- Source profile id: ${SOURCE_PROFILE_ID}
- Publication target id: ${PUBLICATION_TARGET_ID}
- Publication label: ${PUBLICATION_LABEL}
- Decision: STAGED-PREFLIGHT
- Note: this runner currently exercises publication preflight only; live object publication is not yet promoted.

## Bundle

- publication-request.json
- publication-preflight.txt
- final-cluster-health.txt
EOF
}

main() {
  local manifest_root="${DARWIN_V2_ROOT}/phase-b10/manifests/darwin-hpc-publisher"
  local sa_manifest="${manifest_root}/publisher-serviceaccount.yaml"
  local config_manifest="${manifest_root}/publisher-configmap.yaml"
  local job_manifest="${manifest_root}/publication-preflight-job.yaml"
  local rendered_job
  local job_name="darwin-hpc-publication-preflight-${RUN_ID}"

  kubectl apply -f "${sa_manifest}"
  kubectl apply -f "${config_manifest}"

  rendered_job=$(mktemp)
  sed \
    -e "s/__RUN_ID__/${RUN_ID}/g" \
    -e "s/__SOURCE_JOB_ID__/${SOURCE_JOB_ID}/g" \
    "${job_manifest}" > "${rendered_job}"
  kubectl apply -f "${rendered_job}"
  rm -f "${rendered_job}"

  kubectl wait --for=condition=complete --timeout="${JOB_TIMEOUT}" -n "${PUBLISHER_NAMESPACE}" "job/${job_name}" || true
  kubectl logs -n "${PUBLISHER_NAMESPACE}" "job/${job_name}" > "${RESULT_DIR}/publication-preflight.txt" 2>&1 || true

  write_request
  collect_cluster_health
  write_result

  if [[ "${KEEP_JOB}" != "1" ]]; then
    kubectl delete job -n "${PUBLISHER_NAMESPACE}" "${job_name}" --ignore-not-found >/dev/null 2>&1 || true
  fi

  echo "B10 artifact publication preflight artifacts written to ${RESULT_DIR}"
}

main "$@"
