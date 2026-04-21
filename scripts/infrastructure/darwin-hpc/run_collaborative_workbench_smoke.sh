#!/usr/bin/env bash
# Canonical alias for B25.2 smoke (same as run_collaborative_compute_experiment_workbench_smoke.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec bash "${ROOT}/scripts/infrastructure/darwin-hpc/run_collaborative_compute_experiment_workbench_smoke.sh" "$@"
