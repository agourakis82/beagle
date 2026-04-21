#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-5}"
export KUBECONFIG="${KUBECONFIG_PATH}"

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  if kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc 'sacctmgr list cluster >/dev/null 2>&1' >/dev/null 2>&1; then
    echo "slurm accounting API is ready"
    exit 0
  fi
  sleep "${INTERVAL_SECONDS}"
done

echo "timed out waiting for slurm accounting API readiness" >&2
exit 1
