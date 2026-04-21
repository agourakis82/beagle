#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_NODE="${K8S_NODE_NAME:-${TARGET_NODE:-r770-proxmox}}"

if [[ -n "${SLURM_NODE_NAME:-}" ]]; then
  expected="gpuorangefs-${TARGET_NODE}"
  if [[ "${SLURM_NODE_NAME}" != "${expected}" ]]; then
    echo "warning: SLURM_NODE_NAME=${SLURM_NODE_NAME} does not match expected ${expected}; using TARGET_NODE=${TARGET_NODE}" >&2
  fi
fi

TARGET_NODE="${TARGET_NODE}" exec "${SCRIPT_DIR}/66-validate-gpuorangefs-node.sh"
