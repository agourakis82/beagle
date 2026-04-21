#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/study-proposal-dispatch}"

SMOKE_FILE="${OUT}/smoke.json"
DISPATCH_FILE="${OUT}/study-proposal-dispatch-get.json"

if [[ ! -f "${SMOKE_FILE}" ]]; then
  echo "[FAIL] smoke.json not found" >&2
  exit 1
fi

if [[ ! -f "${DISPATCH_FILE}" ]]; then
  echo "[FAIL] study-proposal-dispatch-get.json not found" >&2
  exit 1
fi

# Validate smoke.json
if ! jq -e '
  .status == "ok" and
  .phase == "B26.3" and
  .dispatch_id != null and
  .dispatch_id != "unknown" and
  .study_id != null and
  .same_beagle_owned_identity == true
' "${SMOKE_FILE}" >/dev/null 2>&1; then
  echo "[FAIL] smoke.json validation failed" >&2
  jq '.' "${SMOKE_FILE}" >&2
  exit 1
fi

echo "[OK] B26.3 study proposal dispatch validation passed"
jq '{
  phase: .phase,
  status: .status,
  dispatch_created: .dispatch_created,
  dispatch_id: .dispatch_id,
  study_id: .study_id,
  workspace_id: .workspace_id,
  b266_baseline_preserved: .b266_baseline_preserved
}' "${SMOKE_FILE}"
