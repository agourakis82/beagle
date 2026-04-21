#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID="${RUN_ID:-$(date +%s)}"
DATASET_MB="${DATASET_MB:-256}"
CHECKPOINT_MB="${CHECKPOINT_MB:-256}"

echo "[1/3] dataset writer + fanout readers"
RUN_ID="$RUN_ID" SIZE_MB="$DATASET_MB" MODE=fanout \
  "$BASE/run-k8s-orangefs-dataset-repro.sh"

echo "[2/3] concurrent checkpoint repro"
RUN_ID="$RUN_ID" SIZE_MB="$CHECKPOINT_MB" SLEEP_BEFORE_READ=0 MODE=concurrent \
  "$BASE/run-k8s-orangefs-checkpoint-repro.sh"

echo "[3/3] host evidence"
sshpass -p "${PASS:-Urso1982!}" ssh -o StrictHostKeyChecking=no root@10.100.100.4 \
  "find /var/lib/orangefs-lab/client-runtime/mnt -maxdepth 3 \\( -path '*/dataset-repro-$RUN_ID/*' -o -path '*/checkpoint-repro-$RUN_ID/*' \\) -type f -printf '%P %s\\n' 2>/dev/null | sort"
