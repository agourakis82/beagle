#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="${RUN_ID:-$(date +%s)}"
DATASET_MB="${DATASET_MB:-512}"
CHECKPOINT_MB="${CHECKPOINT_MB:-512}"
LOG_DIR="${LOG_DIR:-$BASE/logs}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/orangefs-proven-workflow-$RUN_ID.log"

echo "run_id=$RUN_ID dataset_mb=$DATASET_MB checkpoint_mb=$CHECKPOINT_MB log=$LOG_FILE"

{
  echo "=== orangefs-proven-workflow-canary start $(date --iso-8601=seconds) ==="
  echo "run_id=$RUN_ID"
  echo "dataset_mb=$DATASET_MB"
  echo "checkpoint_mb=$CHECKPOINT_MB"
  RUN_ID="$RUN_ID" DATASET_MB="$DATASET_MB" CHECKPOINT_MB="$CHECKPOINT_MB" \
    "$BASE/run-k8s-orangefs-proven-workflow.sh"
  echo "=== orangefs-proven-workflow-canary end $(date --iso-8601=seconds) ==="
} | tee "$LOG_FILE"

