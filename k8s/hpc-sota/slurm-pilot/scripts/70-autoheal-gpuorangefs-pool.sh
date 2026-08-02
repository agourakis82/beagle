#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/lib-kubeconfig.sh
source "${SCRIPT_DIR}/lib-kubeconfig.sh"

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
LABEL_SELECTOR="${LABEL_SELECTOR:-sounio.dev/slurm-worker-gpuorangefs=true}"
AUTOHEAL_BIN="${AUTOHEAL_BIN:-${SCRIPT_DIR}/69-autoheal-gpuorangefs-worker.sh}"
OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile}"
OUT_FILE="${OUT_FILE:-${OUT_DIR}/slurm_gpuorangefs_autoheal.prom}"

mkdir -p "${OUT_DIR}"

mapfile -t NODES < <(${KUBECTL_BIN} get nodes -l "${LABEL_SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

declare -A NODE_STATUS=()
declare -A NODE_CODE=()

if [[ "${#NODES[@]}" -eq 0 ]]; then
  echo "[gpuorangefs-pool-autoheal] no admitted nodes"
  total_nodes=0
  healthy=0
  quarantined=0
  repaired=0
  deferred=0
  failed=0
  last_run_success=1
  start_ts="$(date +%s)"
  end_ts="${start_ts}"
else
  hard_fail=0
  deferred=0
  healthy=0
  quarantined=0
  repaired=0
  failed=0
  start_ts="$(date +%s)"

  for node in "${NODES[@]}"; do
    echo "[gpuorangefs-pool-autoheal] checking ${node}"
    set +e
    output="$("${AUTOHEAL_BIN}" "${node}" 2>&1)"
    rc=$?
    set -e
    printf '%s\n' "${output}"

    if [[ "${rc}" -eq 0 ]]; then
      if grep -q ': repaired id=' <<<"${output}"; then
        NODE_STATUS["${node}"]="repaired"
        NODE_CODE["${node}"]=2
        repaired=$((repaired + 1))
      elif grep -q ': quarantined; nothing to heal' <<<"${output}"; then
        NODE_STATUS["${node}"]="quarantined"
        NODE_CODE["${node}"]=0
        quarantined=$((quarantined + 1))
      else
        NODE_STATUS["${node}"]="healthy"
        NODE_CODE["${node}"]=1
        healthy=$((healthy + 1))
      fi
      echo "[gpuorangefs-pool-autoheal] ${node}: ok"
      continue
    fi

    if [[ "${rc}" -eq 2 ]]; then
      NODE_STATUS["${node}"]="deferred"
      NODE_CODE["${node}"]=3
      deferred=$((deferred + 1))
      echo "[gpuorangefs-pool-autoheal] ${node}: deferred because active jobs are still present"
      continue
    fi

    NODE_STATUS["${node}"]="failed"
    NODE_CODE["${node}"]=4
    failed=$((failed + 1))
    hard_fail=1
    echo "[gpuorangefs-pool-autoheal] ${node}: autoheal failed with rc=${rc}" >&2
  done

  end_ts="$(date +%s)"
  total_nodes="${#NODES[@]}"
  if [[ "${hard_fail}" -ne 0 ]]; then
    last_run_success=0
  else
    last_run_success=1
  fi
fi

tmp="$(mktemp "${OUT_FILE}.XXXXXX")"
duration=$((end_ts - start_ts))
cat > "${tmp}" <<EOF
# HELP darwin_slurm_gpuorangefs_autoheal_last_run_success Whether the last gpuorangefs pool autoheal run completed without hard failures.
# TYPE darwin_slurm_gpuorangefs_autoheal_last_run_success gauge
darwin_slurm_gpuorangefs_autoheal_last_run_success ${last_run_success}
# HELP darwin_slurm_gpuorangefs_autoheal_last_run_unixtime Unix timestamp of the last gpuorangefs pool autoheal run.
# TYPE darwin_slurm_gpuorangefs_autoheal_last_run_unixtime gauge
darwin_slurm_gpuorangefs_autoheal_last_run_unixtime ${end_ts}
# HELP darwin_slurm_gpuorangefs_autoheal_last_run_duration_seconds Duration in seconds of the last gpuorangefs pool autoheal run.
# TYPE darwin_slurm_gpuorangefs_autoheal_last_run_duration_seconds gauge
darwin_slurm_gpuorangefs_autoheal_last_run_duration_seconds ${duration}
# HELP darwin_slurm_gpuorangefs_autoheal_admitted_nodes Number of admitted gpuorangefs nodes inspected by the last run.
# TYPE darwin_slurm_gpuorangefs_autoheal_admitted_nodes gauge
darwin_slurm_gpuorangefs_autoheal_admitted_nodes ${total_nodes}
# HELP darwin_slurm_gpuorangefs_autoheal_healthy_nodes Number of healthy gpuorangefs nodes observed in the last run.
# TYPE darwin_slurm_gpuorangefs_autoheal_healthy_nodes gauge
darwin_slurm_gpuorangefs_autoheal_healthy_nodes ${healthy}
# HELP darwin_slurm_gpuorangefs_autoheal_quarantined_nodes Number of gpuorangefs nodes that were already quarantined in the last run.
# TYPE darwin_slurm_gpuorangefs_autoheal_quarantined_nodes gauge
darwin_slurm_gpuorangefs_autoheal_quarantined_nodes ${quarantined}
# HELP darwin_slurm_gpuorangefs_autoheal_repaired_nodes Number of gpuorangefs nodes repaired by the last run.
# TYPE darwin_slurm_gpuorangefs_autoheal_repaired_nodes gauge
darwin_slurm_gpuorangefs_autoheal_repaired_nodes ${repaired}
# HELP darwin_slurm_gpuorangefs_autoheal_deferred_nodes Number of unhealthy gpuorangefs nodes deferred due to active jobs in the last run.
# TYPE darwin_slurm_gpuorangefs_autoheal_deferred_nodes gauge
darwin_slurm_gpuorangefs_autoheal_deferred_nodes ${deferred}
# HELP darwin_slurm_gpuorangefs_autoheal_failed_nodes Number of gpuorangefs nodes whose autoheal failed in the last run.
# TYPE darwin_slurm_gpuorangefs_autoheal_failed_nodes gauge
darwin_slurm_gpuorangefs_autoheal_failed_nodes ${failed}
EOF

{
  echo "# HELP darwin_slurm_gpuorangefs_worker_state_code Status code for the last autoheal evaluation of a gpuorangefs worker node."
  echo "# TYPE darwin_slurm_gpuorangefs_worker_state_code gauge"
} >> "${tmp}"

for node in "${NODES[@]}"; do
  status="${NODE_STATUS[${node}]:-unknown}"
  code="${NODE_CODE[${node}]:-9}"
  echo "darwin_slurm_gpuorangefs_worker_state_code{node=\"${node}\",status=\"${status}\"} ${code}" >> "${tmp}"
done

mv "${tmp}" "${OUT_FILE}"
chmod 0644 "${OUT_FILE}"

if [[ "${last_run_success}" -ne 1 ]]; then
  exit 1
fi

if [[ "${deferred}" -ne 0 ]]; then
  echo "[gpuorangefs-pool-autoheal] completed with deferred nodes"
fi
