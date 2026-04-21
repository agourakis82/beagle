#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  CLOUDFLARE_API_TOKEN=... \
  CLOUDFLARE_ACCOUNT_ID=... \
  CLOUDFLARE_TUNNEL_ID=... \
  [TUNNEL_HOSTNAME=beagle.chiuratto.ai] \
  [ORIGIN=http://project-cockpit.beagle.svc.cluster.local:80] \
  [NAMESPACE=beagle] \
  [SECRET_NAME=cloudflared-beagle-mobile] \
  ./setup_beagle_mobile_tunnel.sh

This fetches the remotely managed tunnel token, writes it to a Kubernetes
Secret, and pushes the Cloudflare ingress config for the Beagle mobile gateway.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${CLOUDFLARE_API_TOKEN:?missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?missing CLOUDFLARE_ACCOUNT_ID}"
: "${CLOUDFLARE_TUNNEL_ID:?missing CLOUDFLARE_TUNNEL_ID}"

TUNNEL_HOSTNAME="${TUNNEL_HOSTNAME:-beagle.chiuratto.ai}"
ORIGIN="${ORIGIN:-http://project-cockpit.beagle.svc.cluster.local:80}"
NAMESPACE="${NAMESPACE:-beagle}"
SECRET_NAME="${SECRET_NAME:-cloudflared-beagle-mobile}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
MANIFEST="${REPO_ROOT}/k8s/project-cockpit/cloudflared-beagle-mobile.yaml"

fetch_tunnel_token() {
  curl -fsS \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${CLOUDFLARE_TUNNEL_ID}/token" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])'
}

push_tunnel_config() {
  curl -fsS \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${CLOUDFLARE_TUNNEL_ID}/configurations" \
    -X PUT \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$(cat <<JSON
{"config":{"ingress":[{"hostname":"${TUNNEL_HOSTNAME}","service":"${ORIGIN}","originRequest":{"connectTimeout":30}},{"service":"http_status:404"}]}}
JSON
)"
}

store_tunnel_secret() {
  local tunnel_token
  tunnel_token="$(fetch_tunnel_token)"
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal=tunnel-token="${tunnel_token}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

main() {
  push_tunnel_config
  store_tunnel_secret
  kubectl apply -f "${MANIFEST}"
  kubectl -n "${NAMESPACE}" rollout status deployment/cloudflared-beagle-mobile --timeout=120s
}

main "$@"
