#!/usr/bin/env bash
set -euo pipefail

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

echo "== tailscale operator verification =="
echo "context: $(k config current-context)"
echo

echo "== operator pods/services =="
k -n tailscale get pods,svc
echo

echo "== proxy groups =="
k -n tailscale get proxygroup 2>/dev/null || echo "proxygroup CRD/resources not available yet"
echo

echo "== workspace tailnet services =="
k -n beagle get svc sounio-workspace-tailnet-ssh sounio-workspace-tailnet-http -o wide
echo

echo "== load balancer ingress =="
k -n beagle get svc sounio-workspace-tailnet-ssh \
  -o jsonpath='{.status.loadBalancer.ingress[*].hostname}{"\n"}' || true
k -n beagle get svc sounio-workspace-tailnet-http \
  -o jsonpath='{.status.loadBalancer.ingress[*].hostname}{"\n"}' || true
echo

echo "verification complete"
