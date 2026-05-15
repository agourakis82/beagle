#!/usr/bin/env bash
#
# BEAGLE Rescue Check
# -------------------
# Small confidence check for the current recovery baseline. This intentionally
# avoids repo-wide lint/test gates that are still noisy from older work.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NPM_BIN="${NPM_BIN:-}"

if [ -z "$NPM_BIN" ]; then
  if command -v npm >/dev/null 2>&1; then
    NPM_BIN="$(command -v npm)"
  elif [ -x /opt/homebrew/bin/npm ]; then
    NPM_BIN="/opt/homebrew/bin/npm"
  elif [ -x /usr/local/bin/npm ]; then
    NPM_BIN="/usr/local/bin/npm"
  fi
fi

info() {
  printf '\n==> %s\n' "$1"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

run_npm() {
  local npm_dir
  npm_dir="$(dirname "$NPM_BIN")"
  run env "PATH=$npm_dir:$PATH" "$NPM_BIN" "$@"
}

cd "$ROOT_DIR"

info "Rust: observer compiles on this platform"
run cargo check -p beagle-observer --lib

info "Rust: hypergraph compiles without a live DATABASE_URL"
(
  unset DATABASE_URL
  run cargo check -p beagle-hypergraph --lib
)

info "Rust: core_server compiles"
run cargo check -p beagle-monorepo --bin core_server

info "Frontend: BEAGLE IDE production build"
if [ -z "$NPM_BIN" ]; then
  printf 'npm was not found. Install Node.js or set NPM_BIN=/path/to/npm.\n' >&2
  exit 127
fi
run_npm --prefix apps/beagle-ide run build

info "Tauri: BEAGLE IDE shell compiles"
run cargo check --manifest-path apps/beagle-ide/src-tauri/Cargo.toml

printf '\nBEAGLE rescue baseline is green.\n'
