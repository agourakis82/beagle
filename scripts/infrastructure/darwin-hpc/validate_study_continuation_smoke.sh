#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/study-continuation}"

SMOKE_FILE="${OUT}/smoke.json"

if [[ ! -f "${SMOKE_FILE}" ]]; then
  echo "[FAIL] smoke.json not found at ${SMOKE_FILE}" >&2
  exit 1
fi

# Check if this is a live test with endpoint verification
if jq -e '.endpoint_verified == true' "${SMOKE_FILE}" >/dev/null 2>&1; then
  echo "[OK] B27.1 LIVE — Endpoint verified and functional"
  jq '{
    phase: .phase,
    status: .status,
    live_cluster: .live_cluster,
    endpoint_verified: .endpoint_verified,
    http_response_code: .http_response_code,
    dependencies: .dependencies
  }' "${SMOKE_FILE}"
  exit 0
fi

# Full data validation (when study continuation state exists)
CONTINUATION_FILE="${OUT}/study-continuation-state.json"
if [[ -f "${CONTINUATION_FILE}" ]]; then
  if ! jq -e '
    .continuation_state_id != null and
    .study_id != null and
    .workstream_id != null and
    .workspace_id != null
  ' "${CONTINUATION_FILE}" >/dev/null 2>&1; then
    echo "[FAIL] study-continuation-state.json validation failed" >&2
    exit 1
  fi
  echo "[OK] B27.1 study continuation smoke validation passed (with data)"
  exit 0
fi

# Default validation
if ! jq -e '
  .status == "ok" and
  .phase == "B27.1"
' "${SMOKE_FILE}" >/dev/null 2>&1; then
  echo "[FAIL] smoke.json validation failed" >&2
  jq '.' "${SMOKE_FILE}" >&2
  exit 1
fi

echo "[OK] B27.1 study continuation smoke validation passed"
jq '{
  phase: .phase,
  status: .status
}' "${SMOKE_FILE}"
