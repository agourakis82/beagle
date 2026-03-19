#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
PHASE_DOC_ROOT="${DOC_ROOT}/phase-b9"
SCRIPT_ROOT="${REPO_ROOT}/scripts/infrastructure/darwin-hpc/phase-b9"
DARWIN_V2_ROOT=${DARWIN_V2_ROOT:-/root/darwin-v2}
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b9"
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
  local contract_path="${CONTRACT_ROOT}/research-admission-policy.yaml"
  local summary_dir="${PHASE_DOC_ROOT}"
  local manifest_dir="${DARWIN_V2_ROOT}/phase-b9/manifests/darwin-hpc-gateway"

  check_file "${contract_path}"
  check_file "${summary_dir}/B96_RESEARCH_CONTROLLED_ADMISSION.md"
  check_file "${summary_dir}/B96_GO_NO_GO.md"
  check_file "${summary_dir}/B96_SECURITY_BOUNDARY.md"
  check_file "${summary_dir}/B96_KNOWN_LIMITS.md"
  check_file "${manifest_dir}/research-networkpolicy.yaml"
  check_file "${manifest_dir}/research-client-serviceaccount.yaml"
  check_file "${manifest_dir}/research-canary-job.yaml"
  check_file "${SCRIPT_ROOT}/run_research_controlled_admission.sh"
  check_file "${SCRIPT_ROOT}/validate_research_controlled_admission.sh"

  for token in \
    "darwin-research" \
    "darwin-research-hpc-client" \
    "darwin-platform" \
    "darwin-hpc-gateway" \
    "cpu-short-v1" \
    "cpu-batch-v1" \
    "gpu-single-v1"; do
    if ! grep -Fq "${token}" "${contract_path}"; then
      echo "research admission contract missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  for token in \
    "allow_raw_scheduler_payload: false" \
    "allow_arbitrary_scripts: false" \
    "allow_arbitrary_partitions: false" \
    "allow_arbitrary_gpu_count: false"; do
    if ! grep -Fq "${token}" "${contract_path}"; then
      echo "research admission contract missing restriction: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  if ! grep -Fq "ClusterIP" "${contract_path}"; then
    echo "research admission contract must keep the gateway internal-only" >&2
    FAILURES=$((FAILURES + 1))
  fi

  if ! grep -Fq "namespace: darwin-research" "${manifest_dir}/research-client-serviceaccount.yaml"; then
    echo "service account manifest is not scoped to darwin-research" >&2
    FAILURES=$((FAILURES + 1))
  fi

  for token in \
    "namespace: darwin-research" \
    "namespace: darwin-platform" \
    "kubernetes.io/metadata.name: kube-system" \
    "app.kubernetes.io/name: darwin-research-hpc-client" \
    "app.kubernetes.io/name: darwin-hpc-gateway" \
    "k8s-app: kube-dns" \
    "protocol: UDP" \
    "port: 53" \
    "port: 80" \
    "port: 8080"; do
    if ! grep -Fq "${token}" "${manifest_dir}/research-networkpolicy.yaml"; then
      echo "research network policy missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  for token in \
    "serviceAccountName: darwin-research-hpc-client" \
    "darwin-hpc-gateway.darwin-platform.svc.cluster.local" \
    "value: cpu-short-v1" \
    "allowPrivilegeEscalation: false" \
    "runAsNonRoot: true" \
    "runAsUser: 65532" \
    "type: RuntimeDefault" \
    "rejection-via-research" \
    "profiles-via-research" \
    "submit-via-research" \
    "status-via-research" \
    "artifact-via-research" \
    "stdout-via-research" \
    "stderr-via-research"; do
    if ! grep -Fq "${token}" "${manifest_dir}/research-canary-job.yaml"; then
      echo "research canary job missing token: ${token}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done
}

validate_run_dir() {
  local result_dir=$1

  check_file "${result_dir}/B96_RESULT.md"
  check_file "${result_dir}/profiles-via-research.txt"
  check_file "${result_dir}/rejection-via-research.txt"
  check_file "${result_dir}/submit-via-research.txt"
  check_file "${result_dir}/status-via-research.txt"
  check_file "${result_dir}/artifact-via-research.txt"
  check_file "${result_dir}/stdout-via-research.txt"
  check_file "${result_dir}/stderr-via-research.txt"
  check_file "${result_dir}/final-cluster-health.txt"

  jq -e '.http_status == 200' "${result_dir}/profiles-via-research.txt" >/dev/null || {
    echo "profiles-via-research.txt does not show a successful GET /profiles" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '.http_status >= 400 and .http_status < 500' "${result_dir}/rejection-via-research.txt" >/dev/null || {
    echo "rejection-via-research.txt does not show a rejected invalid submit" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '.http_status == 200 or .http_status == 201 or .http_status == 202' "${result_dir}/submit-via-research.txt" >/dev/null || {
    echo "submit-via-research.txt does not show a successful submit" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .http_status == 200 and
    (
      .body.state == "COMPLETED" or
      .body.status == "COMPLETED" or
      .body.state == "SUCCEEDED" or
      .body.status == "SUCCEEDED" or
      .body.state == "SUCCESS" or
      .body.status == "SUCCESS" or
      .body.job_state == "COMPLETED" or
      .body.slurm_state == "COMPLETED"
    )
  ' "${result_dir}/status-via-research.txt" >/dev/null || {
    echo "status-via-research.txt does not show a terminal success state" >&2
    FAILURES=$((FAILURES + 1))
  }

  for artifact in artifact stdout stderr; do
    jq -e '.http_status == 200' "${result_dir}/${artifact}-via-research.txt" >/dev/null || {
      echo "${artifact}-via-research.txt does not show HTTP 200" >&2
      FAILURES=$((FAILURES + 1))
    }
  done
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
  echo "B9.6 research admission contracts and run artifacts validated: ${RUN_DIR}"
else
  echo "B9.6 research admission contracts validated"
fi
