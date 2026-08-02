#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
RELEASE="${RELEASE:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" get pods,svc,pvc

LOGIN_POD="$(
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" get pods -o name \
    | grep -E 'login|slinky' \
    | head -n1 \
    | sed 's#pod/##'
)"

if [[ -z "${LOGIN_POD}" ]]; then
  echo "could not find a Slurm login pod in namespace ${NS}" >&2
  exit 1
fi

echo "[validate] using login pod ${LOGIN_POD}"
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc '
  set -euo pipefail
  scontrol ping
  echo ---
  sinfo
  echo ---
  scontrol show nodes | sed -n "1,120p"
'
