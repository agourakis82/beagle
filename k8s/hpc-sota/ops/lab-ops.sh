#!/usr/bin/env bash
set -euo pipefail

OPS_HOST="${OPS_HOST:-root@10.100.100.2}"
LAB_OPS_MODE="${LAB_OPS_MODE:-auto}"
LAB_SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=2
)

resolve_local_kubectl() {
  local candidate
  for candidate in \
    "${KUBECTL:-}" \
    "kubectl" \
    "${HOME:-}/.local/bin/kubectl" \
    "/workspace/.home/openvscode-server/.local/bin/kubectl"
  do
    [[ -n "${candidate}" ]] || continue
    if [[ "${candidate}" == */* ]]; then
      [[ -x "${candidate}" ]] && {
        printf '%s\n' "${candidate}"
        return 0
      }
      continue
    fi
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_local_kubeconfig() {
  if [[ -n "${KUBECONFIG:-}" && -r "${KUBECONFIG}" ]]; then
    printf '%s\n' "${KUBECONFIG}"
    return 0
  fi

  if [[ -r "/etc/kubernetes/admin.conf" ]]; then
    printf '%s\n' "/etc/kubernetes/admin.conf"
    return 0
  fi

  if [[ -r "${HOME}/.kube/config" ]]; then
    printf '%s\n' "${HOME}/.kube/config"
    return 0
  fi

  return 1
}

local_kubectl_available() {
  local kubectl_bin
  kubectl_bin="$(resolve_local_kubectl)" || return 1

  local kc
  if kc="$(resolve_local_kubeconfig 2>/dev/null)"; then
    KUBECONFIG="${kc}" "${kubectl_bin}" get --raw=/version >/dev/null 2>&1
    return $?
  fi

  "${kubectl_bin}" get --raw=/version >/dev/null 2>&1
}

lab_ops_mode() {
  if [[ "${LAB_OPS_MODE}" == "local" || "${LAB_OPS_MODE}" == "ssh" ]]; then
    printf '%s\n' "${LAB_OPS_MODE}"
    return 0
  fi

  if local_kubectl_available; then
    printf '%s\n' "local"
    return 0
  fi

  printf '%s\n' "ssh"
}

lab_ops_host() {
  printf '%s\n' "$OPS_HOST"
}

lab_usage() {
  cat <<'EOF'
usage: lab-ops.sh <command>

commands:
  help                 Show this help text
  ops-host             Print the configured ops host
  ops-mode             Print the resolved execution mode (local or ssh)
  kubeconfig-path      Print the resolved kubeconfig path, when available
  preflight            Check API/SSH reachability
  status               Show Kubernetes node and Slurm pilot pod status
  slurm-status         Show Slurm controller, queue, and recent accounting
  orangefs-status      Show OrangeFS state for the current execution mode
EOF
}

lab_kubeconfig_path() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    resolve_local_kubeconfig || true
  else
    printf '%s\n' "/etc/kubernetes/admin.conf"
  fi
}

_lab_local_kubectl() {
  local kubectl_bin
  kubectl_bin="$(resolve_local_kubectl)"
  local kc
  kc="$(resolve_local_kubeconfig 2>/dev/null || true)"
  if [[ -n "${kc}" ]]; then
    KUBECONFIG="${kc}" "${kubectl_bin}" "$@"
    return 0
  fi
  "${kubectl_bin}" "$@"
}

_lab_remote() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    bash -lc "$(printf '%q ' "$@")"
    return 0
  fi
  local cmd
  printf -v cmd '%q ' "$@"
  ssh "${LAB_SSH_OPTS[@]}" "$OPS_HOST" "bash -lc $cmd"
}

_lab_remote_line() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    bash -lc "$1"
    return 0
  fi
  local line="$1"
  ssh "${LAB_SSH_OPTS[@]}" "$OPS_HOST" "bash -lc $(printf '%q' "$line")"
}

lab_try_host_ssh() {
  local host="$1"
  shift
  if ssh "${LAB_SSH_OPTS[@]}" "${host}" "$@" 2>/dev/null; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo -n ssh "${LAB_SSH_OPTS[@]}" "${host}" "$@" 2>/dev/null && return 0
  fi
  return 1
}

lab_preflight() {
  echo "== ops host =="
  echo "$OPS_HOST"
  echo
  echo "== ssh reachability =="
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    echo "PASS: local kubectl mode"
  elif ssh "${LAB_SSH_OPTS[@]}" "$OPS_HOST" true 2>/dev/null; then
    echo "PASS: ssh to $OPS_HOST"
  else
    echo "WARN: cannot reach $OPS_HOST with non-interactive ssh"
    echo "      lab-ops.sh expects key-based ssh to OPS_HOST"
    echo "      if you are on the control-plane host itself, prefer ./ops/hpc-bootstrap.sh"
    return 1
  fi
  echo
  echo "== kubernetes api =="
  lab_kctl get nodes -o wide
}

lab_kctl() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    _lab_local_kubectl "$@"
    return 0
  fi
  _lab_remote KUBECONFIG="$(lab_kubeconfig_path)" kubectl "$@"
}

lab_login_pod() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    _lab_local_kubectl -n slurm-pilot get pod -o name | grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2
    return 0
  fi
  _lab_remote "KUBECONFIG=$(lab_kubeconfig_path) kubectl -n slurm-pilot get pod -o name | grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2"
}

lab_slurm_exec() {
  local pod
  pod="$(lab_login_pod)"
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    _lab_local_kubectl -n slurm-pilot exec "$pod" -- "$@"
    return 0
  fi
  _lab_remote KUBECONFIG="$(lab_kubeconfig_path)" kubectl -n slurm-pilot exec "$pod" -- "$@"
}

lab_copy_and_run() {
  local local_script="$1"
  local remote_path="${2:-/tmp/$(basename "$local_script")}"
  if [[ ! -f "$local_script" ]]; then
    echo "missing local script: $local_script" >&2
    return 2
  fi
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    bash "$local_script"
    return 0
  fi
  scp "${LAB_SSH_OPTS[@]}" "$local_script" "$OPS_HOST:$remote_path" >/dev/null
  _lab_remote bash "$remote_path"
}

lab_orangefs_backend_status_local() {
  local server01_path="/zfast/orangefs-lab"
  local server02_host="root@10.100.100.3"
  local server02_output=""
  local thin_pool_pct=""

  echo "== OrangeFS server backends =="
  echo "-- server01 backend (t560-proxmox) --"
  if [[ -d "${server01_path}" ]]; then
    df -h "${server01_path}" 2>/dev/null || true
  else
    echo "path not present: ${server01_path}"
  fi
  echo

  echo "-- server02 backend (5860-proxmox) --"
  if server02_output="$(lab_try_host_ssh "${server02_host}" \
    "bash -lc 'df -h /srv/orangefs-server02-store /var/lib/orangefs-lab 2>/dev/null; echo; echo \"LV,LSize,Data%,Meta%\"; lvs --noheadings --units g --nosuffix --separator , -o lv_name,lv_size,data_percent,metadata_percent pve/data pve/orangefs_server02_store 2>/dev/null'")"
  then
    printf '%s\n' "${server02_output}"
    thin_pool_pct="$(printf '%s\n' "${server02_output}" | awk -F, '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)} $1 == "data" {print $3; exit}')"
    if [[ -n "${thin_pool_pct}" ]] && awk -v pct="${thin_pool_pct}" 'BEGIN { exit !((pct + 0) >= 95) }'; then
      echo
      echo "WARN: 5860 local-lvm thin pool is above 95% full."
      echo "      The OrangeFS namespace can look healthy on workers while future growth is still capped by server02 backend risk."
    fi
  else
    echo "server02 backend details unavailable from this shell"
    echo "run from t560 with host-level sudo/ssh access for the full backend picture"
  fi
  echo
  echo "== Capacity interpretation =="
  echo "OrangeFS export size follows the smallest effective server backing store, not the sum of all raw disks in the lab."
  echo "A healthy worker-side df does not mean the data plane is genuinely multi-terabyte yet."
}

lab_orangefs_status_local() {
  local pods pod pod_name node_name
  echo "== OrangeFS mounts on gpuorangefs workers =="
  pods="$(lab_kctl -n slurm-pilot get pod -o name | grep 'pod/slurm-pilot-worker-gpuorangefs' || true)"
  if [[ -z "${pods}" ]]; then
    echo "no gpuorangefs worker pods found" >&2
    return 1
  fi

  while IFS= read -r pod; do
    [[ -n "${pod}" ]] || continue
    pod_name="${pod#pod/}"
    node_name="$(lab_kctl -n slurm-pilot get pod "${pod_name}" -o jsonpath='{.spec.nodeName}')"
    echo "-- ${pod_name} (${node_name}) --"
    lab_kctl -n slurm-pilot exec "${pod_name}" -c slurmd -- sh -lc '
      hostname
      mount | grep pvfs2 || true
      df -h /orangefs/training 2>/dev/null || df -h /orangefs 2>/dev/null || true
    '
    echo
  done <<< "${pods}"

  lab_orangefs_backend_status_local
}

lab_status() {
  echo "== Kubernetes nodes =="
  lab_kctl get nodes -o wide
  echo
  echo "== Slurm pilot pods =="
  lab_kctl -n slurm-pilot get pods -o wide
}

lab_slurm_status() {
  echo "== scontrol ping =="
  lab_slurm_exec scontrol ping
  echo
  echo "== sinfo =="
  lab_slurm_exec sinfo
  echo
  echo "== recent sacct =="
  lab_slurm_exec sacct -S now-1day --format=JobID,JobName,Partition,Account,QOS,State,ExitCode,Start,End,NodeList
}

lab_orangefs_status() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    lab_orangefs_status_local
    return 0
  fi
  echo "== OrangeFS runtime on t560 =="
  _lab_remote systemctl status orangefs-client-runtime.service --no-pager --lines=0
  echo
  echo "== OrangeFS mount =="
  _lab_remote_line "mount | grep pvfs2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-help}"
  shift || true
  case "${cmd}" in
    help|-h|--help)
      lab_usage
      ;;
    ops-host)
      lab_ops_host "$@"
      ;;
    ops-mode)
      lab_ops_mode "$@"
      ;;
    kubeconfig-path)
      lab_kubeconfig_path "$@"
      ;;
    preflight)
      lab_preflight "$@"
      ;;
    status|lab_status)
      lab_status "$@"
      ;;
    slurm-status|lab_slurm_status)
      lab_slurm_status "$@"
      ;;
    orangefs-status|lab_orangefs_status)
      lab_orangefs_status "$@"
      ;;
    *)
      echo "unknown command: ${cmd}" >&2
      echo >&2
      lab_usage >&2
      exit 2
      ;;
  esac
fi
