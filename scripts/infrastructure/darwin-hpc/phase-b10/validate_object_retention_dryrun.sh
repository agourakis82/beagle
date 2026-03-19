#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_ID=${RUN_ID:?RUN_ID is required}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/retention"
RETENTION_POLICY=${RETENTION_POLICY:-"${CONTRACT_ROOT}/object-retention-policy.yaml"}

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

check_file() {
  local path=$1
  [[ -f "${path}" && -s "${path}" ]] || {
    echo "missing or empty file: ${path}" >&2
    exit 1
  }
}

ensure_python_dep() {
  if python3 - <<'PY' >/dev/null 2>&1
import importlib.util
import sys
mods = ("yaml",)
sys.exit(0 if all(importlib.util.find_spec(name) for name in mods) else 1)
PY
  then
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y python3-yaml >/dev/null
}

main() {
  require_cmd grep
  require_cmd python3

  check_file "${RETENTION_POLICY}"
  check_file "${RESULT_DIR}/B103_RESULT.md"
  check_file "${RESULT_DIR}/retention-plan.txt"
  check_file "${RESULT_DIR}/retention-dryrun.txt"
  check_file "${RESULT_DIR}/candidate-objects.txt"
  check_file "${RESULT_DIR}/final-cluster-health.txt"

  ensure_python_dep
  python3 - <<'PY' "${RETENTION_POLICY}"
import sys
import yaml

policy = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert policy["execution"]["destructive_mode_default"] is False
assert policy["execution"]["first_canonical_run_mode"] == "dry-run-only"
assert policy["target"]["bucket"] == "darwin-hpc-artifacts"
assert policy["target"]["forbidden_bucket"] == "darwin-k8s-backups"
assert policy["profiles"]["cpu-short-v1"]["artifact_rules"]["artifact-manifest.json"]["retain_days"] > policy["profiles"]["cpu-short-v1"]["artifact_rules"]["artifact.bin"]["retain_days"]
assert policy["profiles"]["cpu-batch-v1"]["artifact_rules"]["artifact-manifest.json"]["retain_days"] > policy["profiles"]["cpu-batch-v1"]["artifact_rules"]["artifact.bin"]["retain_days"]
assert policy["profiles"]["gpu-single-v1"]["artifact_rules"]["artifact-manifest.json"]["retain_days"] > policy["profiles"]["gpu-single-v1"]["artifact_rules"]["artifact.bin"]["retain_days"]
PY

  grep -q 'cpu-short-v1' "${RESULT_DIR}/candidate-objects.txt"
  grep -q 'cpu-batch-v1' "${RESULT_DIR}/candidate-objects.txt"
  grep -q 'gpu-single-v1' "${RESULT_DIR}/candidate-objects.txt"
  grep -q 'artifact-manifest.json' "${RESULT_DIR}/candidate-objects.txt"
  grep -q 'dry-run-only' "${RESULT_DIR}/retention-dryrun.txt"
  grep -q 'slurmctld=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'slurmrestd=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 't560-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'r770-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q '5860-proxmox' "${RESULT_DIR}/final-cluster-health.txt"

  echo "[OK] B10.3 retention dry-run validation passed"
}

main "$@"
