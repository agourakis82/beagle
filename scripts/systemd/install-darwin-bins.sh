#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/systemd/install-darwin-bins.sh [--root /usr/local] [--no-web] [--offline]

Installs DARWIN ResearchOps binaries (from crates/beagle-rag-update) into <root>/bin.
Recommended for systemd: /usr/local/bin

Notes:
  - Requires Rust toolchain and network access (crates.io) unless your cache is warm.
  - If you install without --root, binaries land in ~/.cargo/bin (update PATH accordingly).
  - If /usr/local is not writable in your environment, use: --root "$HOME/.local"
  - If crates.io is unreachable, try: --offline (requires a warm cargo cache).
EOF
}

ROOT="/usr/local"
INCLUDE_WEB="1"
ROOT_EXPLICIT="0"
OFFLINE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --root)
      ROOT="${2:-}"
      ROOT_EXPLICIT="1"
      shift 2
      ;;
    --no-web)
      INCLUDE_WEB="0"
      shift
      ;;
    --offline)
      OFFLINE="1"
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${ROOT}" ]]; then
  echo "--root requires a value" >&2
  exit 2
fi

autofix_root() {
  local requested="$1"
  local explicit="$2"
  local fallback="${HOME:-/root}/.local"

  if mkdir -p "${requested}/bin" 2>/dev/null; then
    local testfile="${requested}/.beagle_write_test"
    if ( : > "${testfile}" ) 2>/dev/null; then
      rm -f "${testfile}" || true
      echo "${requested}"
      return 0
    fi
  fi

  if [[ "${explicit}" == "1" ]]; then
    echo "Cannot write to --root: ${requested}" >&2
    echo "Pick another destination, e.g.: --root \"${fallback}\"" >&2
    exit 1
  fi

  mkdir -p "${fallback}/bin"
  echo "warning: ${requested} not writable; using ${fallback}" >&2
  echo "${fallback}"
}

ROOT="$(autofix_root "${ROOT}" "${ROOT_EXPLICIT}")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CRATE_PATH="${REPO_ROOT}/crates/beagle-rag-update"

if [[ ! -f "${CRATE_PATH}/Cargo.toml" ]]; then
  echo "Expected darwin crate at: ${CRATE_PATH}" >&2
  exit 1
fi

bins=(
  darwin-incremental-indexer
  darwin-research-harvester
  darwin-knowledge-manager
  darwin-eval
  darwin-brief
)
if [[ "${INCLUDE_WEB}" == "1" ]]; then
  bins+=(darwin-web-harvester)
fi

install_flags=(--locked)
if [[ "${OFFLINE}" == "1" ]]; then
  install_flags+=(--offline)
fi

echo "Installing DARWIN binaries from ${CRATE_PATH}"
echo "Destination root: ${ROOT} (bin dir: ${ROOT}/bin)"
echo

for bin in "${bins[@]}"; do
  echo "==> ${bin}"
  cargo install "${install_flags[@]}" --path "${CRATE_PATH}" --bin "${bin}" --root "${ROOT}"
done

echo
echo "Done."
echo "If commands still aren't found:"
echo "  export PATH=\"${ROOT}/bin:\$PATH\""
