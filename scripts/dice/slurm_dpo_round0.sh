#!/bin/bash
#SBATCH --job-name=dice-dpo-round0
#SBATCH --partition=all
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --gres=gpu:1
#SBATCH --constraint=a5000
#SBATCH --time=12:00:00
#SBATCH --output=/orangefs/beagle-dice/logs/dpo_round0_%j.log
#SBATCH --error=/orangefs/beagle-dice/logs/dpo_round0_%j.err

set -euo pipefail

# ── Environment ──────────────────────────────────────────────────────────────
export BEAGLE_DATA_DIR="${BEAGLE_DATA_DIR:-/orangefs/beagle-data}"
export HF_HOME="/orangefs/hf-cache"
export TOKENIZERS_PARALLELISM=false
export NCCL_DEBUG=WARN

# ── Guard: preference pairs must exist ───────────────────────────────────────
PAIRS="${BEAGLE_DATA_DIR}/dice/preference_pairs_round0.jsonl"
if [[ ! -f "$PAIRS" ]]; then
    echo "[dice] ERROR: preference pairs not found at $PAIRS"
    echo "[dice] Run: python3 scripts/dice/export_preference_pairs.py"
    exit 1
fi

PAIR_COUNT=$(wc -l < "$PAIRS")
echo "[dice] round 0 — ${PAIR_COUNT} preference pairs, A5000 (24GB)"

# ── Axolotl image ────────────────────────────────────────────────────────────
# Pin 0.16.1 as per cluster doctrine (project_axolotl_image_pinning.md)
IMAGE="192.168.3.207:5003/axolotl:0.16.1-cu121"

mkdir -p "${BEAGLE_DATA_DIR}/dice/qwen25-7b-dpo-round0"
mkdir -p /orangefs/beagle-dice/logs

srun singularity exec \
    --nv \
    --bind "${BEAGLE_DATA_DIR}:${BEAGLE_DATA_DIR}" \
    --bind /orangefs:/orangefs \
    "docker://${IMAGE}" \
    axolotl train /workspace/scripts/dice/axolotl_qwen25_dpo_round0.yaml

echo "[dice] round 0 training complete — adapter at ${BEAGLE_DATA_DIR}/dice/qwen25-7b-dpo-round0"
