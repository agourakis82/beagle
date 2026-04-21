#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -gt 0 ]]; then
  exec "$root/run-gpu-sku-job.sh" nvidia-rtx-4000-ada "$1"
else
  exec "$root/run-gpu-sku-job.sh" nvidia-rtx-4000-ada
fi
