#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:-Urso1982!}"
PROFILE="${PROFILE:-balanced}"
T560_HOST=root@10.100.100.2
R740_HOST=root@10.100.100.4
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf

case "$PROFILE" in
  balanced)
    POD_NAME="orangefs-vs-ceph-r740-bench"
    MANIFEST="$BASE/k8s/pod-orangefs-vs-ceph-r740-bench.yaml"
    ;;
  streaming)
    POD_NAME="orangefs-vs-ceph-r740-bench-streaming"
    MANIFEST="$BASE/k8s/pod-orangefs-vs-ceph-r740-bench-streaming.yaml"
    ;;
  *)
    echo "unsupported PROFILE=$PROFILE (use balanced or streaming)" >&2
    exit 2
    ;;
esac

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$R740_HOST" \
  'systemctl restart orangefs-client-runtime.service && systemctl status --no-pager orangefs-client-runtime.service | sed -n "1,15p"' >/dev/null

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" "\
KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle delete pod $POD_NAME --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true; \
sleep 3; \
KUBECONFIG=$KUBECONFIG_REMOTE kubectl apply -f '$MANIFEST' >/dev/null"

python3 - <<PY
import subprocess, time, sys
phase_cmd = "sshpass -p '$PASS' ssh -o StrictHostKeyChecking=no $T560_HOST \\"KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle get pod $POD_NAME -o jsonpath='{.status.phase}'\\""
logs_cmd = "sshpass -p '$PASS' ssh -o StrictHostKeyChecking=no $T560_HOST \\"KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle logs $POD_NAME --tail=200\\""
for _ in range(240):
    phase = subprocess.check_output(phase_cmd, shell=True, text=True).strip()
    if phase in {'Succeeded','Failed'}:
        print('phase='+phase)
        print('---logs---')
        print(subprocess.check_output(logs_cmd, shell=True, text=True))
        sys.exit(0 if phase == 'Succeeded' else 1)
    time.sleep(2)
print('phase='+phase)
print('---partial-logs---')
try:
    print(subprocess.check_output(logs_cmd, shell=True, text=True))
except Exception as e:
    print(e)
sys.exit(1)
PY

