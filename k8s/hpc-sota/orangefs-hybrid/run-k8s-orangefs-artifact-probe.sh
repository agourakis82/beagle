#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:?defina PASS no ambiente (nunca no script); prefira chave SSH}"
T560=root@10.100.100.2
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf
NAMESPACE="beagle"
TARGET_NODE="${1:-}"

if [[ -z "$TARGET_NODE" ]]; then
  echo "usage: $0 <r740-proxmox|r770-proxmox>"
  exit 2
fi

JOB_NAME="orangefs-artifact-probe-${TARGET_NODE%%-*}"
TMP_MANIFEST="$(mktemp)"
cleanup() {
  rm -f "$TMP_MANIFEST"
}
trap cleanup EXIT

python3 - <<'PY' "$BASE/k8s/job-orangefs-artifact-probe.yaml" "$TMP_MANIFEST" "$JOB_NAME" "$TARGET_NODE"
from pathlib import Path
import sys, yaml

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
job_name = sys.argv[3]
target_node = sys.argv[4]

doc = yaml.safe_load(src.read_text())
doc["metadata"]["name"] = job_name
doc["spec"]["template"]["spec"]["nodeSelector"]["kubernetes.io/hostname"] = target_node
dst.write_text(yaml.safe_dump(doc, sort_keys=False))
PY

remote_k() {
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl $*"
}

echo "[1/4] label OrangeFS client nodes"
remote_k "label node r740-proxmox sounio.dev/orangefs-client=true --overwrite"
remote_k "label node r770-proxmox sounio.dev/orangefs-client=true --overwrite"

echo "[2/4] clear previous probe job if present"
remote_k "-n $NAMESPACE delete job $JOB_NAME --ignore-not-found=true"
sleep 2

echo "[3/4] apply OrangeFS artifact probe on $TARGET_NODE"
cat "$TMP_MANIFEST" | sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560" \
  "cat > /root/${JOB_NAME}.yaml && KUBECONFIG=$KUBECONFIG_REMOTE kubectl apply -f /root/${JOB_NAME}.yaml"

echo "[4/4] current status"
remote_k "-n $NAMESPACE get job $JOB_NAME -o wide"
remote_k "-n $NAMESPACE get pods -o wide | egrep '$JOB_NAME|NAME' || true"
