#!/usr/bin/env bash
set -euo pipefail

OPS_HOST="${OPS_HOST:-root@10.100.100.2}"
LAB_OPS_MODE="${LAB_OPS_MODE:-auto}"
LAB_SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=2
)

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

lab_ops_mode() {
  if [[ "${LAB_OPS_MODE}" == "local" || "${LAB_OPS_MODE}" == "ssh" ]]; then
    printf '%s\n' "${LAB_OPS_MODE}"
    return 0
  fi

  local kc
  if kc="$(resolve_local_kubeconfig 2>/dev/null)" && KUBECONFIG="${kc}" kubectl version --client >/dev/null 2>&1; then
    printf '%s\n' "local"
    return 0
  fi

  printf '%s\n' "ssh"
}

lab_ops_host() {
  printf '%s\n' "$OPS_HOST"
}

lab_kubeconfig_path() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    resolve_local_kubeconfig
  else
    printf '%s\n' "/etc/kubernetes/admin.conf"
  fi
}

_lab_remote() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    local kc
    kc="$(resolve_local_kubeconfig)"
    KUBECONFIG="${kc}" bash -lc "$(printf '%q ' "$@")"
    return 0
  fi
  local cmd
  printf -v cmd '%q ' "$@"
  ssh "${LAB_SSH_OPTS[@]}" "$OPS_HOST" "bash -lc $cmd"
}

_lab_remote_line() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    local kc
    kc="$(resolve_local_kubeconfig)"
    KUBECONFIG="${kc}" bash -lc "$1"
    return 0
  fi
  local line="$1"
  ssh "${LAB_SSH_OPTS[@]}" "$OPS_HOST" "bash -lc $(printf '%q' "$line")"
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
    local kc
    kc="$(lab_kubeconfig_path)"
    KUBECONFIG="${kc}" kubectl "$@"
    return 0
  fi
  _lab_remote KUBECONFIG="$(lab_kubeconfig_path)" kubectl "$@"
}

lab_login_pod() {
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    local kc
    kc="$(lab_kubeconfig_path)"
    KUBECONFIG="${kc}" kubectl -n slurm-pilot get pod -o name | grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2
    return 0
  fi
  _lab_remote "KUBECONFIG=$(lab_kubeconfig_path) kubectl -n slurm-pilot get pod -o name | grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2"
}

lab_slurm_exec() {
  local pod
  pod="$(lab_login_pod)"
  if [[ "$(lab_ops_mode)" == "local" ]]; then
    local kc
    kc="$(lab_kubeconfig_path)"
    KUBECONFIG="${kc}" kubectl -n slurm-pilot exec "$pod" -- "$@"
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
  echo "== OrangeFS runtime on t560 =="
  _lab_remote systemctl status orangefs-client-runtime.service --no-pager --lines=0
  echo
  echo "== OrangeFS mount =="
  _lab_remote_line "mount | grep pvfs2"
}
