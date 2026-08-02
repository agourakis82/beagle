#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: preload-node-local-images.sh <target-node> <loader-image> <image-ref> [image-ref...]

Exports one or more local `localhost/...` images from the current node,
creates a temporary privileged loader pod on the target Kubernetes node,
copies the image archives into the host filesystem, and imports them into the
target node's containerd `k8s.io` namespace.

Examples:
  preload-node-local-images.sh \
    r740-proxmox \
    localhost/project-cockpit:20260406-6 \
    localhost/sounio-workspace-ide:0406231500 \
    localhost/beagle-workspace-ssh:b216

  preload-node-local-images.sh \
    t560-proxmox \
    localhost/beagle-workspace-ssh:b216 \
    localhost/sounio-workspace-ide:0406231500
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

TARGET_NODE="$1"
LOADER_IMAGE="$2"
shift 2
IMAGES=("$@")

NAMESPACE="${NAMESPACE:-beagle}"
WORKDIR="$(mktemp -d /tmp/node-local-image-preload.XXXXXX)"
LOADER_POD="image-loader-${TARGET_NODE//[^a-zA-Z0-9-]/-}-$(date +%H%M%S)"

cleanup() {
  kubectl -n "${NAMESPACE}" delete pod "${LOADER_POD}" --wait=false >/dev/null 2>&1 || true
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

require kubectl
require sudo
require ctr
require podman

cat > "${WORKDIR}/loader-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${LOADER_POD}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: node-local-image-loader
    app.kubernetes.io/part-of: beagle
spec:
  restartPolicy: Never
  nodeName: ${TARGET_NODE}
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: sounio.dev/compute
      operator: Equal
      value: heavy
      effect: NoSchedule
    - key: sounio.dev/pool
      operator: Equal
      value: gpu-batch
      effect: NoSchedule
  containers:
    - name: loader
      image: ${LOADER_IMAGE}
      imagePullPolicy: IfNotPresent
      command:
        - /bin/sh
        - -lc
        - sleep infinity
      securityContext:
        privileged: true
        runAsUser: 0
      volumeMounts:
        - name: host-root
          mountPath: /host
  volumes:
    - name: host-root
      hostPath:
        path: /
        type: Directory
EOF

echo "[INFO] creating loader pod ${LOADER_POD} on ${TARGET_NODE}"
kubectl apply -f "${WORKDIR}/loader-pod.yaml" >/dev/null
kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${LOADER_POD}" --timeout=180s >/dev/null

for image_ref in "${IMAGES[@]}"; do
  archive_name="$(echo "${image_ref}" | tr '/:@' '_').tar"
  archive_path="${WORKDIR}/${archive_name}"

  echo "[INFO] exporting ${image_ref}"
  if sudo ctr -n k8s.io images export "${archive_path}" "${image_ref}" >/dev/null 2>&1; then
    :
  elif podman image exists "${image_ref}" >/dev/null 2>&1; then
    podman image save -o "${archive_path}" "${image_ref}"
  else
    echo "[FAIL] image not found in containerd or podman: ${image_ref}" >&2
    exit 1
  fi

  echo "[INFO] copying ${image_ref} archive to ${TARGET_NODE}"
  kubectl cp "${archive_path}" "${NAMESPACE}/${LOADER_POD}:/host/tmp/${archive_name}" >/dev/null

  echo "[INFO] importing ${image_ref} into ${TARGET_NODE} containerd"
  kubectl -n "${NAMESPACE}" exec "${LOADER_POD}" -- \
    chroot /host ctr -n k8s.io images import "/tmp/${archive_name}" >/dev/null
done

echo "[OK] imported ${#IMAGES[@]} image(s) into ${TARGET_NODE}"
