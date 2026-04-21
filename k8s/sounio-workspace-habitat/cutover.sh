#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: cutover.sh <phase>

phases:
  apply    apply habitat storageclass/services/statefulset
  quiesce  scale both old deployment and habitat statefulset to zero
  seed     apply the seed job and wait for completion
  resume   scale habitat statefulset to one and wait for readiness
  switch-service patch the stable sounio-workspace service to target the habitat
  rollback-service patch the stable sounio-workspace service back to the old deployment
  rollback scale habitat to zero and old deployment to one
EOF
}

if [[ $# -ne 1 ]]; then
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

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
phase="$1"
legacy_deployment="sounio-workspace"

case "$phase" in
  apply)
    k apply -k "$root"
    ;;
  quiesce)
    k -n beagle scale statefulset sounio-workspace-habitat --replicas=0 || true
    k -n beagle scale deployment "$legacy_deployment" --replicas=0 2>/dev/null || true
    k -n beagle get deploy,statefulset
    ;;
  seed)
    k -n beagle delete job sounio-workspace-habitat-seed --ignore-not-found
    k apply -f "$root/seed-workspace-data-job.yaml"
    k -n beagle wait --for=condition=complete --timeout=30m job/sounio-workspace-habitat-seed
    ;;
  resume)
    k -n beagle scale statefulset sounio-workspace-habitat --replicas=1
    k -n beagle rollout status statefulset/sounio-workspace-habitat --timeout=30m
    ;;
  switch-service)
    k -n beagle patch service sounio-workspace --type=merge \
      -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-habitat"}}}'
    k -n beagle get svc sounio-workspace -o wide
    ;;
  rollback-service)
    if k -n beagle get deploy "$legacy_deployment" >/dev/null 2>&1; then
      k -n beagle patch service sounio-workspace --type=merge \
        -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace"}}}'
      k -n beagle get svc sounio-workspace -o wide
    else
      echo "legacy deployment $legacy_deployment is not present; rollback-service has no safe target" >&2
      exit 1
    fi
    ;;
  rollback)
    k -n beagle scale statefulset sounio-workspace-habitat --replicas=0 || true
    if k -n beagle get deploy "$legacy_deployment" >/dev/null 2>&1; then
      k -n beagle scale deployment "$legacy_deployment" --replicas=1
      k -n beagle rollout status deployment/"$legacy_deployment" --timeout=30m
    else
      echo "legacy deployment $legacy_deployment is not present; rollback must be handled manually" >&2
      exit 1
    fi
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
