#!/bin/bash
# GPU Environment Diagnostic

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

function section() {
  echo ""
  printf "${YELLOW}%s${NC}\n" "$1"
  echo "--------------------------------------"
}

echo "🔍 BEAGLE GPU Environment Diagnostic"
echo "======================================"

section "1️⃣  NVIDIA Driver"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=driver_version --format=csv,noheader
else
  echo "nvidia-smi not available"
fi

section "2️⃣  CUDA Version"
if command -v nvcc >/dev/null 2>&1; then
  nvcc --version
else
  echo "nvcc not in PATH"
fi
if [ -f /usr/local/cuda/version.txt ]; then
  cat /usr/local/cuda/version.txt
else
  echo "CUDA version file not found"
fi

section "3️⃣  GPU Info"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,compute_cap,memory.total --format=csv
else
  echo "nvidia-smi not available"
fi

section "4️⃣  GPU Compute Mode"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=compute_mode --format=csv
else
  echo "nvidia-smi not available"
fi

section "5️⃣  MPS Status"
if pgrep -x nvidia-cuda-mps >/dev/null 2>&1; then
  echo "⚠️  NVIDIA MPS is RUNNING (may cause vLLM deadlock)"
  ps aux | grep -i mps | grep -v grep
else
  echo "✅ NVIDIA MPS is NOT RUNNING"
fi

section "6️⃣  GPU Processes"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi pmon -c 1 || true
else
  echo "nvidia-smi not available"
fi

section "7️⃣  Docker GPU Runtime"
if command -v docker >/dev/null 2>&1; then
  docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi || echo "GPU runtime not working"
else
  echo "Docker not available"
fi

section "8️⃣  System Info"
uname -a

section "9️⃣  CUDA libs"
ls -l /usr/lib/x86_64-linux-gnu | grep -i cuda | head -n 20 || true

section "🔚 Diagnostic complete"
