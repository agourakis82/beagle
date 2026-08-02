#!/usr/bin/env bash
# Seed a pinned biography digest into beagle-core for Personal space grounding.
# Run from a machine with kubectl access to the beagle namespace.
set -euo pipefail

NAMESPACE="${BEAGLE_NAMESPACE:-beagle}"
POD=$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/name=project-cockpit -o jsonpath='{.items[0].metadata.name}')

DIGEST="${1:-Demetrios (Demi) é psiquiatra e builder solo do ecossistema Beagle + linguagem Sounio. Opera o cluster t560/HPC (K8s, Slurm, OrangeFS), integrou 2 DGX Spark (GB10). Trabalho recente: Personal Companion, memory-pg, ensemble hermes+hunyuan, canal Telegram Beagle.}"

kubectl -n "$NAMESPACE" exec "$POD" -- sh -c "TOKEN=\$(printenv BEAGLE_MEMORY_API_TOKEN); curl -fsS -X POST http://beagle-core.beagle.svc.cluster.local:8080/api/exocortex/v1/memory/assisted-import \
  -H 'content-type: application/json' \
  -H 'X-Beagle-Consumer: beagle-operator' \
  -H \"Authorization: Bearer \$TOKEN\" \
  -d '{\"source_platform\":\"exocortex-ingest\",\"source_surface\":\"manual-seed\",\"import_scope\":\"biography_digest\",\"session_id\":\"biography-digest\",\"privacy_class\":\"sensitive\",\"title\":\"Biografia viva — $(date +%F)\",\"confidence_score\":0.95,\"create_chronoself_commit\":false,\"turns\":[{\"role\":\"user\",\"content\":$(printf '%s' "$DIGEST" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"metadata\":{\"kind\":\"biography-digest\"}}],\"tags\":[\"biography-digest\",\"pinned\"],\"metadata\":{\"kind\":\"biography-digest\",\"remembered_from\":\"manual-seed\"}}'"

echo
echo "Biography digest seeded via pod $POD"
