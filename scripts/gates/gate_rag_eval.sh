#!/usr/bin/env bash
# RAG retrieval regression gate (Beagle / P1).
#
# Runs the golden query set against live Qdrant and FAILS (exit 1) if nDCG@k / Recall@k / MRR drop
# more than the tolerance below the committed baseline (scripts/darwin-eval-baseline.json).
# Mirrors the cockpit's /eval/run baseline+alert, in the Rust stack.
#
# Usage:
#   QDRANT_URL=http://qdrant:6333 EMBEDDING_URL=http://embed:8001/v1 scripts/gates/gate_rag_eval.sh
#   scripts/gates/gate_rag_eval.sh --update-baseline    # seed/refresh the baseline
#
# It SKIPS (exit 0) when Qdrant is unreachable, so it is safe to call from CI that lacks the
# retrieval infra — wire it as a scheduled job against the cluster (or a docker-compose-dev stack)
# for it to actually gate.
set -euo pipefail
cd "$(dirname "$0")/../.."

QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
# IMPORTANT: the embedder MUST be the SAME model that indexed the eval collection
# (beagle_exocortex = BAAI/bge-m3, 1024-dim) or query vectors land in the wrong
# semantic space and the baseline is meaningless. Default points at the LiteLLM
# router (bge-m3, OpenAI-compat) — NOT embedding-service:8001 (that's bge-large-en).
# In-cluster: kubectl -n llm-router port-forward svc/router 4000:4000.
EMBEDDING_URL="${EMBEDDING_URL:-http://localhost:4000/v1}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-bge-m3}"
EVAL_FILE="${DARWIN_EVAL_FILE:-scripts/darwin-eval.yaml}"

echo "[gate_rag_eval] qdrant=$QDRANT_URL embed=$EMBEDDING_URL model=$EMBEDDING_MODEL eval=$EVAL_FILE"

# Reachability probe — skip gracefully if the retrieval stack isn't up (e.g. CI without infra).
if ! curl -fsS --max-time 5 "$QDRANT_URL/readyz" >/dev/null 2>&1 \
   && ! curl -fsS --max-time 5 "$QDRANT_URL/healthz" >/dev/null 2>&1 \
   && ! curl -fsS --max-time 5 "$QDRANT_URL/" >/dev/null 2>&1; then
  echo "[gate_rag_eval] Qdrant not reachable at $QDRANT_URL — SKIPPING (not a failure)."
  exit 0
fi

exec cargo run --quiet -p beagle-rag-update --bin darwin-eval -- \
  --qdrant-url "$QDRANT_URL" \
  --embedding-url "$EMBEDDING_URL" \
  --embedding-model "$EMBEDDING_MODEL" \
  --eval-file "$EVAL_FILE" \
  "$@"
