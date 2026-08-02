#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile}"
OUT_FILE="${OUT_DIR}/sounio_abide_runner.prom"
STATE_FILE="${STATE_FILE:-/home/devsounio/beagle/k8s/hpc-sota/state/abide_campaign_last_submit.env}"
STATE_HISTORY_FILE="${STATE_HISTORY_FILE:-/home/devsounio/beagle/k8s/hpc-sota/state/abide_campaign_recent_submits.tsv}"

mkdir -p "${OUT_DIR}"

run_id="unknown"
job_id="unknown"
state_written_unix="0"
payload_transfer_mode="unknown"
persist_mode="unknown"
sbatch_nodelist="unknown"
sbatch_exclude=""
stage_root="unknown"
results_dir="unknown"
manifest_path="unknown"
ns="unknown"
login_pod="unknown"

if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  run_id="${RUN_ID:-unknown}"
  job_id="${JOB_ID:-unknown}"
  state_written_unix="${STATE_WRITTEN_UNIX:-0}"
  payload_transfer_mode="${PAYLOAD_TRANSFER_MODE:-unknown}"
  persist_mode="${PERSIST_MODE:-unknown}"
  sbatch_nodelist="${SBATCH_NODELIST:-unknown}"
  sbatch_exclude="${SBATCH_EXCLUDE:-}"
  stage_root="${STAGE_ROOT:-unknown}"
  results_dir="${ORANGEFS_RESULTS_DIR:-unknown}"
  manifest_path="${ABIDE_MANIFEST_PATH:-unknown}"
  ns="${NS:-unknown}"
  login_pod="${LOGIN_POD:-unknown}"
fi

payload_code=0
case "${payload_transfer_mode}" in
  embedded) payload_code=1 ;;
  sbcast) payload_code=2 ;;
  *) payload_code=0 ;;
esac

persist_code=0
case "${persist_mode}" in
  orangefs) persist_code=1 ;;
  worker_local) persist_code=2 ;;
  *) persist_code=0 ;;
esac

now="$(date +%s)"
if [[ "${state_written_unix}" =~ ^[0-9]+$ ]] && [[ "${state_written_unix}" -gt 0 ]]; then
  last_submit_age_seconds=$((now - state_written_unix))
else
  state_written_unix=0
  last_submit_age_seconds=-1
fi

tmp="$(mktemp "${OUT_FILE}.XXXXXX")"
cat > "${tmp}" <<EOF
# HELP darwin_sounio_abide_runner_metrics_last_emit_unixtime Unix timestamp of the last successful ABIDE runner metrics emission on t560.
# TYPE darwin_sounio_abide_runner_metrics_last_emit_unixtime gauge
darwin_sounio_abide_runner_metrics_last_emit_unixtime ${now}
# HELP darwin_sounio_abide_runner_last_submit_unixtime Unix timestamp of the last ABIDE campaign submit observed on t560.
# TYPE darwin_sounio_abide_runner_last_submit_unixtime gauge
darwin_sounio_abide_runner_last_submit_unixtime ${state_written_unix}
# HELP darwin_sounio_abide_runner_last_submit_age_seconds Age in seconds of the last ABIDE campaign submit observed on t560.
# TYPE darwin_sounio_abide_runner_last_submit_age_seconds gauge
darwin_sounio_abide_runner_last_submit_age_seconds ${last_submit_age_seconds}
# HELP darwin_sounio_abide_runner_last_payload_transfer_mode_code Numeric code for the last ABIDE campaign payload transfer mode (0 unknown, 1 embedded, 2 sbcast).
# TYPE darwin_sounio_abide_runner_last_payload_transfer_mode_code gauge
darwin_sounio_abide_runner_last_payload_transfer_mode_code ${payload_code}
# HELP darwin_sounio_abide_runner_last_persist_mode_code Numeric code for the last ABIDE campaign persist mode (0 unknown, 1 orangefs, 2 worker_local).
# TYPE darwin_sounio_abide_runner_last_persist_mode_code gauge
darwin_sounio_abide_runner_last_persist_mode_code ${persist_code}
# HELP darwin_sounio_abide_runner_last_submit_info Labels describing the last ABIDE campaign submit observed on t560.
# TYPE darwin_sounio_abide_runner_last_submit_info gauge
darwin_sounio_abide_runner_last_submit_info{run_id="${run_id}",job_id="${job_id}",payload_transfer_mode="${payload_transfer_mode}",persist_mode="${persist_mode}",sbatch_nodelist="${sbatch_nodelist}",sbatch_exclude="${sbatch_exclude}",namespace="${ns}",login_pod="${login_pod}"} 1
# HELP darwin_sounio_abide_runner_last_manifest_info Labels describing the manifest and result roots used by the last ABIDE campaign submit observed on t560.
# TYPE darwin_sounio_abide_runner_last_manifest_info gauge
darwin_sounio_abide_runner_last_manifest_info{run_id="${run_id}",stage_root="${stage_root}",results_dir="${results_dir}",manifest_path="${manifest_path}"} 1
EOF

{
  echo "# HELP darwin_sounio_abide_runner_recent_submit_info Labels describing recent ABIDE campaign submits observed on t560."
  echo "# TYPE darwin_sounio_abide_runner_recent_submit_info gauge"
  echo "# HELP darwin_sounio_abide_runner_recent_submit_unixtime Unix timestamp of recent ABIDE campaign submits observed on t560."
  echo "# TYPE darwin_sounio_abide_runner_recent_submit_unixtime gauge"
} >> "${tmp}"
python3 - "${STATE_HISTORY_FILE}" >> "${tmp}" <<'PY'
import csv
import pathlib
import sys

history_path = pathlib.Path(sys.argv[1])
if not history_path.exists():
    raise SystemExit(0)

def esc(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')

rows = []
with history_path.open(newline="") as fh:
    reader = csv.reader(fh, delimiter="\t")
    rows = [row for row in reader if row]

rows = rows[-5:]
for slot, row in enumerate(rows, start=1):
    padded = (row + [""] * 12)[:12]
    (
        recent_written_unix,
        recent_run_id,
        recent_job_id,
        recent_payload_transfer_mode,
        recent_persist_mode,
        recent_sbatch_nodelist,
        recent_sbatch_exclude,
        recent_stage_root,
        recent_results_dir,
        recent_manifest_path,
        recent_ns,
        recent_login_pod,
    ) = padded
    if not recent_run_id:
        continue
    print(
        'darwin_sounio_abide_runner_recent_submit_info{slot="%d",run_id="%s",job_id="%s",payload_transfer_mode="%s",persist_mode="%s",sbatch_nodelist="%s",sbatch_exclude="%s",namespace="%s",login_pod="%s",stage_root="%s",results_dir="%s",manifest_path="%s"} 1'
        % (
            slot,
            esc(recent_run_id or "unknown"),
            esc(recent_job_id or "unknown"),
            esc(recent_payload_transfer_mode or "unknown"),
            esc(recent_persist_mode or "unknown"),
            esc(recent_sbatch_nodelist or "unknown"),
            esc(recent_sbatch_exclude or ""),
            esc(recent_ns or "unknown"),
            esc(recent_login_pod or "unknown"),
            esc(recent_stage_root or "unknown"),
            esc(recent_results_dir or "unknown"),
            esc(recent_manifest_path or "unknown"),
        )
    )
    print(
        'darwin_sounio_abide_runner_recent_submit_unixtime{slot="%d",run_id="%s"} %s'
        % (slot, esc(recent_run_id or "unknown"), recent_written_unix or "0")
    )
PY

mv "${tmp}" "${OUT_FILE}"
chmod 0644 "${OUT_FILE}"
