#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <gpu-sku> [job-name]" >&2
  exit 1
fi

sku="$1"
job_name="${2:-sounio-gpu-${sku}-$(date +%Y%m%d%H%M%S)}"
namespace="${NAMESPACE:-beagle}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$root/gpu-batch-job.yaml"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

python3 - "$template" "$job_name" "$sku" <<'PY' | k -n "$namespace" apply -f - >/dev/null
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
job_name = sys.argv[2]
sku = sys.argv[3]

resources_by_sku = {
    "nvidia-l4": {"cpu": "16", "memory": "32Gi"},
    "nvidia-rtx-a5000": {"cpu": "16", "memory": "48Gi"},
    "nvidia-rtx-4000-ada": {"cpu": "8", "memory": "24Gi"},
}
resources = resources_by_sku.get(sku, {"cpu": "8", "memory": "16Gi"})

text = template_path.read_text()
text = text.replace(
    "name: sounio-gpu-batch-template",
    f"name: {job_name}",
    1,
)
text = text.replace(
    "suspend: true",
    "suspend: false",
    1,
)
text = text.replace(
    "      restartPolicy: Never\n",
    "      restartPolicy: Never\n"
    "      nodeSelector:\n"
    "        sounio.dev/accelerator: " + sku + "\n",
    1,
)
text = text.replace(
    "            limits:\n"
    "              cpu: \"32\"\n"
    "              memory: 64Gi\n"
    "              nvidia.com/gpu: \"1\"\n",
    "            limits:\n"
    f"              cpu: \"{resources['cpu']}\"\n"
    f"              memory: {resources['memory']}\n"
    "              nvidia.com/gpu: \"1\"\n",
    1,
)
text = text.replace(
    "                  - key: sounio.dev/accelerator\n"
    "                    operator: Exists",
    "                  - key: sounio.dev/accelerator\n"
    "                    operator: In\n"
    f"                    values:\n"
    f"                      - {sku}",
    1,
)
print(text, end="")
PY

echo "$job_name"
