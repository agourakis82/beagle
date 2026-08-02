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
  mkdir -p /orangefs/training/slurm-pilot/plruntime
  cat >/tmp/plruntime-gpuorangefs.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J plruntime-gpu
#SBATCH -p gpu-orangefs
#SBATCH -A plruntime
#SBATCH --qos=gpuorangefs
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
set -euo pipefail
copy_with_retry() {
  local src="\$1"
  local dst="\$2"
  local attempt
  for attempt in \$(seq 1 15); do
    mkdir -p "\$(dirname "\$dst")" || true
    rm -f "\$dst" || true
    if cp -f "\$src" "\$dst" && [ -s "\$dst" ]; then
      return 0
    fi
    sleep 1
  done
  echo "failed to copy \$src -> \$dst" >&2
  return 1
}
tmpdir=\$(mktemp -d /tmp/plruntime-gpu.XXXXXX)
trap "rm -rf \"\${tmpdir}\"" EXIT
export PLRUNTIME_TMPDIR="\${tmpdir}"
export LD_LIBRARY_PATH="/host-nvidia:\${LD_LIBRARY_PATH:-}"
python3 <<PY
import glob, json, os, pathlib, shutil, socket, subprocess, time

out = pathlib.Path(os.environ["PLRUNTIME_TMPDIR"])
out.mkdir(parents=True, exist_ok=True)

code = compile("sum((i*i)%97 for i in range(4096))", "<plruntime>", "eval")
iters = 5000
start = time.perf_counter()
checksum = 0
for _ in range(iters):
    checksum += eval(code)
elapsed = time.perf_counter() - start

payload = {
    "job_id": int(os.environ.get("SLURM_JOB_ID", "0")),
    "host": socket.gethostname(),
    "account": os.environ.get("SLURM_JOB_ACCOUNT"),
    "partition": os.environ.get("SLURM_JOB_PARTITION"),
    "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
    "gpu_devices": sorted(glob.glob("/dev/nvidia*")),
    "python": shutil.which("python3"),
    "iterations": iters,
    "elapsed_seconds": elapsed,
    "ops_per_second": round(iters / elapsed, 2) if elapsed else None,
    "checksum": checksum,
}

try:
    payload["nvidia_smi"] = subprocess.check_output(
        ["/host-nvidia/nvidia-smi", "-L"],
        text=True,
        env=os.environ.copy(),
        stderr=subprocess.STDOUT,
        timeout=10,
    ).strip()
except Exception as exc:
    payload["nvidia_smi_error"] = repr(exc)

(out / "pl-runtime-metrics.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
(out / "pl-runtime-run.txt").write_text("pl runtime slurm gpu pilot complete\n", encoding="utf-8")
print(json.dumps(payload), flush=True)
PY
copy_with_retry "\${tmpdir}/pl-runtime-metrics.json" /orangefs/training/slurm-pilot/plruntime/pl-runtime-metrics.json
copy_with_retry "\${tmpdir}/pl-runtime-run.txt" /orangefs/training/slurm-pilot/plruntime/pl-runtime-run.txt
hostname
ls -l /orangefs/training/slurm-pilot/plruntime
EOF
  sbatch /tmp/plruntime-gpuorangefs.sbatch
  echo ---
  squeue
'
