#!/usr/bin/env bash
set -euo pipefail

repo_root="/home/devsounio/beagle"
context_dir="${repo_root}/docker/sglang-dynamo"
tag="${1:-192.168.3.207:5003/sounio-sglang-dynamo-runtime:$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 3)}"
podman_root="${PODMAN_ROOT:-/tmp/podman-sglang-root}"
podman_runroot="${PODMAN_RUNROOT:-/tmp/podman-sglang-runroot}"
tmpdir="${TMPDIR:-/tmp}"
podman_isolation="${PODMAN_BUILD_ISOLATION:-chroot}"
podman_cgroup_manager="${PODMAN_CGROUP_MANAGER:-cgroupfs}"

mkdir -p "${podman_root}" "${podman_runroot}" "${tmpdir}"

podman \
  --root "${podman_root}" \
  --runroot "${podman_runroot}" \
  --cgroup-manager "${podman_cgroup_manager}" \
  build \
  --isolation "${podman_isolation}" \
  -f "${context_dir}/Dockerfile" \
  -t "${tag}" \
  "${context_dir}"

podman \
  --root "${podman_root}" \
  --runroot "${podman_runroot}" \
  --cgroup-manager "${podman_cgroup_manager}" \
  push --tls-verify=false "${tag}"

printf '%s\n' "${tag}"
