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
  mkdir -p /orangefs/training/slurm-pilot/qos-proof
  cat >/tmp/qos-proof.sbatch <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
tag="$1"
sleep_seconds="$2"
out=/orangefs/training/slurm-pilot/qos-proof
mkdir -p "$out"
sleep "$sleep_seconds"
copy_with_retry() {
  local src="$1"
  local dst="$2"
  local tmp_dst="${dst}.tmp"
  local attempt
  for attempt in $(seq 1 15); do
    rm -f "$dst" "$tmp_dst" || true
    if cp -f "$src" "$tmp_dst" && [ -s "$tmp_dst" ] && mv -f "$tmp_dst" "$dst" && [ -s "$dst" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}
tmp="$(mktemp)"
python3 <<PY >"$tmp"
import json, os, socket, time
payload = {
    "job_id": int(os.environ.get("SLURM_JOB_ID", "0")),
    "job_name": os.environ.get("SLURM_JOB_NAME"),
    "qos": os.environ.get("SLURM_JOB_QOS"),
    "host": socket.gethostname(),
    "timestamp": time.time(),
    "tag": os.environ.get("QOS_PROOF_TAG"),
}
print(json.dumps(payload, indent=2), flush=True)
PY
dest="${out}/${SLURM_JOB_ID}-${tag}.json"
copy_with_retry "$tmp" "$dest" || echo "warning: could not persist $dest" >&2
cat "$tmp"
rm -f "$tmp"
EOF

  blocker=$(QOS_PROOF_TAG=blocker sbatch --parsable -J qos-blocker -p gpu-orangefs -A plruntime --qos=normal --nodelist=gpuorangefs-r770-proxmox --gres=gpu:1 --export=ALL,QOS_PROOF_TAG=blocker /tmp/qos-proof.sbatch blocker 12)
  sleep 1
  normal=$(QOS_PROOF_TAG=normal sbatch --parsable -J qos-normal -p gpu-orangefs -A plruntime --qos=normal --nodelist=gpuorangefs-r770-proxmox --gres=gpu:1 --export=ALL,QOS_PROOF_TAG=normal /tmp/qos-proof.sbatch normal 2)
  sleep 1
  burst=$(QOS_PROOF_TAG=burst sbatch --parsable -J qos-burst -p gpu-orangefs -A plruntime --qos=burst --nodelist=gpuorangefs-r770-proxmox --gres=gpu:1 --export=ALL,QOS_PROOF_TAG=burst /tmp/qos-proof.sbatch burst 2)

  echo "blocker=$blocker"
  echo "normal=$normal"
  echo "burst=$burst"

  for i in $(seq 1 30); do
    states="$(sacct -n -j ${blocker},${normal},${burst} -X -o JobID,State,Start,End | sed "/^$/d")"
    echo "--- poll $i ---"
    echo "$states"
    b_state=$(sacct -n -j "${burst}" -X -o State | head -n1 | xargs || true)
    n_state=$(sacct -n -j "${normal}" -X -o State | head -n1 | xargs || true)
    if { [ "$b_state" = "COMPLETED" ] || [ "$b_state" = "FAILED" ] || [ "$b_state" = "CANCELLED" ] || [ "$b_state" = "TIMEOUT" ]; } \
      && { [ "$n_state" = "COMPLETED" ] || [ "$n_state" = "FAILED" ] || [ "$n_state" = "CANCELLED" ] || [ "$n_state" = "TIMEOUT" ]; }; then
      break
    fi
    sleep 2
  done

  echo "--- final sacct ---"
  sacct -j ${blocker},${normal},${burst} -o JobID,JobName,QOS,State,Submit,Start,End,NodeList
'
