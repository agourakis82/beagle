#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

LOGIN_POD="$(
  kubectl -n "${NS}" get pods -o name \
    | grep -E 'login|slinky' \
    | head -n1 \
    | sed 's#pod/##'
)"

if [[ -z "${LOGIN_POD}" ]]; then
  echo "could not find a Slurm login pod in namespace ${NS}" >&2
  exit 1
fi

kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc '
  set -euo pipefail
  mkdir -p /orangefs/training/slurm-pilot/pbpk
  cat >/tmp/pbpk-cpuops.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J pbpk-cpuops
#SBATCH -p cpu-ops
#SBATCH -N 1
#SBATCH -n 1
set -euo pipefail
python3 <<PY
import json, math, pathlib, time
out = pathlib.Path("/orangefs/training/slurm-pilot/pbpk")
out.mkdir(parents=True, exist_ok=True)
times = [i * 0.5 for i in range(25)]
conc = [120.0 * math.exp(-0.18 * t) + 18.0 * math.exp(-0.03 * t) for t in times]
cmax = max(conc)
auc = sum((conc[i] + conc[i+1]) * 0.25 for i in range(len(conc)-1))
payload = {
    "job_id": int(__import__("os").environ.get("SLURM_JOB_ID", "0")),
    "host": __import__("socket").gethostname(),
    "cmax": cmax,
    "auc_proxy": auc,
    "samples": len(conc),
    "timestamp": time.time(),
}
(out / "pbpk-cpuops-summary.json").write_text(json.dumps(payload, indent=2))
PY
hostname
ls -l /orangefs/training/slurm-pilot/pbpk
EOF
  sbatch /tmp/pbpk-cpuops.sbatch
  echo ---
  squeue
'
