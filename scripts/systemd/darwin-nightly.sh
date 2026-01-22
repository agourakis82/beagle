#!/usr/bin/env bash
set -euo pipefail

CURRENT_STEP=""

post_webhook() {
  local url="$1"
  local payload="$2"
  if [[ -z "${url}" ]]; then
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsS -X POST -H 'Content-Type: application/json' --data "${payload}" "${url}" >/dev/null || true
  fi
}

notify_error() {
  local exit_code="$1"
  local step="$2"
  local cmd="$3"

  local url="${DARWIN_NIGHTLY_ERROR_WEBHOOK_URL:-}"
  if [[ -z "${url}" ]]; then
    return 0
  fi

  local payload
  payload="$(
    python3 - <<'PY' "${exit_code}" "${step}" "${cmd}"
import json
import socket
import sys
from datetime import datetime, timezone

exit_code = int(sys.argv[1])
step = sys.argv[2]
cmd = sys.argv[3]

print(
    json.dumps(
        {
            "event": "darwin_nightly_error",
            "at": datetime.now(timezone.utc).isoformat(),
            "host": socket.gethostname(),
            "step": step,
            "exit_code": exit_code,
            "command": cmd,
        }
    )
)
PY
  )"

  post_webhook "${url}" "${payload}"
}

notify_success() {
  local url="${DARWIN_NIGHTLY_SUCCESS_WEBHOOK_URL:-}"
  if [[ -z "${url}" ]]; then
    return 0
  fi

  local payload
  payload="$(
    python3 - <<'PY'
import json
import socket
from datetime import datetime, timezone

print(
    json.dumps(
        {
            "event": "darwin_nightly_success",
            "at": datetime.now(timezone.utc).isoformat(),
            "host": socket.gethostname(),
        }
    )
)
PY
  )"

  post_webhook "${url}" "${payload}"
}

on_err() {
  local code="$1"
  local cmd="$2"
  notify_error "${code}" "${CURRENT_STEP}" "${cmd}"
  exit "${code}"
}
trap 'on_err $? "${BASH_COMMAND}"' ERR

run_shell() {
  local name="$1"
  shift
  local cmd="$1"
  CURRENT_STEP="${name}"
  echo "==> ${name}"
  /usr/bin/env bash -lc "${cmd}"
}

# Toggle which parts to run via env vars.
DARWIN_NIGHTLY_RUN_INDEXER="${DARWIN_NIGHTLY_RUN_INDEXER:-0}"
DARWIN_NIGHTLY_RUN_RESEARCH="${DARWIN_NIGHTLY_RUN_RESEARCH:-1}"
DARWIN_NIGHTLY_RUN_WEB="${DARWIN_NIGHTLY_RUN_WEB:-0}"
DARWIN_NIGHTLY_RUN_BRIEF="${DARWIN_NIGHTLY_RUN_BRIEF:-0}"
DARWIN_NIGHTLY_RUN_EVAL="${DARWIN_NIGHTLY_RUN_EVAL:-1}"

resolve_darwin_bin_dir() {
  if [[ -n "${DARWIN_BIN_DIR:-}" ]]; then
    echo "${DARWIN_BIN_DIR%/}"
    return 0
  fi

  # Prefer binaries already on PATH.
  for bin in darwin-brief darwin-research-harvester darwin-eval darwin-incremental-indexer; do
    local found
    found="$(command -v "${bin}" 2>/dev/null || true)"
    if [[ -n "${found}" ]]; then
      dirname "${found}"
      return 0
    fi
  done

  # Fallback to common install locations.
  local home="${HOME:-}"
  local home_cargo="${home:+${home%/}/.cargo/bin}"
  for dir in /usr/local/bin /usr/bin /root/.cargo/bin "${home_cargo:-}"; do
    if [[ -z "${dir}" ]]; then
      continue
    fi
    if [[ -x "${dir}/darwin-brief" ]] \
      || [[ -x "${dir}/darwin-research-harvester" ]] \
      || [[ -x "${dir}/darwin-eval" ]] \
      || [[ -x "${dir}/darwin-incremental-indexer" ]]; then
      echo "${dir}"
      return 0
    fi
  done

  echo "/usr/local/bin"
}

DARWIN_BIN_DIR="$(resolve_darwin_bin_dir)"
DARWIN_BIN_DIR="${DARWIN_BIN_DIR%/}"
echo "DARWIN_BIN_DIR=${DARWIN_BIN_DIR}"

ensure_executable() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "Missing executable: ${path}" >&2
    echo "Hint: install with: sudo bash scripts/systemd/install-darwin-bins.sh --root /usr/local" >&2
    echo "Or set: DARWIN_BIN_DIR=/path/to/bin (e.g., /root/.cargo/bin)" >&2
    exit 127
  fi
}

if [[ "${DARWIN_NIGHTLY_RUN_INDEXER}" == "1" ]]; then
  ensure_executable "${DARWIN_BIN_DIR}/darwin-incremental-indexer"
  run_shell "indexer" "${DARWIN_BIN_DIR}/darwin-incremental-indexer --sync ${DARWIN_INDEX_ARGS:-}"
fi

if [[ "${DARWIN_NIGHTLY_RUN_RESEARCH}" == "1" ]]; then
  ensure_executable "${DARWIN_BIN_DIR}/darwin-research-harvester"
  run_shell "research_harvester" "${DARWIN_BIN_DIR}/darwin-research-harvester ${DARWIN_HARVEST_ARGS:-}"
fi

if [[ "${DARWIN_NIGHTLY_RUN_WEB}" == "1" ]]; then
  ensure_executable "${DARWIN_BIN_DIR}/darwin-web-harvester"
  run_shell "web_harvester" "${DARWIN_BIN_DIR}/darwin-web-harvester ${DARWIN_WEB_HARVEST_ARGS:-}"
fi

if [[ "${DARWIN_NIGHTLY_RUN_BRIEF}" == "1" ]]; then
  ensure_executable "${DARWIN_BIN_DIR}/darwin-brief"
  run_shell "brief" "${DARWIN_BIN_DIR}/darwin-brief ${DARWIN_BRIEF_ARGS:-}"
fi

if [[ "${DARWIN_NIGHTLY_RUN_EVAL}" == "1" ]]; then
  ensure_executable "${DARWIN_BIN_DIR}/darwin-eval"
  run_shell "eval" "${DARWIN_BIN_DIR}/darwin-eval ${DARWIN_EVAL_ARGS:-}"
fi

notify_success
