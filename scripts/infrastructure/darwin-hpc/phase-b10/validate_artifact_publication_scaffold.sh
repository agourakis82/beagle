#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
TEMPLATE_ROOT="${DOC_ROOT}/templates"
PHASE_DOC_ROOT="${DOC_ROOT}/phase-b10"
SCRIPT_ROOT="${REPO_ROOT}/scripts/infrastructure/darwin-hpc/phase-b10"
DARWIN_V2_ROOT=${DARWIN_V2_ROOT:-/root/darwin-v2}
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_DIR=${1:-}
FAILURES=0

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd jq

check_file() {
  local path=$1
  if [[ ! -f "${path}" ]]; then
    echo "missing file: ${path}" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
  if [[ ! -s "${path}" ]]; then
    echo "empty file: ${path}" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
  return 0
}

validate_static_assets() {
  local contract_dir="${CONTRACT_ROOT}"
  local summary_dir="${PHASE_DOC_ROOT}"
  local manifest_dir="${DARWIN_V2_ROOT}/phase-b10/manifests/darwin-hpc-publisher"

  check_file "${contract_dir}/artifact-publication-policy.yaml"
  check_file "${contract_dir}/publication-request-schema.json"
  check_file "${TEMPLATE_ROOT}/example_publication_request.json"
  check_file "${summary_dir}/B101_OBJECT_ARTIFACT_PUBLICATION.md"
  check_file "${summary_dir}/B101_GO_NO_GO.md"
  check_file "${summary_dir}/B101_SECURITY_BOUNDARY.md"
  check_file "${summary_dir}/B101_KNOWN_LIMITS.md"
  check_file "${manifest_dir}/publisher-serviceaccount.yaml"
  check_file "${manifest_dir}/publisher-configmap.yaml"
  check_file "${manifest_dir}/publication-preflight-job.yaml"
  check_file "${SCRIPT_ROOT}/run_artifact_publication_gate.sh"
  check_file "${SCRIPT_ROOT}/validate_artifact_publication_scaffold.sh"

  for token in \
    "phase_status: STAGED" \
    "gateway_namespace: darwin-platform" \
    "gateway_service: darwin-hpc-gateway" \
    "cpu-short-v1" \
    "cpu-batch-v1" \
    "gpu-single-v1" \
    "research-results-v1" \
    "allow_client_bucket_selection: false" \
    "allow_shared_filesystem_mounts: false" \
    "allow_direct_research_credentials: false"; do
    if ! grep -Fq "${token}" "${contract_dir}/artifact-publication-policy.yaml"; then
      echo "artifact publication policy missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  jq -e '
    .type == "object" and
    .additionalProperties == false and
    (.properties.profile_id.enum | index("cpu-short-v1")) != null and
    (.properties.profile_id.enum | index("cpu-batch-v1")) != null and
    (.properties.profile_id.enum | index("gpu-single-v1")) != null and
    (.properties.publication_target_id.enum | index("research-results-v1")) != null
  ' "${contract_dir}/publication-request-schema.json" >/dev/null || {
    echo "publication-request-schema.json does not match the expected contract" >&2
    FAILURES=$((FAILURES + 1))
  }

  for token in \
    "namespace: darwin-platform" \
    "name: darwin-hpc-publisher"; do
    if ! grep -Fq "${token}" "${manifest_dir}/publisher-serviceaccount.yaml"; then
      echo "publisher serviceaccount missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  for token in \
    "darwin-hpc-gateway.darwin-platform.svc.cluster.local" \
    "publication-target-id: research-results-v1" \
    "object-prefix-template: hpc/{profile_id}/{job_id}/"; do
    if ! grep -Fq "${token}" "${manifest_dir}/publisher-configmap.yaml"; then
      echo "publisher configmap missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  for token in \
    "serviceAccountName: darwin-hpc-publisher" \
    "darwin.phase/status: STAGED" \
    "SOURCE_JOB_ID" \
    "PUBLICATION_TARGET_ID" \
    "darwin-artifact-publisher-credentials" \
    "allowPrivilegeEscalation: false" \
    "runAsNonRoot: true" \
    "runAsUser: 65532" \
    "type: RuntimeDefault"; do
    if ! grep -Fq "${token}" "${manifest_dir}/publication-preflight-job.yaml"; then
      echo "publication preflight job missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done
}

validate_run_dir() {
  local result_dir=$1

  check_file "${result_dir}/B10_RESULT.md"
  check_file "${result_dir}/publication-request.json"
  check_file "${result_dir}/publication-preflight.txt"
  check_file "${result_dir}/final-cluster-health.txt"

  jq -e '
    .job_id != null and
    (.profile_id == "cpu-short-v1" or .profile_id == "cpu-batch-v1" or .profile_id == "gpu-single-v1") and
    .publication_target_id == "research-results-v1"
  ' "${result_dir}/publication-request.json" >/dev/null || {
    echo "publication-request.json does not match expected request constraints" >&2
    FAILURES=$((FAILURES + 1))
  }

  if ! grep -Fq "STAGED-PREFLIGHT" "${result_dir}/B10_RESULT.md"; then
    echo "B10_RESULT.md does not record the scaffold decision" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

validate_static_assets

if [[ -n "${RUN_DIR}" ]]; then
  validate_run_dir "${RUN_DIR}"
fi

if (( FAILURES > 0 )); then
  echo "validation failed with ${FAILURES} issue(s)" >&2
  exit 1
fi

if [[ -n "${RUN_DIR}" ]]; then
  echo "B10 artifact publication scaffold and run artifacts validated: ${RUN_DIR}"
else
  echo "B10 artifact publication scaffold validated"
fi
