#!/bin/bash
# DICE Task 6 — Slurm DPO job for DGX Spark (GB10, sm_120, 128GB unified memory).
# Arriving ~2026-06-25. Uses Feature=gb10 constraint when Spark nodes are registered.
#
# Usage:
#   ROUND=1 PREV_ADAPTER=/orangefs/beagle-data/dice/qwen25-7b-dpo-round0 \
#     sbatch scripts/dice/slurm_dpo_spark.sh
#
#SBATCH --job-name=dice-dpo-spark
#SBATCH --partition=all
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=0
#SBATCH --gres=gpu:1
#SBATCH --constraint=gb10
#SBATCH --time=06:00:00
#SBATCH --output=/orangefs/beagle-dice/logs/dpo_spark_r%x_%j.log
#SBATCH --error=/orangefs/beagle-dice/logs/dpo_spark_r%x_%j.err

set -euo pipefail

ROUND="${ROUND:-1}"
PREV_ADAPTER="${PREV_ADAPTER:-Qwen/Qwen2.5-7B-Instruct}"
export BEAGLE_DATA_DIR="${BEAGLE_DATA_DIR:-/orangefs/beagle-data}"
export HF_HOME="/orangefs/hf-cache"
export TOKENIZERS_PARALLELISM=false

# NCCL: pin to the direct 200G Spark-Spark CX-7 link (when both Sparks are online)
# If running on a single Spark, this is a no-op.
export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-eth1}"
export NCCL_DEBUG=WARN

PAIRS="${BEAGLE_DATA_DIR}/dice/preference_pairs_round${ROUND}.jsonl"
if [[ ! -f "$PAIRS" ]]; then
    echo "[dice] ERROR: preference pairs not found at $PAIRS"
    echo "[dice] Run first: python3 scripts/dice/dice_iterate.py --round ${ROUND}"
    exit 1
fi

PAIR_COUNT=$(wc -l < "$PAIRS")
echo "[dice] round ${ROUND} — ${PAIR_COUNT} pairs, Spark gb10 (128GB unified), prev=${PREV_ADAPTER}"

mkdir -p "${BEAGLE_DATA_DIR}/dice"
mkdir -p /orangefs/beagle-dice/logs

# Render the YAML template
CONFIG="${BEAGLE_DATA_DIR}/dice/axolotl_round${ROUND}.yaml"
sed -e "s|{{ROUND}}|${ROUND}|g" \
    -e "s|{{PREV_ADAPTER}}|${PREV_ADAPTER}|g" \
    scripts/dice/axolotl_qwen25_dpo_round_N.yaml.template \
    > "${CONFIG}"

echo "[dice] Config written to ${CONFIG}"

# Axolotl 0.16.1 on Spark via singularity
IMAGE="192.168.3.207:5003/axolotl:0.16.1-cu124"

srun singularity exec \
    --nv \
    --bind "${BEAGLE_DATA_DIR}:${BEAGLE_DATA_DIR}" \
    --bind /orangefs:/orangefs \
    "docker://${IMAGE}" \
    axolotl train "${CONFIG}"

ADAPTER_DIR="${BEAGLE_DATA_DIR}/dice/qwen25-7b-dpo-round${ROUND}"
echo "[dice] round ${ROUND} complete — adapter at ${ADAPTER_DIR}"
echo "[dice] next: ROUND=$((ROUND+1)) PREV_ADAPTER=${ADAPTER_DIR} sbatch scripts/dice/slurm_dpo_spark.sh"
