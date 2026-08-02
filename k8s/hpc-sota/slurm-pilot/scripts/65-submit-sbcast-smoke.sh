#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

LOGIN_DEPLOYMENT="slurm-pilot-login-slinky"
LOGIN_TARGET="deploy/${LOGIN_DEPLOYMENT}"

if ! kubectl -n "${NS}" get deployment "${LOGIN_DEPLOYMENT}" >/dev/null 2>&1; then
  echo "could not find deployment/${LOGIN_DEPLOYMENT} in namespace ${NS}" >&2
  exit 1
fi

kubectl -n "${NS}" exec "${LOGIN_TARGET}" -- bash -lc '
  set -euo pipefail
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  outdir="/orangefs/training/sounio/slurm-smokes"
  mkdir -p "${outdir}"
  job_out="${outdir}/sbcast-${stamp}-%j.out"
  job_err="${outdir}/sbcast-${stamp}-%j.err"

  cat >/tmp/sbcast-smoke.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J sbcast-smoke
#SBATCH -p gpu-orangefs
#SBATCH -w gpuorangefs-r770-proxmox
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --time=00:02:00
#SBATCH --output=${job_out}
#SBATCH --error=${job_err}
set -euo pipefail
src="/tmp/sbcast-src-\$\$.txt"
dst="/tmp/sbcast-dst-\$\$.txt"
printf "hello-from-sbcast\\n" > "\${src}"
echo "pre-sbcast host=\$(hostname -s) job=\${SLURM_JOB_ID}" >&2
command -v sbcast >&2
sbcast -f "\${src}" "\${dst}"
cmp -s "\${src}" "\${dst}"
cat "\${dst}"
EOF

  sbatch /tmp/sbcast-smoke.sbatch
'
