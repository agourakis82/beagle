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
  mkdir -p /orangefs/training/slurm-pilot/plruntime-stress
  cat >/tmp/plruntime-gpu-stress.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J plruntime-stress
#SBATCH -p gpu-orangefs
#SBATCH -A plruntime
#SBATCH --qos=burst
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
set -euo pipefail
copy_with_retry() {
  local src="\$1"
  local dst="\$2"
  local attempt
  local tmp_dst="\${dst}.tmp"
  for attempt in \$(seq 1 15); do
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
tmpdir=\$(mktemp -d /tmp/plruntime-gpu-stress.XXXXXX)
trap "rm -rf \"\${tmpdir}\"" EXIT
export LD_LIBRARY_PATH="/host-nvidia:\${LD_LIBRARY_PATH:-}"
export PLRUNTIME_STRESS_TMPDIR="\${tmpdir}"
python3 <<PY
import hashlib, json, os, pathlib, socket, subprocess, time

tmpdir = pathlib.Path(os.environ["PLRUNTIME_STRESS_TMPDIR"])
tmpdir.mkdir(parents=True, exist_ok=True)

payload = {
    "job_id": int(os.environ.get("SLURM_JOB_ID", "0")),
    "job_name": os.environ.get("SLURM_JOB_NAME"),
    "account": os.environ.get("SLURM_JOB_ACCOUNT"),
    "partition": os.environ.get("SLURM_JOB_PARTITION"),
    "qos": os.environ.get("SLURM_JOB_QOS"),
    "host": socket.gethostname(),
    "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
}

env = os.environ.copy()
env["LD_LIBRARY_PATH"] = "/host-nvidia:" + env.get("LD_LIBRARY_PATH", "")

def capture(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT, timeout=15, env=env).strip()
    except Exception as exc:
        return f"ERROR: {exc!r}"

payload["nvidia_smi_L"] = capture(["/host-nvidia/nvidia-smi", "-L"])
payload["nvidia_smi_query_before"] = capture([
    "/host-nvidia/nvidia-smi",
    "--query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total",
    "--format=csv,noheader,nounits",
])

iters = 150000
checkpoint_every = 25000
checksum = 0
digest = hashlib.sha256()
start = time.perf_counter()
samples = []
for i in range(1, iters + 1):
    value = ((i * 2654435761) ^ (i >> 3)) & 0xFFFFFFFF
    checksum = (checksum + value) % 1000000007
    if i % checkpoint_every == 0:
      blob = f"{i}:{checksum}".encode("utf-8")
      digest.update(blob)
      samples.append({"iteration": i, "checksum": checksum})
elapsed = time.perf_counter() - start

payload["iterations"] = iters
payload["elapsed_seconds"] = elapsed
payload["ops_per_second"] = round(iters / elapsed, 2) if elapsed else None
payload["checksum"] = checksum
payload["sha256"] = digest.hexdigest()
payload["sample_points"] = samples
payload["nvidia_smi_query_after"] = capture([
    "/host-nvidia/nvidia-smi",
    "--query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total",
    "--format=csv,noheader,nounits",
])

(tmpdir / "pl-runtime-stress-metrics.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
(tmpdir / "pl-runtime-stress.txt").write_text("pl runtime slurm gpu stress complete\n", encoding="utf-8")
print(json.dumps(payload), flush=True)
PY
copy_with_retry "\${tmpdir}/pl-runtime-stress-metrics.json" /orangefs/training/slurm-pilot/plruntime-stress/pl-runtime-stress-metrics.json
copy_with_retry "\${tmpdir}/pl-runtime-stress.txt" /orangefs/training/slurm-pilot/plruntime-stress/pl-runtime-stress.txt
hostname
ls -l /orangefs/training/slurm-pilot/plruntime-stress
EOF
  sbatch /tmp/plruntime-gpu-stress.sbatch
  echo ---
  squeue
'
