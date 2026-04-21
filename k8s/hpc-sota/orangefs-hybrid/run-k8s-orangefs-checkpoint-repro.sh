#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:-Urso1982!}"
RUN_ID="${RUN_ID:-$(date +%s)}"
SIZE_MB="${SIZE_MB:-256}"
SLEEP_BEFORE_READ="${SLEEP_BEFORE_READ:-0}"
MODE="${MODE:-single-r740}"
T560_HOST=root@10.100.100.2
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf
TEMPLATE="$BASE/k8s/pod-orangefs-checkpoint-repro-template.yaml"

render_apply() {
  local name="$1"
  local node="$2"
  perl -0pe \
    "s/__NAME__/$name/g; s/__NODE__/$node/g; s/__RUN_ID__/$RUN_ID/g; s/__SIZE_MB__/$SIZE_MB/g; s/__SLEEP_BEFORE_READ__/$SLEEP_BEFORE_READ/g" \
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
  for _ in $(seq 1 180); do
    phase="$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle get pod $name -o jsonpath='{.status.phase}'" 2>/dev/null || true)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
      echo "$phase"
      return 0
    fi
    sleep 2
  done
  echo "Timeout"
}

logs_pod() {
  local name="$1"
  echo "---logs:$name---"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle logs $name --tail=200 2>/dev/null || true"
}

pods=()
case "$MODE" in
  single-r740)
    pods=("orangefs-repro-r740")
    ;;
  single-r770)
    pods=("orangefs-repro-r770")
    ;;
  concurrent)
    pods=("orangefs-repro-r740" "orangefs-repro-r770")
    ;;
  *)
    echo "unsupported MODE=$MODE" >&2
    exit 2
    ;;
esac

for pod in "${pods[@]}"; do
  delete_pod "$pod"
done
sleep 3

if [[ "$MODE" == "single-r740" || "$MODE" == "concurrent" ]]; then
  render_apply "orangefs-repro-r740" "r740-proxmox"
fi
if [[ "$MODE" == "single-r770" || "$MODE" == "concurrent" ]]; then
  render_apply "orangefs-repro-r770" "r770-proxmox"
fi

for pod in "${pods[@]}"; do
  phase="$(wait_pod "$pod")"
  echo "$pod phase=$phase"
  logs_pod "$pod"
done
