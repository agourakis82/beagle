#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_ID=${RUN_ID:?RUN_ID is required}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/retention-enforcement"

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

main() {
  require_cmd grep
  require_cmd python3

  check_file "${RESULT_DIR}/B104_RESULT.md"
  check_file "${RESULT_DIR}/enforcement-plan.txt"
  check_file "${RESULT_DIR}/deleted-objects.txt"
  check_file "${RESULT_DIR}/preserved-objects.txt"
  check_file "${RESULT_DIR}/post-delete-head.txt"
  check_file "${RESULT_DIR}/final-cluster-health.txt"

  grep -q '^GO$' <(sed -n '4p' "${RESULT_DIR}/B104_RESULT.md")
  grep -q 'hpc-retention-canary/' "${RESULT_DIR}/enforcement-plan.txt"
  grep -q 'production_prefix_guard=hpc/' "${RESULT_DIR}/enforcement-plan.txt"
  grep -q 'deleted-confirmed' "${RESULT_DIR}/deleted-objects.txt"
  grep -q 'preserved' "${RESULT_DIR}/preserved-objects.txt"
  grep -q 'canary_deleted_confirmed' "${RESULT_DIR}/post-delete-head.txt"
  grep -q $'production_prefix_delta\t0' "${RESULT_DIR}/post-delete-head.txt"
  grep -q 'slurmctld=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'slurmrestd=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 't560-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'r770-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q '5860-proxmox' "${RESULT_DIR}/final-cluster-health.txt"

  python3 - <<'PY' "${RESULT_DIR}/deleted-objects.txt" "${RESULT_DIR}/preserved-objects.txt"
import sys

deleted = [line.split("\t") for line in open(sys.argv[1], "r", encoding="utf-8").read().splitlines()[2:] if line.strip()]
preserved = [line.split("\t") for line in open(sys.argv[2], "r", encoding="utf-8").read().splitlines()[2:] if line.strip()]

if len(deleted) != 4:
    raise SystemExit(f"expected 4 deleted canary objects, got {len(deleted)}")

for key, status in deleted:
    if not key.startswith("hpc-retention-canary/"):
        raise SystemExit(f"non-canary key in deleted list: {key}")
    if status != "deleted-confirmed":
        raise SystemExit(f"unexpected deleted status for {key}: {status}")

if not preserved:
    raise SystemExit("no preserved production objects were recorded")

for row in preserved:
    key = row[0]
    status = row[1]
    if not key.startswith("hpc/"):
        raise SystemExit(f"preserved key not under production prefix: {key}")
    if key.startswith("hpc-retention-canary/"):
        raise SystemExit(f"canary key leaked into preserved list: {key}")
    if status != "preserved":
        raise SystemExit(f"unexpected preserved status for {key}: {status}")
PY

  echo "[OK] B10.4 lifecycle enforcement canary validation passed"
}

main "$@"
