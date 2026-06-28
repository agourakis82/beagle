#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
PHASE_DOC_ROOT="${DOC_ROOT}/phase-b9"
TEMPLATE_ROOT="${DOC_ROOT}/templates"
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

check_http_status_ok() {
  local path=$1
  local label=$2
  local status

  status=$(awk -F= '/^http_status=/{ print $2; exit }' "${path}")
  case "${status}" in
    200|201|202)
      return 0
      ;;
    *)
      echo "${label} unexpected http status: ${status:-missing} (${path})" >&2
      FAILURES=$((FAILURES + 1))
      return 1
      ;;
  esac
}

validate_contracts() {
  local contract_dir="${CONTRACT_ROOT}"
  local summary_dir="${PHASE_DOC_ROOT}"
  local manifest_path="${DARWIN_V2_ROOT}/phase-b9/manifests/darwin-hpc-gateway/profile-configmap.yaml"
  local template_dir="${TEMPLATE_ROOT}"

  check_file "${contract_dir}/hpc-workload-profiles.yaml"
  check_file "${contract_dir}/gateway-submit-schema.json"
  check_file "${contract_dir}/cpu-short-job.json"
  check_file "${contract_dir}/cpu-batch-job.json"
  check_file "${contract_dir}/gpu-single-job.json"
  check_file "${template_dir}/example_cpu_short_request.json"
  check_file "${template_dir}/example_cpu_batch_request.json"
  check_file "${template_dir}/example_gpu_single_request.json"
  check_file "${summary_dir}/B95_WORKLOAD_CLASS_EXPANSION.md"
  check_file "${summary_dir}/B95_GO_NO_GO.md"
  check_file "${summary_dir}/B95_SECURITY_BOUNDARY.md"
  check_file "${summary_dir}/B95_PROFILE_CATALOG.md"
  check_file "${summary_dir}/B95_KNOWN_LIMITS.md"
  check_file "${manifest_path}"

  for profile in cpu-short-v1 cpu-batch-v1 gpu-single-v1; do
    if ! grep -Fq "id: ${profile}" "${contract_dir}/hpc-workload-profiles.yaml"; then
      echo "profile missing from catalog: ${profile}" >&2
      FAILURES=$((FAILURES + 1))
    fi
    if ! grep -Fq "${profile}" "${manifest_path}"; then
      echo "profile missing from manifest: ${profile}" >&2
      FAILURES=$((FAILURES + 1))
    fi
    if ! grep -Fq "${profile}" "${summary_dir}/B95_PROFILE_CATALOG.md"; then
      echo "profile missing from summary catalog: ${profile}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  if ! grep -Fq "No raw scheduler payload passthrough." "${contract_dir}/hpc-workload-profiles.yaml"; then
    echo "catalog missing raw payload prohibition" >&2
    FAILURES=$((FAILURES + 1))
  fi

  jq -e '
    .type == "object" and
    .additionalProperties == false and
    (.required | index("profile_id")) and
    (.required | index("parameters")) and
    (.properties.profile_id.enum | index("cpu-short-v1")) and
    (.properties.profile_id.enum | index("cpu-batch-v1")) and
    (.properties.profile_id.enum | index("gpu-single-v1"))
  ' "${contract_dir}/gateway-submit-schema.json" >/dev/null || {
    echo "submit schema is missing required profile controls" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .profile_id == "cpu-short-v1" and
    (.parameters | keys | sort) == ["run_label"]
  ' "${contract_dir}/cpu-short-job.json" >/dev/null || {
    echo "cpu-short-job.json does not match the contract" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .profile_id == "cpu-batch-v1" and
    (.parameters | keys | sort) == ["run_label"]
  ' "${contract_dir}/cpu-batch-job.json" >/dev/null || {
    echo "cpu-batch-job.json does not match the contract" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .profile_id == "gpu-single-v1" and
    (.parameters | keys | sort) == ["run_label"]
  ' "${contract_dir}/gpu-single-job.json" >/dev/null || {
    echo "gpu-single-job.json does not match the contract" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .profile_id == "cpu-short-v1" and
    (.parameters | keys | sort) == ["run_label"]
  ' "${template_dir}/example_cpu_short_request.json" >/dev/null || {
    echo "example_cpu_short_request.json does not match the contract" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .profile_id == "cpu-batch-v1" and
    (.parameters | keys | sort) == ["run_label"]
  ' "${template_dir}/example_cpu_batch_request.json" >/dev/null || {
    echo "example_cpu_batch_request.json does not match the contract" >&2
    FAILURES=$((FAILURES + 1))
  }

  jq -e '
    .profile_id == "gpu-single-v1" and
    (.parameters | keys | sort) == ["run_label"]
  ' "${template_dir}/example_gpu_single_request.json" >/dev/null || {
    echo "example_gpu_single_request.json does not match the contract" >&2
    FAILURES=$((FAILURES + 1))
  }
}

validate_run_dir() {
  local result_dir=$1

  check_file "${result_dir}/B95_RESULT.md"
  check_file "${result_dir}/profiles-response.json"
  check_file "${result_dir}/cpu-short-submit.txt"
  check_file "${result_dir}/cpu-short-status.txt"
  check_file "${result_dir}/cpu-short-artifact.txt"
  check_file "${result_dir}/cpu-batch-submit.txt"
  check_file "${result_dir}/cpu-batch-status.txt"
  check_file "${result_dir}/cpu-batch-artifact.txt"
  check_file "${result_dir}/gpu-submit.txt"
  check_file "${result_dir}/gpu-status.txt"
  check_file "${result_dir}/gpu-artifact.txt"
  check_file "${result_dir}/final-cluster-health.txt"

  for profile in cpu-short-v1 cpu-batch-v1 gpu-single-v1; do
    if ! grep -Fq "${profile}" "${result_dir}/profiles-response.json"; then
      echo "profiles response missing ${profile}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done

  check_http_status_ok "${result_dir}/cpu-short-submit.txt" "cpu-short submit"
  check_http_status_ok "${result_dir}/cpu-short-status.txt" "cpu-short status"
  check_http_status_ok "${result_dir}/cpu-short-artifact.txt" "cpu-short artifact"
  check_http_status_ok "${result_dir}/cpu-batch-submit.txt" "cpu-batch submit"
  check_http_status_ok "${result_dir}/cpu-batch-status.txt" "cpu-batch status"
  check_http_status_ok "${result_dir}/cpu-batch-artifact.txt" "cpu-batch artifact"
  check_http_status_ok "${result_dir}/gpu-submit.txt" "gpu submit"
  check_http_status_ok "${result_dir}/gpu-status.txt" "gpu status"
  check_http_status_ok "${result_dir}/gpu-artifact.txt" "gpu artifact"

  for path in \
    "${result_dir}/cpu-short-status.txt" \
    "${result_dir}/cpu-batch-status.txt" \
    "${result_dir}/gpu-status.txt"; do
    if ! grep -Eq 'COMPLETED|SUCCEEDED|SUCCESS' "${path}"; then
      echo "terminal success state missing from ${path}" >&2
      FAILURES=$((FAILURES + 1))
    fi
  done
}

validate_contracts

if [[ -n "${RUN_DIR}" ]]; then
  validate_run_dir "${RUN_DIR}"
fi

if (( FAILURES > 0 )); then
  echo "validation failed with ${FAILURES} issue(s)" >&2
  exit 1
fi

if [[ -n "${RUN_DIR}" ]]; then
  echo "B9.5 contracts and run artifacts validated: ${RUN_DIR}"
else
  echo "B9.5 contracts validated"
fi
