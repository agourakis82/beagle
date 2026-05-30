#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
GATE="${GPU_FABRIC_GATE:-${SCRIPT_DIR}/gpu-fabric-gate.sh}"

MODE="watch"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-0}"
TRANSPORT="${TRANSPORT:-ib}"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/artifacts/gpu-fabric-smoke-watch}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
  cat <<'EOF'
usage: gpu-fabric-smoke-watch.sh [--watch|--run-on-ready] [--interval SECONDS] [--max-attempts N] [--transport socket|ib]

Wait for the dedicated GPU fabric gate to become ready.

Modes:
  --watch         Observe readiness only. This is the default and never creates smoke jobs.
  --run-on-ready  Run exactly one phase3-smoke when phase3-ib-ready succeeds.

Safety:
  - Does not override gpu-lease.
  - Does not cancel Slurm jobs.
  - Does not create smoke jobs unless --run-on-ready is explicit.
  - Stops after --max-attempts when N > 0; otherwise watches until ready.

Environment:
  INTERVAL_SECONDS  default 60
  MAX_ATTEMPTS      default 0, meaning unlimited
  TRANSPORT         default ib
  LOG_DIR           default artifacts/gpu-fabric-smoke-watch
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      MODE="watch"
      shift
      ;;
    --run-on-ready)
      MODE="run-on-ready"
      shift
      ;;
    --interval)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --max-attempts)
      MAX_ATTEMPTS="${2:-}"
      shift 2
      ;;
    --transport)
      TRANSPORT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${MODE}" in
  watch|run-on-ready) ;;
  *) echo "invalid mode: ${MODE}" >&2; exit 2 ;;
esac

case "${TRANSPORT}" in
  socket|ib) ;;
  *) echo "invalid transport: ${TRANSPORT}" >&2; exit 2 ;;
esac

if ! [[ "${INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${INTERVAL_SECONDS}" -lt 5 ]]; then
  echo "--interval must be an integer >= 5" >&2
  exit 2
fi

if ! [[ "${MAX_ATTEMPTS}" =~ ^[0-9]+$ ]]; then
  echo "--max-attempts must be an integer >= 0" >&2
  exit 2
fi

[[ -x "${GATE}" ]] || {
  echo "gpu fabric gate is not executable: ${GATE}" >&2
  exit 1
}

mkdir -p "${LOG_DIR}"
summary="${LOG_DIR}/${RUN_ID}.summary.log"

log() {
  local line
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"
  echo "${line}" | tee -a "${summary}"
}

attempt=0
log "mode=${MODE} transport=${TRANSPORT} interval=${INTERVAL_SECONDS}s max_attempts=${MAX_ATTEMPTS}"

while true; do
  attempt=$((attempt + 1))
  ready_log="${LOG_DIR}/${RUN_ID}.attempt-${attempt}.ready.log"
  log "attempt=${attempt} checking phase3-ib-ready"

  if "${GATE}" phase3-ib-ready >"${ready_log}" 2>&1; then
    log "attempt=${attempt} ready=pass log=${ready_log}"
    if [[ "${MODE}" == "watch" ]]; then
      log "watch mode complete; next command: ${GATE} phase3-smoke --transport ${TRANSPORT}"
      exit 0
    fi

    smoke_log="${LOG_DIR}/${RUN_ID}.smoke-${TRANSPORT}.log"
    log "running smoke: ${GATE} phase3-smoke --transport ${TRANSPORT}"
    "${GATE}" phase3-smoke --transport "${TRANSPORT}" >"${smoke_log}" 2>&1
    log "smoke complete log=${smoke_log}"
    exit 0
  fi

  log "attempt=${attempt} ready=not-ready log=${ready_log}"

  if [[ "${MAX_ATTEMPTS}" -gt 0 && "${attempt}" -ge "${MAX_ATTEMPTS}" ]]; then
    log "max attempts reached; leaving without smoke"
    exit 1
  fi

  sleep "${INTERVAL_SECONDS}"
done
