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
  mkdir -p /orangefs/training/slurm-pilot/omics
  cat >/tmp/omics-cpuops.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH -J omics-cpuops
#SBATCH -p cpu-ops
#SBATCH -A omics
#SBATCH --qos=cpuops
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
tmpdir=\$(mktemp -d /tmp/omics-cpuops.XXXXXX)
trap "rm -rf \"\${tmpdir}\"" EXIT
export OMICS_TMPDIR="\${tmpdir}"
python3 <<PY
import csv, io, json, os, pathlib, random, time
out = pathlib.Path(os.environ["OMICS_TMPDIR"])
out.mkdir(parents=True, exist_ok=True)
random.seed(42)
rows = []
for gene_idx in range(1024):
    rows.append({
        "gene": f"GENE_{gene_idx:04d}",
        "expr_mean": round(random.random() * 100.0, 4),
        "expr_var": round(random.random() * 10.0, 4),
    })
buf = io.StringIO()
writer = csv.DictWriter(buf, fieldnames=["gene", "expr_mean", "expr_var"])
writer.writeheader()
writer.writerows(rows)
(out / "omics-expression-summary.csv").write_text(buf.getvalue(), encoding="utf-8")
payload = {
    "job_id": int(__import__("os").environ.get("SLURM_JOB_ID", "0")),
    "host": __import__("socket").gethostname(),
    "records": len(rows),
    "top_gene": max(rows, key=lambda row: row["expr_mean"])["gene"],
    "timestamp": time.time(),
}
(out / "omics-preprocess-summary.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
print(json.dumps(payload), flush=True)
PY
copy_with_retry "\${tmpdir}/omics-expression-summary.csv" /orangefs/training/slurm-pilot/omics/omics-expression-summary.csv
copy_with_retry "\${tmpdir}/omics-preprocess-summary.json" /orangefs/training/slurm-pilot/omics/omics-preprocess-summary.json
hostname
ls -l /orangefs/training/slurm-pilot/omics
EOF
  sbatch /tmp/omics-cpuops.sbatch
  echo ---
  squeue
'
