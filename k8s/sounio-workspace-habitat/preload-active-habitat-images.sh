#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/devsounio/beagle"
STATEFULSET_FILE="${ROOT}/k8s/sounio-workspace-habitat/statefulset.yaml"
COCKPIT_DEPLOYMENT_FILE="${ROOT}/k8s/project-cockpit/deployment.yaml"
PRELOAD_SCRIPT="${ROOT}/k8s/workspace-platform/scripts/preload-node-local-images.sh"

TARGET_NODE="${1:-r740-proxmox}"
LOADER_IMAGE="${LOADER_IMAGE:-$(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "${COCKPIT_DEPLOYMENT_FILE}" | head -n 1)}"
IDE_IMAGE="$(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "${STATEFULSET_FILE}" | sed -n '1p')"
SSH_IMAGE="$(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "${STATEFULSET_FILE}" | sed -n '2p')"

if [[ -z "${LOADER_IMAGE}" || -z "${IDE_IMAGE}" || -z "${SSH_IMAGE}" ]]; then
  echo "[FAIL] could not derive loader or habitat images from manifests" >&2
  exit 1
fi

exec "${PRELOAD_SCRIPT}" "${TARGET_NODE}" "${LOADER_IMAGE}" "${IDE_IMAGE}" "${SSH_IMAGE}"
