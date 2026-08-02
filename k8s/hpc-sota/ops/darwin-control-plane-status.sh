#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SLURM_NS="${DARWIN_STATUS_SLURM_NS:-slurm-pilot}"

deep=0
json=0

usage() {
  cat <<'EOF'
usage: darwin-control-plane-status.sh [--deep] [--json]

Read-only Darwin control-plane inventory for humans and agents.

Default mode prints the fast operational truth:
  - authority paths
  - Kubernetes nodes and allocatable resources
  - VM footprint and retired/stopped VMs
  - Slurm partitions and queue
  - GPU ownership
  - Sounio workspace surface
  - storage/mount quick view

Options:
  --deep   also run the existing doctors
  --json   emit a compact machine-readable JSON summary where practical
EOF
}

while (($#)); do
  case "$1" in
    --deep)
      deep=1
      ;;
    --json)
      json=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

have() {
  command -v "$1" >/dev/null 2>&1
}

section() {
  echo
  echo "== $1 =="
}

warn() {
  echo "WARN: $*" >&2
}

kctl() {
  if have sudo && sudo -n test -r /etc/kubernetes/admin.conf 2>/dev/null; then
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
  else
    kubectl "$@"
  fi
}

pve() {
  if have sudo; then
    sudo -n pvesh "$@"
  else
    pvesh "$@"
  fi
}

slurm_login_pod() {
  kctl -n "$SLURM_NS" get pod -o name 2>/dev/null |
    awk -F/ '/pod\/slurm-pilot-login/ {print $2; exit}'
}

slurm_cmd() {
  local mode="${DARWIN_STATUS_SLURM_MODE:-pilot}"

  if [[ "$mode" == "local" ]] && have "$1"; then
    "$@"
    return $?
  fi

  local pod
  pod="$(slurm_login_pod || true)"
  if [[ -n "$pod" ]]; then
    kctl -n "$SLURM_NS" exec "$pod" -- "$@"
    return $?
  fi

  return 127
}

local_slurm_summary() {
  if ! have scontrol; then
    return 0
  fi

  local cluster controller
  cluster="$(scontrol show config 2>/dev/null | awk -F= '/^ClusterName/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' || true)"
  controller="$(scontrol show config 2>/dev/null | awk -F= '/^SlurmctldHost/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' || true)"

  if [[ -n "$cluster" && "$cluster" != "beagle-slurm-pilot" ]]; then
    echo "WARN: bare host Slurm points at legacy cluster '${cluster}' (${controller:-unknown controller})"
    echo "      use Slurm pilot through the login pod for Darwin supercomputing truth"
  elif [[ -n "$cluster" ]]; then
    echo "PASS: bare host Slurm points at ${cluster}"
  fi
}

tmpdir="$(mktemp -d /tmp/darwin-control-plane-status.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

collect_k8s_nodes() {
  kctl get nodes -o json >"${tmpdir}/nodes.json" 2>/dev/null || return 1
}

collect_vms() {
  pve get /cluster/resources --type vm --output-format json >"${tmpdir}/vms.json" 2>/dev/null || return 1
}

if ((json)); then
  collect_k8s_nodes || true
  collect_vms || true
  jq -n \
    --arg generated_at "$(date -Is)" \
    --arg host "$(hostname -f 2>/dev/null || hostname)" \
    --slurpfile nodes "${tmpdir}/nodes.json" \
    --slurpfile vms "${tmpdir}/vms.json" '
      def gib_from_ki: (sub("Ki$"; "") | tonumber / 1048576);
      def gib_from_bytes: (. / 1073741824);
      {
        schema: "darwin.control_plane.status.v1",
        generated_at: $generated_at,
        host: $host,
        authority: {
          machine_root: "/home/devsounio",
          hpc_root: "/home/devsounio/beagle/k8s/hpc-sota",
          sounio_control: "/home/devsounio/projects/sounio",
          sounio_host_repo: "/home/devsounio/sounio",
          sounio_workspace: "/workspace/sounio"
        },
        kubernetes: (
          if ($nodes|length) > 0 then
            {
              node_count: ($nodes[0].items | length),
              allocatable_cpu: ($nodes[0].items | map(.status.allocatable.cpu | tonumber) | add),
              allocatable_memory_gib: (($nodes[0].items | map(.status.allocatable.memory | gib_from_ki) | add) * 10 | round / 10),
              allocatable_gpus: ($nodes[0].items | map(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) | add)
            }
          else null end
        ),
        vms: (
          if ($vms|length) > 0 then
            ($vms[0] | map(select(.type == "qemu")) as $all |
             map(select(.type == "qemu" and .status == "running")) as $running |
             {
               total_count: ($all | length),
               running_count: ($running | length),
               running_vcpu: ($running | map(.maxcpu // 0) | add // 0),
               running_configured_memory_gib: (($running | map(.maxmem // 0) | add // 0 | gib_from_bytes) | round),
               running_host_memory_gib: ((($running | map(.memhost // .mem // 0) | add // 0 | gib_from_bytes) * 10) | round / 10),
               running_cpu_cores_now: ((($running | map(.cpu // 0) | add // 0) * 1000) | round / 1000)
             })
          else null end
        )
      }'
  exit 0
fi

echo "Darwin control-plane status"
echo
echo "This script is read-only."
echo "generated_at: $(date -Is)"
echo "host:         $(hostname -f 2>/dev/null || hostname)"
echo "cwd:          $(pwd)"

section "Authority Map"
cat <<EOF
machine root:        /home/devsounio
HPC ops root:        ${ROOT_DIR}
Sounio control:      /home/devsounio/projects/sounio
Sounio host repo:    /home/devsounio/sounio
Sounio workspace:    /workspace/sounio
Sounio workspace svc beagle/sounio-workspace
Heavy execution:     Slurm scratch, not /workspace/sounio
EOF

section "Kubernetes Nodes"
if collect_k8s_nodes; then
  jq -r '
    ["NODE","STATUS","CPU","MEM_GiB","GPU","INTERNAL_IP","RUNTIME"],
    (.items[] | [
      .metadata.name,
      ([.status.conditions[] | select(.type == "Ready") | .status][0]),
      .status.allocatable.cpu,
      (((.status.allocatable.memory | sub("Ki$"; "") | tonumber) / 1048576) * 10 | round / 10),
      (.status.allocatable["nvidia.com/gpu"] // "0"),
      ([.status.addresses[] | select(.type == "InternalIP") | .address][0] // ""),
      (.status.nodeInfo.containerRuntimeVersion // "")
    ]),
    (["TOTAL","-",(.items | map(.status.allocatable.cpu | tonumber) | add),((.items | map(.status.allocatable.memory | sub("Ki$"; "") | tonumber) | add) / 1048576 * 10 | round / 10),(.items | map(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) | add),"-","-"])
    | @tsv
  ' "${tmpdir}/nodes.json" | column -t -s $'\t'
else
  warn "could not query Kubernetes nodes"
fi

section "Kubernetes Non-Running Pods"
if non_running="$(kctl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o wide 2>&1)"; then
  if [[ "$non_running" == "No resources found"* || -z "$non_running" ]]; then
    echo "none"
  else
    printf '%s\n' "$non_running"
  fi
  true
else
  printf '%s\n' "$non_running" >&2
  warn "could not query non-running pods"
fi

section "VM Footprint"
if collect_vms; then
  jq -r '
    ["VMID","NAME","NODE","STATUS","VCPU","RAM_CFG_GiB","RAM_HOST_GiB","CPU_NOW"],
    (.[] | select(.type == "qemu") | [
      .vmid,
      .name,
      .node,
      .status,
      .maxcpu,
      ((.maxmem / 1073741824) | round),
      ((((.memhost // .mem // 0) / 1073741824) * 10 | round) / 10),
      (((.cpu // 0) * 1000 | round) / 1000)
    ]),
    ([.[] | select(.type == "qemu" and .status == "running")] as $vms |
      ["RUNNING_TOTAL","-","-","-",($vms | map(.maxcpu // 0) | add // 0),((($vms | map(.maxmem // 0) | add // 0) / 1073741824) | round),(((($vms | map(.memhost // .mem // 0) | add // 0) / 1073741824) * 10 | round) / 10),((($vms | map(.cpu // 0) | add // 0) * 1000 | round) / 1000)])
    | @tsv
  ' "${tmpdir}/vms.json" | column -t -s $'\t'
else
  warn "could not query Proxmox VMs"
fi

section "Slurm"
echo "source: Slurm pilot login pod (${SLURM_NS})"
if slurm_cmd sinfo -N -o "%N %P %t %G %C" 2>/dev/null | column -t; then
  echo
  slurm_cmd squeue -o "%.18i %.9P %.24j %.8u %.2t %.10M %.6D %R" 2>/dev/null || true
else
  warn "could not query Slurm"
fi
local_slurm_summary

section "GPU Ownership"
echo "Kubernetes GPU consumers:"
gpu_consumer_nodes_file="${tmpdir}/gpu-consumer-nodes.txt"
if kctl get pods -A -o json >"${tmpdir}/pods.json" 2>/dev/null; then
  jq -r '
    ["NAMESPACE","POD","NODE","PHASE","GPU_UNITS"],
    (.items[] |
      ([.spec.containers[]? |
        ((.resources.limits["nvidia.com/gpu"] // .resources.requests["nvidia.com/gpu"] // "0") | tonumber)
      ] | add // 0) as $gpu |
      select($gpu > 0) |
      [.metadata.namespace,.metadata.name,(.spec.nodeName // "-"),.status.phase,($gpu|tostring)]
    ) | @tsv
  ' "${tmpdir}/pods.json" | column -t -s $'\t'
  jq -r '
    .items[] |
    ([.spec.containers[]? |
      ((.resources.limits["nvidia.com/gpu"] // .resources.requests["nvidia.com/gpu"] // "0") | tonumber)
    ] | add // 0) as $gpu |
    select($gpu > 0) |
    .spec.nodeName // empty
  ' "${tmpdir}/pods.json" | sort -u >"$gpu_consumer_nodes_file"
else
  warn "could not query Kubernetes GPU consumers"
  : >"$gpu_consumer_nodes_file"
fi
echo
echo "Slurm GPU nodes:"
slurm_cmd sinfo -N -o "%N %P %t %G %C %E" 2>/dev/null |
  awk 'NR == 1 || $2 ~ /gpu/ || $4 ~ /gpu/' |
  column -t || true

section "GPU Lane Mismatch Check"
if [[ -s "${tmpdir}/nodes.json" ]]; then
  jq -r '.items[] | select((.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0) | .metadata.name' \
    "${tmpdir}/nodes.json" | sort -u >"${tmpdir}/k8s-gpu-nodes.txt"
  jq -r '
    .items[]
    | select((.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0)
    | select((.metadata.labels["sounio.dev/inference-fabric"] // "") == "true"
        or (.metadata.annotations["sounio.dev/gpu-owner"] // "") == "inference-fabric")
    | .metadata.name
  ' "${tmpdir}/nodes.json" | sort -u >"${tmpdir}/inference-gpu-lease-nodes.txt"
else
  : >"${tmpdir}/k8s-gpu-nodes.txt"
  : >"${tmpdir}/inference-gpu-lease-nodes.txt"
fi

slurm_cmd scontrol show nodes 2>/dev/null |
  awk '
    /^NodeName=/ {
      node=$1
      sub(/^NodeName=/, "", node)
      k8s=node
      sub(/^gpuorangefs-/, "", k8s)
      sub(/^cpuops-/, "", k8s)
    }
    /^[[:space:]]+Gres=/ && $1 ~ /gpu/ {print k8s}
  ' |
  sort -u >"${tmpdir}/slurm-gpu-nodes.txt" || true

slurm_cmd sinfo -N -h -o "%N|%T|%E" 2>/dev/null |
  awk -F'|' '$2 ~ /down|drain|fail|unk|not/ || $3 ~ /Not responding|not responding/ {print "WARN: Slurm node " $1 " state=" $2 " reason=" $3}' || true

while read -r node; do
  [[ -n "$node" ]] || continue
  in_slurm=0
  in_k8s_consumer=0
  in_inference_lease=0
  grep -Fxq "$node" "${tmpdir}/slurm-gpu-nodes.txt" && in_slurm=1
  grep -Fxq "$node" "$gpu_consumer_nodes_file" && in_k8s_consumer=1
  grep -Fxq "$node" "${tmpdir}/inference-gpu-lease-nodes.txt" && in_inference_lease=1

  if ((in_slurm && (in_k8s_consumer || in_inference_lease))); then
    echo "WARN: GPU node ${node} is visible to Slurm and an inference/Kubernetes owner"
  elif ((in_inference_lease && in_k8s_consumer)); then
    echo "PASS: GPU node ${node} is owned by the inference lease and has a Kubernetes GPU consumer"
  elif ((in_inference_lease)); then
    echo "PASS: GPU node ${node} is reserved by the inference lease"
  elif ((! in_slurm && ! in_k8s_consumer)); then
    echo "WARN: GPU node ${node} has no visible owner lane"
  else
    echo "PASS: GPU node ${node} has one visible owner lane"
  fi
done <"${tmpdir}/k8s-gpu-nodes.txt"

section "Sounio Workspace"
kctl -n beagle get svc sounio-workspace sounio-workspace-control sounio-workspace-tailnet-http sounio-workspace-tailnet-ssh -o wide 2>/dev/null || warn "could not query Sounio services"
echo
kctl -n beagle get pod sounio-workspace-control-0 -o wide 2>/dev/null || warn "could not query Sounio workspace pod"

section "Storage Quick View"
df -h / /home /var/lib/vz /zfast /var/lib/orangefs-lab/client-runtime/mnt/training-orangefs 2>/dev/null || true
echo
findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null |
  awk '$1 ~ /orangefs|training-orangefs|zfast|var\/lib\/vz/ {print}' || true

section "Recent Retirement Evidence"
find /home/devsounio/.local/state/darwin-vm-retire -maxdepth 2 -type f \( -name POSTCHECK.md -o -name VERIFY.md \) 2>/dev/null |
  sort |
  tail -n 8 || true

if ((deep)); then
  section "Deep Doctors"
  doctors=(
    "${SCRIPT_DIR}/hpc-route-doctor.sh"
    "${SCRIPT_DIR}/hpc-surface-doctor.sh"
    "${SCRIPT_DIR}/slurmdbd-backend-doctor.sh"
    "${SCRIPT_DIR}/workspace-platform-doctor.sh"
    "${SCRIPT_DIR}/darwin-gpu-ownership-doctor.sh"
  )

  for doctor in "${doctors[@]}"; do
    echo
    echo "-- $(basename "$doctor") --"
    if [[ -x "$doctor" ]]; then
      "$doctor" || warn "$(basename "$doctor") reported attention"
    elif [[ -f "$doctor" ]]; then
      bash "$doctor" || warn "$(basename "$doctor") reported attention"
    else
      echo "SKIP: ${doctor} not present"
    fi
  done
fi

section "Operational Reading"
cat <<'EOF'
Green means: workspace stays interactive, stress goes to Slurm, artifacts are read from published roots.
Yellow means: run the relevant doctor and canary before editing infrastructure.
Red means: stop onboarding projects and isolate the broken lane first.
EOF
