#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -gt 0 ]]; then
  exec "$root/run-gpu-sku-job.sh" nvidia-rtx-a5000 "$1"
else
  exec "$root/run-gpu-sku-job.sh" nvidia-rtx-a5000
fi
