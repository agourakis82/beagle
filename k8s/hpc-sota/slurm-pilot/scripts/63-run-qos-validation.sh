#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/slurm-pilot}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${LOG_DIR}"

{
  echo "[$(date --iso-8601=seconds)] starting Slurm QoS validation"
  sudo bash "${REPO_ROOT}/scripts/59-prove-burst-priority.sh"
  echo "--- qos validation artifacts ---"
  find /var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/slurm-pilot/qos-proof -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
  echo "[$(date --iso-8601=seconds)] completed Slurm QoS validation"
} | tee "${LOG_DIR}/qos-validation-${STAMP}.log"
