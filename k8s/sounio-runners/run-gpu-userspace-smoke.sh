#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <node-hostname> <accelerator-label> [pod-name]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_HOSTNAME="$1"
ACCELERATOR_LABEL="$2"
POD_NAME="${3:-gpu-userspace-smoke-${NODE_HOSTNAME}}"

sudo kubectl -n beagle delete pod "${POD_NAME}" --ignore-not-found >/dev/null
"${ROOT_DIR}/render-gpu-userspace-smoke.sh" "${NODE_HOSTNAME}" "${ACCELERATOR_LABEL}" "${POD_NAME}" | sudo kubectl apply -f -
echo "${POD_NAME}"
