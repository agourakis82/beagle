#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${root}/run-jobset-rdma-smoke.sh" \
  --network gpu-fabric-10-210 \
  --jobset-name rdma210 \
  --manifest "${root}/jobset-rdma-gpu-smoke.v2.yaml"
