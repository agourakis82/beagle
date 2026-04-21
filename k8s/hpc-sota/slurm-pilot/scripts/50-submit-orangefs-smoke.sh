#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

LOGIN_POD="$(
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" get pods -o name \
    | grep -E 'login|slinky' \
    | head -n1 \
    | sed 's#pod/##'
)"

if [[ -z "${LOGIN_POD}" ]]; then
  echo "could not find a Slurm login pod in namespace ${NS}" >&2
  exit 1
fi

KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc '
  set -euo pipefail
  mkdir -p /orangefs/training/slurm-pilot
  cat >/tmp/orangefs-smoke.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J orangefs-smoke
#SBATCH -p gpu-orangefs
#SBATCH -N 1
#SBATCH -n 1
set -euo pipefail
mkdir -p /orangefs/training/slurm-pilot
echo "job_id=\${SLURM_JOB_ID} host=\$(hostname)" > /orangefs/training/slurm-pilot/slurm-orangefs-smoke-\${SLURM_JOB_ID}.txt
hostname
ls -ld /orangefs/training /orangefs/training/slurm-pilot
EOF
  sbatch /tmp/orangefs-smoke.sbatch
  echo ---
  squeue
'
