#!/usr/bin/env bash
# Alias canónico B25.3 — delega em validate_workbench_orchestration_smoke.sh
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
exec "${ROOT}/scripts/infrastructure/darwin-hpc/validate_workbench_orchestration_smoke.sh" "$@"
