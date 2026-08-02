#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROOF_SCRIPT="$BASE/prove-t560-5860-two-node.sh"
K8S_MANIFEST="$BASE/k8s/pod-orangefs-r770-canary.yaml"
CLIENT_MOUNT_SCRIPT="$BASE/run-orangefs-client-mount.sh"

T560_HOST=root@10.100.100.2
R770_HOST=root@10.100.100.1
PASS="${PASS:?defina PASS no ambiente (nunca no script); prefira chave SSH}"
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf
HOLD_SECONDS="${HOLD_SECONDS:-900}"

SSH_T560=(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST")
SCP_T560=(sshpass -p "$PASS" scp -o StrictHostKeyChecking=no)

echo "[1/5] Opening two-node OrangeFS proof window on t560 + 5860"
"${SCP_T560[@]}" "$PROOF_SCRIPT" "$T560_HOST:/root/prove-t560-5860-two-node.sh" >/dev/null
"${SSH_T560[@]}" "bash -s" <<REMOTE
set -euo pipefail
LOG=/root/orangefs-two-node-proof.log
PID=/root/orangefs-two-node-proof.pid
chmod +x /root/prove-t560-5860-two-node.sh
pkill -f '/root/prove-t560-5860-two-node.sh' >/dev/null 2>&1 || true
rm -f "\$LOG" "\$PID"
nohup env HOLD_SECONDS=$HOLD_SECONDS /root/prove-t560-5860-two-node.sh >"\$LOG" 2>&1 &
echo \$! >"\$PID"
sleep 8
echo "proof-pid=\$(cat "\$PID")"
tail -n 20 "\$LOG"
REMOTE

echo "[2/5] Verifying both OrangeFS servers are alive"
"${SSH_T560[@]}" "ps -ef | grep pvfs2-server | grep -v grep"
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no root@10.100.100.3 "ps -ef | grep pvfs2-server | grep -v grep"

echo "[3/5] Mounting OrangeFS persistently on r770"
TARGET_HOST="$R770_HOST" TARGET_PASS="$PASS" SOURCE_HOST="$T560_HOST" SOURCE_PASS="$PASS" "$CLIENT_MOUNT_SCRIPT"

echo "[4/5] Applying K8s canary pod on r770"
"${SSH_T560[@]}" "\
KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle delete pod orangefs-r770-canary --ignore-not-found >/dev/null 2>&1 || true && \
KUBECONFIG=$KUBECONFIG_REMOTE kubectl apply -f '$K8S_MANIFEST' >/dev/null"

for _ in $(seq 1 90); do
    phase="$("${SSH_T560[@]}" "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle get pod orangefs-r770-canary -o jsonpath='{.status.phase}'" || true)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
        break
    fi
    sleep 2
done

echo "[5/5] Collecting pod and filesystem evidence"
"${SSH_T560[@]}" "\
KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle get pod orangefs-r770-canary -o wide && \
echo ---logs--- && \
KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle logs orangefs-r770-canary --tail=200"

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$R770_HOST" "\
ls -la /var/lib/orangefs-lab/client-runtime/mnt/checkpoints && \
echo --- && \
cat /var/lib/orangefs-lab/client-runtime/mnt/checkpoints/k8s-orangefs-r770.txt"
