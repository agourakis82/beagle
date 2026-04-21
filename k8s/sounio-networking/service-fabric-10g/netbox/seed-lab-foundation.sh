#!/usr/bin/env bash
set -euo pipefail

NETBOX_URL="${NETBOX_URL:-http://127.0.0.1:8081}"
NETBOX_TOKEN="${NETBOX_TOKEN:?set NETBOX_TOKEN}"

api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Token ${NETBOX_TOKEN}" \
      -H "Content-Type: application/json" \
      "${NETBOX_URL}${path}" \
      --data "$body"
  else
    curl -fsS -X "$method" \
      -H "Authorization: Token ${NETBOX_TOKEN}" \
      "${NETBOX_URL}${path}"
  fi
}

ensure_prefix() {
  local prefix="$1"
  local description="$2"
  if ! api GET "/api/ipam/prefixes/?prefix=${prefix}" | jq -e '.count > 0' >/dev/null; then
    api POST "/api/ipam/prefixes/" "{\"prefix\":\"${prefix}\",\"status\":\"active\",\"description\":\"${description}\"}" >/dev/null
    echo "created prefix ${prefix}"
  fi
}

ensure_vlan() {
  local vid="$1"
  local name="$2"
  if ! api GET "/api/ipam/vlans/?vid=${vid}" | jq -e '.count > 0' >/dev/null; then
    api POST "/api/ipam/vlans/" "{\"vid\":${vid},\"name\":\"${name}\",\"status\":\"active\"}" >/dev/null
    echo "created vlan ${vid}"
  fi
}

ensure_prefix "192.168.3.0/24" "Management fabric"
ensure_prefix "10.30.0.0/24" "10Gb service and egress fabric"
ensure_prefix "10.100.100.0/24" "Kubernetes underlay"
ensure_prefix "10.200.0.0/24" "Storage and migration fabric"
ensure_prefix "10.210.0.0/24" "GPU RDMA fabric"

ensure_vlan "3" "MGMT"
ensure_vlan "100" "K8S-UNDERLAY"
ensure_vlan "130" "SERVICE-FABRIC-10G"
ensure_vlan "200" "STORAGE-MIGRATION"
ensure_vlan "210" "GPU-FABRIC"

echo "NetBox foundation seed complete"
