#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:-Urso1982!}"
RUN_ID="${RUN_ID:-$(date +%s)}"
DATASET_MB="${DATASET_MB:-1024}"
CHECKPOINT_MB="${CHECKPOINT_MB:-512}"
REMOUNT_BEFORE_CHECKPOINT="${REMOUNT_BEFORE_CHECKPOINT:-yes}"
T560_HOST=root@10.100.100.2
R740_HOST=root@10.100.100.4
R770_HOST=root@10.100.100.1
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf
TEMPLATE="$BASE/k8s/pod-orangefs-multinode-template.yaml"

render_apply() {
  local name="$1"
  local node="$2"
  local mode="$3"
  local size_mb="$4"
  perl -0pe \
    "s/__NAME__/$name/g; s/__NODE__/$node/g; s/__RUN_ID__/$RUN_ID/g; s/__MODE__/$mode/g; s/__SIZE_MB__/$size_mb/g" \
    "$TEMPLATE" \
  | sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" "KUBECONFIG=$KUBECONFIG_REMOTE kubectl apply -f - >/dev/null"
}

delete_pod() {
  local name="$1"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle delete pod $name --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true"
}

wait_pod() {
  local name="$1"
  local phase
  for _ in $(seq 1 240); do
    phase="$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle get pod $name -o jsonpath='{.status.phase}'" 2>/dev/null || true)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
      echo "$phase"
      return 0
    fi
    sleep 2
  done
  echo "Timeout"
  return 1
}

logs_pod() {
  local name="$1"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle logs $name --tail=200"
}

restart_client_mounts() {
  for host in "$R740_HOST" "$R770_HOST"; do
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$host" \
      "systemctl restart orangefs-client-runtime.service >/dev/null && systemctl is-active orangefs-client-runtime.service"
  done
}

restart_client_mounts

writer="orangefs-dataset-writer-r740"
reader1="orangefs-dataset-reader-r740"
reader2="orangefs-dataset-reader-r770"
ckpt1="orangefs-checkpoint-writer-r740"
ckpt2="orangefs-checkpoint-writer-r770"

for pod in "$writer" "$reader1" "$reader2" "$ckpt1" "$ckpt2"; do
  delete_pod "$pod"
done
sleep 3

echo "[1/4] dataset writer on r740"
render_apply "$writer" r740-proxmox dataset-write "$DATASET_MB"
phase="$(wait_pod "$writer")"
echo "writer-phase=$phase"
logs_pod "$writer"
[[ "$phase" == "Succeeded" ]]

echo "[2/4] concurrent shared readers on r740 + r770"
render_apply "$reader1" r740-proxmox dataset-read "$DATASET_MB"
render_apply "$reader2" r770-proxmox dataset-read "$DATASET_MB"
phase1="$(wait_pod "$reader1")"
phase2="$(wait_pod "$reader2")"
echo "reader-r740-phase=$phase1"
echo "reader-r770-phase=$phase2"
echo "---logs:$reader1---"
logs_pod "$reader1"
echo "---logs:$reader2---"
logs_pod "$reader2"
[[ "$phase1" == "Succeeded" && "$phase2" == "Succeeded" ]]

if [[ "$REMOUNT_BEFORE_CHECKPOINT" == "yes" ]]; then
  echo "[2.5/4] remount OrangeFS clients before checkpoint phase"
  restart_client_mounts
fi

echo "[3/4] concurrent checkpoint writes on r740 + r770"
render_apply "$ckpt1" r740-proxmox checkpoint-write "$CHECKPOINT_MB"
render_apply "$ckpt2" r770-proxmox checkpoint-write "$CHECKPOINT_MB"
phase3="$(wait_pod "$ckpt1")"
phase4="$(wait_pod "$ckpt2")"
echo "checkpoint-r740-phase=$phase3"
echo "checkpoint-r770-phase=$phase4"
echo "---logs:$ckpt1---"
logs_pod "$ckpt1"
echo "---logs:$ckpt2---"
logs_pod "$ckpt2"
[[ "$phase3" == "Succeeded" && "$phase4" == "Succeeded" ]]

echo "[4/4] host evidence"
for host in "$R740_HOST" "$R770_HOST"; do
  echo "---host:$host---"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$host" \
    "ls -la /var/lib/orangefs-lab/client-runtime/mnt/multinode-bench-$RUN_ID && \
     ls -la /var/lib/orangefs-lab/client-runtime/mnt/multinode-bench-$RUN_ID/datasets && \
     ls -la /var/lib/orangefs-lab/client-runtime/mnt/multinode-bench-$RUN_ID/checkpoints"
done
