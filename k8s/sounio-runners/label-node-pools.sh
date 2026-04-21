#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  label-node-pools.sh compute <node-name>
  label-node-pools.sh cpu <node-name>
  label-node-pools.sh gpu <node-name>
  label-node-pools.sh clear <node-name>
  label-node-pools.sh accelerator <node-name> <gpu-sku>
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

kind="$1"
node="$2"

case "$kind" in
  compute)
    k label node "$node" "sounio.dev/compute=heavy" --overwrite
    k taint node "$node" "sounio.dev/compute=heavy:NoSchedule" --overwrite
    k get node "$node" -L sounio.dev/compute
    exit 0
    ;;
  cpu)
    pool="cpu-batch"
    remove_pool="gpu-batch"
    ;;
  gpu)
    pool="gpu-batch"
    remove_pool="cpu-batch"
    ;;
  clear)
    k taint node "$node" "sounio.dev/compute=heavy:NoSchedule-" >/dev/null 2>&1 || true
    k taint node "$node" "sounio.dev/pool=cpu-batch:NoSchedule-" >/dev/null 2>&1 || true
    k taint node "$node" "sounio.dev/pool=gpu-batch:NoSchedule-" >/dev/null 2>&1 || true
    k label node "$node" sounio.dev/compute- >/dev/null 2>&1 || true
    k label node "$node" sounio.dev/pool- >/dev/null 2>&1 || true
    k get node "$node" -L sounio.dev/compute -L sounio.dev/pool
    exit 0
    ;;
  accelerator)
    if [[ $# -ne 3 ]]; then
      usage >&2
      exit 1
    fi
    accelerator="$3"
    k label node "$node" "sounio.dev/accelerator=${accelerator}" --overwrite
    k get node "$node" -L sounio.dev/accelerator
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

k taint node "$node" "sounio.dev/pool=${remove_pool}:NoSchedule-" >/dev/null 2>&1 || true
k label node "$node" "sounio.dev/pool=${pool}" --overwrite
k taint node "$node" "sounio.dev/pool=${pool}:NoSchedule" --overwrite
k get node "$node" -L sounio.dev/pool
