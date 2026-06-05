#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"

SNAPSHOT_DIR="${SNAPSHOT_DIR:-}"
STRICT_EXIT=1
OUT_ROOT="${OUT_ROOT:-${SCRIPT_DIR}/artifacts/orangefs-multitb-gonogo}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUT_DIR="${OUT_DIR:-${OUT_ROOT}/${RUN_ID}}"
REPORT="${OUT_DIR}/GO_NOGO.md"
SUMMARY="${OUT_DIR}/summary.env"

usage() {
  cat <<'EOF'
usage: orangefs-multitb-gonogo.sh [--snapshot-dir PATH] [--always-zero]

Create a read-only go/no-go packet for the OrangeFS multi-TiB maintenance
window. This script does not apply changes. It runs:

  - orangefs-growth-gate.sh preflight
  - orangefs-multitb-maintenance-executor.sh --dry-run
  - orangefs-capacity-doctor.sh
  - sota-readiness-doctor.sh

If --snapshot-dir is omitted, the newest orangefs-maintenance-* artifact is
used. A fresh snapshot is still required for a real apply window.

By default, this exits 0 only for GO_FOR_EXPLICIT_MAINTENANCE_WINDOW_ONLY.
Use --always-zero to preserve report-only behavior.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot-dir)
      SNAPSHOT_DIR="${2:-}"
      shift 2
      ;;
    --always-zero)
      STRICT_EXIT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${SNAPSHOT_DIR}" ]]; then
  SNAPSHOT_DIR="$(find "${SCRIPT_DIR}/artifacts" -maxdepth 1 -type d -name 'orangefs-maintenance-*' | sort | tail -n 1)"
fi

if [[ -z "${SNAPSHOT_DIR}" || ! -d "${SNAPSHOT_DIR}" ]]; then
  echo "missing snapshot dir; run orangefs-maintenance-snapshot.sh first" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

run_capture() {
  local name="$1"
  shift
  local output="${OUT_DIR}/${name}.txt"
  local rc=0
  "$@" >"${output}" 2>&1 || rc=$?
  printf '%s_rc=%s\n' "${name//-/_}" "${rc}" >>"${SUMMARY}"
  printf '%s_log=%q\n' "${name//-/_}" "${output}" >>"${SUMMARY}"
  return "${rc}"
}

snapshot_age_hours() {
  python3 - "$1" <<'PY'
import os
import sys
import time

path = sys.argv[1]
age = (time.time() - os.stat(path).st_mtime) / 3600
print(f"{age:.2f}")
PY
}

: >"${SUMMARY}"
{
  printf 'run_id=%q\n' "${RUN_ID}"
  printf 'started_at_utc=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'snapshot_dir=%q\n' "${SNAPSHOT_DIR}"
  printf 'out_dir=%q\n' "${OUT_DIR}"
  printf 'strict_exit=%q\n' "${STRICT_EXIT}"
} >>"${SUMMARY}"

growth_rc=0
executor_rc=0
capacity_rc=0
sota_rc=0

run_capture "orangefs-growth-gate-preflight" "${SCRIPT_DIR}/orangefs-growth-gate.sh" preflight || growth_rc=$?
run_capture "orangefs-maintenance-executor-dry-run" \
  "${SCRIPT_DIR}/orangefs-multitb-maintenance-executor.sh" \
  --dry-run \
  --snapshot-dir "${SNAPSHOT_DIR}" || executor_rc=$?
run_capture "orangefs-capacity-doctor" "${SCRIPT_DIR}/orangefs-capacity-doctor.sh" || capacity_rc=$?
run_capture "sota-readiness-doctor" "${SCRIPT_DIR}/sota-readiness-doctor.sh" || sota_rc=$?

snapshot_age="$(snapshot_age_hours "${SNAPSHOT_DIR}/README.md")"
executor_report="$(grep -E '^report=' "${OUT_DIR}/orangefs-maintenance-executor-dry-run.txt" | tail -n 1 | cut -d= -f2- || true)"

decision="NO_GO"
reason="preflight_failed"
if [[ "${growth_rc}" -eq 0 && "${executor_rc}" -eq 0 && "${capacity_rc}" -eq 0 && "${sota_rc}" -eq 0 ]]; then
  decision="GO_FOR_EXPLICIT_MAINTENANCE_WINDOW_ONLY"
  reason="all_read_only_checks_passed"
fi

{
  printf 'snapshot_age_hours=%q\n' "${snapshot_age}"
  printf 'executor_report=%q\n' "${executor_report}"
  printf 'decision=%q\n' "${decision}"
  printf 'reason=%q\n' "${reason}"
  printf 'finished_at_utc=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >>"${SUMMARY}"

cat >"${REPORT}" <<EOF
# OrangeFS Multi-TiB Go/No-Go

- Run ID: \`${RUN_ID}\`
- Decision: \`${decision}\`
- Reason: \`${reason}\`
- Snapshot: \`${SNAPSHOT_DIR}\`
- Snapshot age hours: \`${snapshot_age}\`
- Output dir: \`${OUT_DIR}\`
- Executor report: \`${executor_report:-n/a}\`

## Checks

| Check | RC | Log |
| --- | ---: | --- |
| OrangeFS growth preflight | ${growth_rc} | \`${OUT_DIR}/orangefs-growth-gate-preflight.txt\` |
| Maintenance executor dry-run | ${executor_rc} | \`${OUT_DIR}/orangefs-maintenance-executor-dry-run.txt\` |
| OrangeFS capacity doctor | ${capacity_rc} | \`${OUT_DIR}/orangefs-capacity-doctor.txt\` |
| SOTA readiness doctor | ${sota_rc} | \`${OUT_DIR}/sota-readiness-doctor.txt\` |

## Apply Command

Only run during an explicit maintenance window:

\`\`\`bash
ORANGEFS_MULTITB_CONFIRM=APPLY \\
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-multitb-maintenance-executor.sh \\
  --apply \\
  --snapshot-dir ${SNAPSHOT_DIR}
\`\`\`

## Rollback Command

\`\`\`bash
ORANGEFS_MULTITB_CONFIRM=ROLLBACK \\
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-multitb-maintenance-executor.sh \\
  --rollback \\
  --snapshot-dir ${SNAPSHOT_DIR}
\`\`\`

## Safety

- This packet is read-only.
- \`GO_FOR_EXPLICIT_MAINTENANCE_WINDOW_ONLY\` is not permission to apply now.
- A fresh snapshot should be created immediately before the real window.
EOF

echo "decision=${decision}"
echo "report=${REPORT}"
if [[ "${STRICT_EXIT}" -eq 1 && "${decision}" != "GO_FOR_EXPLICIT_MAINTENANCE_WINDOW_ONLY" ]]; then
  exit 1
fi
exit 0
