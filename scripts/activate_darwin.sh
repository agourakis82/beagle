#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   source scripts/activate_darwin.sh
#
# Purpose:
# - Make darwin-* binaries discoverable in shells by adding common install dirs to PATH.
# - Set BEAGLE_WORKSPACE_ROOT to this repo (if unset) for Core/MCP helpers.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "note: run this as: source $0" >&2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BEAGLE_WORKSPACE_ROOT="${BEAGLE_WORKSPACE_ROOT:-$REPO_ROOT}"

prepend_path() {
  local dir="$1"
  if [[ -z "${dir}" ]] || [[ ! -d "${dir}" ]]; then
    return 0
  fi
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *) export PATH="${dir}:${PATH}" ;;
  esac
}

prepend_path "${HOME:-/root}/.cargo/bin"
prepend_path "${HOME:-/root}/.local/bin"
prepend_path "/usr/local/bin"

echo "BEAGLE_WORKSPACE_ROOT=${BEAGLE_WORKSPACE_ROOT}"
echo "PATH=${PATH}"

