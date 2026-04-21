#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-beagle}"
secret_name="${AI_DYNAMO_PULL_SECRET_NAME:-ai-dynamo-pull-secret}"
registry="${AI_DYNAMO_REGISTRY:-nvcr.io}"
username="${AI_DYNAMO_REGISTRY_USERNAME:-\$oauthtoken}"
password="${NGC_API_KEY:-${AI_DYNAMO_REGISTRY_PASSWORD:-}}"
email="${AI_DYNAMO_REGISTRY_EMAIL:-devnull@sounio-lab.local}"

if [[ -z "${password}" ]]; then
  cat >&2 <<'EOF'
Missing NGC credential.

Export one of:
  NGC_API_KEY=...
  AI_DYNAMO_REGISTRY_PASSWORD=...

Optional overrides:
  AI_DYNAMO_PULL_SECRET_NAME
  AI_DYNAMO_REGISTRY
  AI_DYNAMO_REGISTRY_USERNAME
  AI_DYNAMO_REGISTRY_EMAIL

Usage:
  ./beagle/scripts/infrastructure/setup_ai_dynamo_pull_secret.sh [namespace]
EOF
  exit 1
fi

kubectl -n "${namespace}" delete secret "${secret_name}" --ignore-not-found >/dev/null

kubectl -n "${namespace}" create secret docker-registry "${secret_name}" \
  --docker-server="${registry}" \
  --docker-username="${username}" \
  --docker-password="${password}" \
  --docker-email="${email}"

echo "created secret ${secret_name} in namespace ${namespace}"
