#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${root}/cutover-gpu-fabric-10-210.sh" "$@"
