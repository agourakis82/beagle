#!/usr/bin/env bash
set -euo pipefail

for cmd in kubectl helm rg; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
done

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

echo "== tailscale operator preflight =="
echo "context: $(k config current-context)"
echo

echo "== existing CRDs =="
k get crd | rg -i 'tailscale|proxygroup' || echo "none"
echo

echo "== tailscale namespace =="
k get ns tailscale 2>/dev/null || echo "tailscale namespace not present yet"
echo

echo "== tailscale secrets =="
k get secret -n tailscale 2>/dev/null || echo "no secrets visible in tailscale namespace yet"
echo

echo "== beagle services that will be exposed =="
k -n beagle get svc sounio-workspace 2>/dev/null || {
  echo "expected service beagle/sounio-workspace was not found" >&2
  exit 1
}
echo

echo "preflight complete"
