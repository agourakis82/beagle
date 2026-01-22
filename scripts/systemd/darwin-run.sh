#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/systemd/darwin-run.sh <binary> [args...]

Resolves a darwin-* binary robustly for systemd/cron:
- Uses $DARWIN_BIN_DIR if set and executable exists
- Otherwise uses PATH
- Otherwise falls back to common locations: /usr/local/bin, /usr/bin, /bin, ~/.cargo/bin
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

BIN_NAME="$1"
shift

resolve_bin() {
  local name="$1"

  if [[ -n "${DARWIN_BIN_DIR:-}" ]]; then
    local candidate="${DARWIN_BIN_DIR%/}/${name}"
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  fi

  local found
  found="$(command -v "${name}" 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return 0
  fi

  local home="${HOME:-}"
  local cargo_bin=""
  if [[ -n "${home}" ]]; then
    cargo_bin="${home%/}/.cargo/bin"
  fi

  for dir in /usr/local/bin /usr/bin /bin /root/.cargo/bin "${cargo_bin}"; do
    if [[ -z "${dir}" ]]; then
      continue
    fi
    local candidate="${dir%/}/${name}"
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  return 1
}

BIN_PATH="$(resolve_bin "${BIN_NAME}" || true)"
if [[ -z "${BIN_PATH}" ]]; then
  echo "Binary not found: ${BIN_NAME}" >&2
  echo "Hint: install darwin-* binaries (recommended):" >&2
  echo "  sudo bash scripts/systemd/install-darwin-bins.sh --root /usr/local" >&2
  echo "Or run without systemd:" >&2
  echo "  cargo run -p beagle-rag-update --bin ${BIN_NAME} -- --help" >&2
  echo "Or set DARWIN_BIN_DIR to where you installed them (e.g. ~/.cargo/bin)." >&2
  exit 127
fi

exec "${BIN_PATH}" "$@"

