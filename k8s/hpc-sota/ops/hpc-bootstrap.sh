#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lab-ops.sh
source "${SCRIPT_DIR}/lab-ops.sh"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

require_cmd bash
require_cmd hostname

have_local_control_plane() {
  command -v kubectl >/dev/null 2>&1 &&
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes >/dev/null 2>&1
}

bootstrap_kctl() {
  if have_local_control_plane; then
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
  else
    lab_kctl "$@"
  fi
}

bootstrap_login_pod() {
  if have_local_control_plane; then
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n slurm-pilot get pod -o name |
      grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2
  else
    lab_login_pod
  fi
}

bootstrap_slurm_exec() {
  if have_local_control_plane; then
    local pod
    pod="$(bootstrap_login_pod)"
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n slurm-pilot exec "$pod" -- "$@"
  else
    lab_slurm_exec "$@"
  fi
}

bootstrap_slurm_status() {
  echo "== scontrol ping =="
  bootstrap_slurm_exec scontrol ping
  echo
  echo "== sinfo =="
  bootstrap_slurm_exec sinfo
  echo
  echo "== recent sacct =="
  bootstrap_slurm_exec sacct -S now-1day --format=JobID,JobName,Partition,Account,QOS,State,ExitCode,Start,End,NodeList
}

bootstrap_orangefs_status() {
  if have_local_control_plane; then
    echo "== OrangeFS runtime on t560 =="
    sudo -n systemctl status orangefs-client-runtime.service --no-pager --lines=0
    echo
    echo "== OrangeFS mount =="
    mount | grep pvfs2
  else
    lab_orangefs_status
  fi
}

bootstrap_surface_status() {
  bash "${SCRIPT_DIR}/hpc-surface-doctor.sh"
}

bootstrap_kueue_status() {
  bootstrap_kctl get clusterqueues,localqueues -A
}

bootstrap_context() {
  echo "host: $(hostname -f 2>/dev/null || hostname)"
  echo "lab root: /home/devsounio/beagle/k8s/hpc-sota"
  if have_local_control_plane; then
    echo "control plane access: local /etc/kubernetes/admin.conf"
  else
    echo "control plane access: remote via $(lab_ops_host)"
  fi
}

section() {
  echo
  echo "== $1 =="
}

safe_run() {
  local title="$1"
  shift
  section "$title"
  if ! "$@"; then
    echo "[warn] command failed: $*"
  fi
}

cat <<'EOF'
HPC agent bootstrap snapshot

This script is read-only.
It gives the shortest operational picture of the live Beagle AI/HPC stack.
For Tailscale-vs-management-LAN regressions, also run: ./ops/hpc-route-doctor.sh
For Slurm accounting backend health, also run: ./ops/slurmdbd-backend-doctor.sh
For shared client-visible surfaces, also run: ./ops/hpc-surface-doctor.sh
EOF

section "Control Plane Truths"
cat <<'EOF'
- Machine source of truth: /home/devsounio
- Lab root: /home/devsounio/beagle/k8s/hpc-sota
- Proven lanes:
  - K8s + JobSet + Kueue + OrangeFS
  - Slurm/Slinky + OrangeFS + K8s
- Green tracks:
  - pbpk
  - omics
  - pl-runtime
- Slurm accounting source of truth:
  - externalized K8s MariaDB candidate via slurmdbd-mariadb-ext.darwin.lan
- Worker-safe Kubernetes API endpoint:
  - https://k8s-api.darwin.lan:6443
- Worker resolution for that endpoint:
  - k8s-api.darwin.lan -> 10.100.100.2
- Do not casually revert workers to:
  - https://192.168.3.169:6443
- Proxmox management note:
  - 192.168.3.169 remains the t560/vmbr0 management IP
- Root cause note:
  - t560 was previously accepting the overlapping Tailscale subnet route 192.168.3.0/24
- Current Tailscale safety setting on t560:
  - accept-routes=false
- Slurm migration MariaDBs:
  - slurm-pilot-mariadb remains intentionally scaled to 0
  - slurm-pilot-mariadb-ext is the active live backend and currently expected to be 1/1 Running
- Sounio source of truth:
  - /home/devsounio/sounio
- Sounio dev branch:
  - integration/sounio-dev-ready-base
- Stable Sounio workspace service:
  - sounio-workspace
- Grafana:
  - http://darwin-grafana.tail21cbc4.ts.net
EOF

safe_run "Agent Entry Context" bootstrap_context
safe_run "Shared Surfaces" bootstrap_surface_status
safe_run "Kubernetes Nodes" bootstrap_kctl get nodes -o wide
safe_run "Slurm Pilot Pods" bootstrap_kctl -n slurm-pilot get pods -o wide
safe_run "Kueue Queues" bootstrap_kueue_status
safe_run "Slurm Status" bootstrap_slurm_status
safe_run "OrangeFS Status" bootstrap_orangefs_status
safe_run "Sounio Workspace Surfaces" bootstrap_kctl -n beagle get svc,statefulset,pod -l app.kubernetes.io/name=sounio-workspace-habitat -o wide
safe_run "Grafana Surface" bootstrap_kctl -n darwin-platform get svc,pod -l app.kubernetes.io/name=grafana -o wide

section "Decision Reminder"
cat <<'EOF'
- Choose Slurm for:
  - PBPK
  - omics
  - pl-runtime
  - QoS, partition, accounting, queue semantics
- Choose Kubernetes for:
  - distributed training
  - JobSet
  - Kueue
  - controller-native experiments
EOF

section "Known-Good Commands"
cat <<'EOF'
From /home/devsounio/beagle/k8s/hpc-sota:

source ops/lab-ops.sh
lab_status
lab_slurm_status
lab_orangefs_status

Proven Slurm submits:
- lab_copy_and_run slurm-pilot/scripts/55-submit-pbpk-cpuops.sh
- lab_copy_and_run slurm-pilot/scripts/57-submit-omics-cpuops.sh
- lab_copy_and_run slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh
- lab_copy_and_run slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh

Proven Kubernetes runs:
- bash orangefs-hybrid/run-k8s-orangefs-training-canary.sh
- bash orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh
- bash orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh
EOF

section "Yellow Zones"
cat <<'EOF'
- slurm-pilot/SLURMDBD_EVOLUTION.md
- slurm-pilot/values/mariadb-values.yaml
- slurm-pilot/values/slurm-pilot-values.external-db.example.yaml
- /home/devsounio/beagle/k8s/sounio-workspace/configmap.yaml
- /home/devsounio/projects/sounio/WORKSPACE_K8S.md

Do not edit these casually.
EOF
