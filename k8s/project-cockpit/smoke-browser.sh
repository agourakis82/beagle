#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-project-cockpit-tailnet-http}"
PROJECT_SLUG="${1:-sounio}"
SESSION_NAME="${SESSION_NAME:-cockpit-smoke}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[fail] missing command: $1" >&2
    exit 1
  }
}

require kubectl
require jq
require agent-browser

service_json="$(kubectl -n "${NAMESPACE}" get svc "${SERVICE_NAME}" -o json)"
hostname="$(printf '%s' "${service_json}" | jq -r '.status.loadBalancer.ingress[0].hostname // empty')"
vip="$(printf '%s' "${service_json}" | jq -r '.status.loadBalancer.ingress[0].ip // empty')"

if [[ -z "${hostname}" && -z "${vip}" ]]; then
  echo "[fail] no public hostname or VIP found for ${SERVICE_NAME}" >&2
  exit 1
fi

route_path="/projects/${PROJECT_SLUG}"
vip_url=""
hostname_url=""
if [[ -n "${vip}" ]]; then
  vip_url="http://${vip}${route_path}"
fi
if [[ -n "${hostname}" ]]; then
  hostname_url="http://${hostname}${route_path}"
fi

# The current browser runtime can block the Tailnet hostname with
# ERR_BLOCKED_BY_CLIENT even when the service itself is healthy.
# So browser automation uses the VIP by default and only falls back to the
# hostname when the VIP is unavailable.
primary_url="${vip_url}"
fallback_url="${hostname_url}"

run_browser_smoke() {
  local url="$1"
  echo "[info] opening ${url}" >&2
  agent-browser close >/dev/null 2>&1 || true
  agent-browser open --session "${SESSION_NAME}" "${url}"
  agent-browser wait --session "${SESSION_NAME}" --load networkidle
  agent-browser snapshot --session "${SESSION_NAME}" -i
}

if [[ -n "${primary_url}" ]]; then
  output_file="$(mktemp)"
  if run_browser_smoke "${primary_url}" >"${output_file}" 2>&1; then
    cat "${output_file}"
    rm -f "${output_file}"
    exit 0
  fi

  cat "${output_file}" >&2
  if grep -q 'ERR_BLOCKED_BY_CLIENT' "${output_file}" && [[ -n "${fallback_url}" ]]; then
    echo "[warn] primary browser path was blocked by the browser runtime; retrying fallback ${fallback_url}" >&2
    rm -f "${output_file}"
    run_browser_smoke "${fallback_url}"
    exit 0
  fi
  rm -f "${output_file}"
  exit 1
fi

run_browser_smoke "${fallback_url}"
