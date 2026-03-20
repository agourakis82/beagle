#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${IMAGE_REF:-beagle-core:dev}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/beagle-core-dev.oci.tar}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require sudo
require podman
require ctr

echo "[INFO] saving ${IMAGE_REF} to ${ARCHIVE_PATH}"
sudo podman image exists "${IMAGE_REF}" || {
  echo "[FAIL] image not found locally: ${IMAGE_REF}" >&2
  exit 1
}

sudo podman save --format oci-archive -o "${ARCHIVE_PATH}" "${IMAGE_REF}"

echo "[INFO] importing image into containerd k8s namespace"
sudo ctr -n k8s.io images import "${ARCHIVE_PATH}"

echo "[INFO] imported images matching beagle-core"
sudo ctr -n k8s.io images ls | rg 'beagle-core' || true

echo "[OK] image load completed"
