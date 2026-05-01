#!/bin/bash
# Deploy beagle-core with Round Table support
# Run from the repo root: ./scripts/deploy-round-table.sh

set -euo pipefail

TAG="beagle-core-$(date +%s)"
REGISTRY="ttl.sh"
IMAGE="${REGISTRY}/${TAG}:24h"
NAMESPACE="beagle"
DEPLOYMENT="beagle-core"

echo "=== Building beagle-core container ==="
echo "Image: ${IMAGE}"

docker build \
  -f apps/beagle-monorepo/Dockerfile.core_server \
  -t "${IMAGE}" \
  .

echo "=== Pushing to ttl.sh ==="
docker push "${IMAGE}"

echo "=== Updating deployment ==="
kubectl -n "${NAMESPACE}" set image "deployment/${DEPLOYMENT}" \
  core-server="${IMAGE}"

echo "=== Waiting for rollout ==="
kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=300s

echo "=== Testing /health ==="
sleep 5
curl -s http://beagle-core.tail21cbc4.ts.net/health | jq .

echo "=== Testing /api/v1/round-table ==="
curl -s http://beagle-core.tail21cbc4.ts.net/api/v1/round-table \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is consciousness?", "voices": ["quantum", "paradox"]}' \
  --max-time 60 | jq '{voices: [.voices[].name], pci_score, synthesis: .synthesis[0:100]}'

echo "=== Done ==="
