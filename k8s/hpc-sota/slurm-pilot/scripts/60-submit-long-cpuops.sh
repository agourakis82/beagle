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
  mkdir -p /orangefs/training/slurm-pilot/long
  cat >/tmp/long-cpuops.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J cpu-long
#SBATCH -p cpu-ops
#SBATCH -A pbpk
#SBATCH --qos=long
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
set -euo pipefail
python3 <<PY
import json, os, pathlib, socket, time
payload = {
    "job_id": int(os.environ.get("SLURM_JOB_ID", "0")),
    "job_name": os.environ.get("SLURM_JOB_NAME"),
    "account": os.environ.get("SLURM_JOB_ACCOUNT"),
    "qos": os.environ.get("SLURM_JOB_QOS"),
    "partition": os.environ.get("SLURM_JOB_PARTITION"),
    "host": socket.gethostname(),
    "timestamp": time.time(),
}
pathlib.Path("/orangefs/training/slurm-pilot/long/cpu-long-summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
print(json.dumps(payload), flush=True)
PY
EOF
  sbatch /tmp/long-cpuops.sbatch
  echo ---
  squeue
'
