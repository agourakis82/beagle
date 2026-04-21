#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$root/run-template-job.sh" cpu-standard "sounio-cpu-fast-$(date +%Y%m%d%H%M%S)"
