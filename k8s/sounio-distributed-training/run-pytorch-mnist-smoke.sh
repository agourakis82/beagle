#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-beagle}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$root/jobset-pytorch-mnist-smoke.yaml"
job_name="mn$(date +%m%d%H%M%S)"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

python3 - "$template" "$job_name" <<'PY' | k -n "$namespace" apply -f -
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text()
job_name = sys.argv[2]
print(template.replace("name: mn2", f"name: {job_name}", 1), end="")
PY

echo "$job_name"
