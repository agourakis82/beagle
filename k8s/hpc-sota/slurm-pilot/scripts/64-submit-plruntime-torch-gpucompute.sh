#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

LOGIN_TARGET="deploy/slurm-pilot-login-slinky"

if ! kubectl -n "${NS}" get "${LOGIN_TARGET}" >/dev/null 2>&1; then
  echo "could not find ${LOGIN_TARGET} in namespace ${NS}" >&2
  exit 1
fi

kubectl -n "${NS}" exec "${LOGIN_TARGET}" -- bash -lc '
  set -euo pipefail
  mkdir -p /orangefs/training/slurm-pilot/plruntime-torch
  cat >/tmp/plruntime-torch-gpucompute.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J plruntime-torch
#SBATCH -p gpu-orangefs
#SBATCH -A plruntime
#SBATCH --qos=burst
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
set -euo pipefail
set -x

copy_with_retry() {
  local src="\$1"
  local dst="\$2"
  local attempt
  local tmp_dst="\${dst}.tmp"
  for attempt in \$(seq 1 20); do
    mkdir -p "\$(dirname "\$dst")" || true
    rm -f "\$dst" "\$tmp_dst" || true
    if cp -f "\$src" "\$tmp_dst" && [ -s "\$tmp_dst" ] && mv -f "\$tmp_dst" "\$dst" && [ -s "\$dst" ]; then
      return 0
    fi
    sleep 1
  done
  echo "failed to copy \$src -> \$dst" >&2
  return 1
}

tmpdir=\$(mktemp -d /tmp/plruntime-torch.XXXXXX)
persist_logs() {
  mkdir -p /orangefs/training/slurm-pilot/plruntime-torch || true
  for f in get-pip.log pip-install.log job.log; do
    if [ -f "\${tmpdir}/\$f" ]; then
      copy_with_retry "\${tmpdir}/\$f" "/orangefs/training/slurm-pilot/plruntime-torch/\${SLURM_JOB_ID}-\$f" || true
    fi
  done
}
cleanup() {
  persist_logs || true
  rm -rf "\${tmpdir}"
}
trap cleanup EXIT

export LD_LIBRARY_PATH="/host-nvidia:\${LD_LIBRARY_PATH:-}"
export PYTHONUSERBASE="\${tmpdir}/pyusr"
exec > >(tee "\${tmpdir}/job.log") 2>&1

python3 - <<PY
import pathlib, ssl, urllib.request
path = pathlib.Path("\${tmpdir}") / "get-pip.py"
ctx = ssl._create_unverified_context()
with urllib.request.urlopen("https://bootstrap.pypa.io/get-pip.py", context=ctx) as resp:
    path.write_bytes(resp.read())
print(path)
PY

python3 "\${tmpdir}/get-pip.py" --user --break-system-packages --trusted-host bootstrap.pypa.io >"\${tmpdir}/get-pip.log" 2>&1
export PATH="\${PYTHONUSERBASE}/bin:\${PATH}"

python3 -m pip install --user --no-cache-dir \
  --break-system-packages \
  --trusted-host download.pytorch.org \
  torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
  --index-url https://download.pytorch.org/whl/cu124 >"\${tmpdir}/pip-install.log" 2>&1

export PYTHONPATH="\$(python3 - <<PY
import site
print(site.getusersitepackages())
PY):\${PYTHONPATH:-}"

python3 <<PY
import json, os, socket, time
import torch

start = time.perf_counter()
device = torch.device("cuda")
assert torch.cuda.is_available(), "torch.cuda.is_available() is false"
name = torch.cuda.get_device_name(0)

a = torch.randn((4096, 4096), device=device, dtype=torch.float32)
b = torch.randn((4096, 4096), device=device, dtype=torch.float32)
c = torch.matmul(a, b)
checksum = float(c.sum().item())
torch.cuda.synchronize()
elapsed = time.perf_counter() - start

payload = {
    "job_id": int(os.environ.get("SLURM_JOB_ID", "0")),
    "job_name": os.environ.get("SLURM_JOB_NAME"),
    "account": os.environ.get("SLURM_JOB_ACCOUNT"),
    "partition": os.environ.get("SLURM_JOB_PARTITION"),
    "qos": os.environ.get("SLURM_JOB_QOS"),
    "host": socket.gethostname(),
    "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
    "torch_version": torch.__version__,
    "cuda_version": torch.version.cuda,
    "device_name": name,
    "elapsed_seconds": elapsed,
    "checksum": checksum,
    "matrix_shape": [4096, 4096]
}

with open("\${tmpdir}/pl-runtime-torch-metrics.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
with open("\${tmpdir}/pl-runtime-torch-run.txt", "w", encoding="utf-8") as fh:
    fh.write("pl runtime torch slurm gpu compute complete\n")
print(json.dumps(payload), flush=True)
PY

copy_with_retry "\${tmpdir}/pl-runtime-torch-metrics.json" /orangefs/training/slurm-pilot/plruntime-torch/pl-runtime-torch-metrics.json
copy_with_retry "\${tmpdir}/pl-runtime-torch-run.txt" /orangefs/training/slurm-pilot/plruntime-torch/pl-runtime-torch-run.txt
EOF
  sbatch /tmp/plruntime-torch-gpucompute.sbatch
  echo ---
  squeue
'
