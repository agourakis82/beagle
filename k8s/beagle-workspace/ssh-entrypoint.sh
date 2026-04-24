#!/usr/bin/env bash
set -euo pipefail

SSH_USER="${BEAGLE_WORKSPACE_SSH_USER:-openvscode-server}"
SSH_PORT="${BEAGLE_WORKSPACE_SSH_PORT:-2222}"
WORKSPACE_ROOT="${BEAGLE_WORKSPACE_ROOT:-/workspace/beagle}"
PROJECT_SLUG="${PROJECT_SLUG:-$(basename "${WORKSPACE_ROOT}")}"
PROJECT_TMUX_SESSION="${PROJECT_TMUX_SESSION:-${PROJECT_SLUG}-dev}"
PROJECT_AUTO_TMUX_ATTACH="${PROJECT_AUTO_TMUX_ATTACH:-false}"
AUTHORIZED_KEYS_FILE="${BEAGLE_WORKSPACE_SSH_AUTHORIZED_KEYS_FILE:-/var/run/beagle-workspace-ssh/authorized_keys}"
HOST_KEYS_DIR="${BEAGLE_WORKSPACE_SSH_HOST_KEYS_DIR:-/workspace/.beagle/ssh-host-keys}"
USER_HOME="$(getent passwd "${SSH_USER}" | cut -d: -f6)"
DEFAULT_PERSISTENT_HOME="/workspace/.home/${SSH_USER}"
PERSISTENT_HOME="${BEAGLE_WORKSPACE_PERSISTENT_HOME:-}"
if [[ -z "${PERSISTENT_HOME}" ]]; then
  if [[ -d "/workspace/.home" || -e "/workspace/.home/${SSH_USER}" ]]; then
    PERSISTENT_HOME="${DEFAULT_PERSISTENT_HOME}"
  else
    PERSISTENT_HOME="${USER_HOME}"
  fi
fi
GIT_USER_NAME="${BEAGLE_GIT_USER_NAME:-}"
GIT_USER_EMAIL="${BEAGLE_GIT_USER_EMAIL:-}"
GIT_CREDENTIAL_HELPER="${BEAGLE_GIT_CREDENTIAL_HELPER:-!/usr/bin/gh auth git-credential}"
HELPERS_FILE="${PERSISTENT_HOME}/.beagle_shell_helpers.sh"
BASHRC_FILE="${PERSISTENT_HOME}/.bashrc"
BASH_PROFILE_FILE="${PERSISTENT_HOME}/.bash_profile"
PROFILE_FILE="${PERSISTENT_HOME}/.profile"
ZSHENV_FILE="${PERSISTENT_HOME}/.zshenv"
ZSHRC_FILE="${PERSISTENT_HOME}/.zshrc"
TMUX_CONF_FILE="${PERSISTENT_HOME}/.tmux.conf"
TMUX_SOCKET_DIR="${PERSISTENT_HOME}/.tmux"
SLURM_RUNTIME_DIR="${BEAGLE_WORKSPACE_SLURM_RUNTIME_DIR:-/run/slurm}"
SLURM_CONF_FILE="${BEAGLE_WORKSPACE_SLURM_CONF:-${SLURM_RUNTIME_DIR}/conf/slurm.conf}"
SLURM_CONF_SERVER="${BEAGLE_WORKSPACE_SLURM_CONF_SERVER:-slurm-pilot-controller.slurm-pilot:6817}"
SLURM_AUTH_KEY_FILE="${BEAGLE_WORKSPACE_SLURM_AUTH_KEY_FILE:-/etc/slurm/slurm.key}"
SLURM_SACK_SOCKET="${BEAGLE_WORKSPACE_SLURM_SACK_SOCKET:-${SLURM_RUNTIME_DIR}/sack.socket}"
SLURM_RUNTIME_KEY_FILE="${BEAGLE_WORKSPACE_SLURM_RUNTIME_KEY_FILE:-${SLURM_RUNTIME_DIR}/slurm.key}"
SACKD_BIN="${BEAGLE_WORKSPACE_SACKD_BIN:-/usr/sbin/sackd}"
HELPER_BIN_DIR="${PERSISTENT_HOME}/bin"
PUSH_CHECK_SCRIPT="${HELPER_BIN_DIR}/project-gh-push-check"
VSCODE_SERVER_DIR="${PERSISTENT_HOME}/.vscode-server"
HEALTH_DIR="/workspace/.beagle/health"
SSH_READY_FILE="${HEALTH_DIR}/ssh-ready"
AUTHORIZED_KEYS_WAIT_INTERVAL="${AUTHORIZED_KEYS_WAIT_INTERVAL:-5}"
HELPERS_BLOCK_START="# >>> beagle managed shell helpers >>>"
HELPERS_BLOCK_END="# <<< beagle managed shell helpers <<<"
TMUX_BLOCK_START="# >>> beagle managed tmux autoattach >>>"
TMUX_BLOCK_END="# <<< beagle managed tmux autoattach <<<"

if [[ -z "${USER_HOME}" ]]; then
  echo "[FAIL] unable to resolve home directory for ${SSH_USER}" >&2
  exit 1
fi

chown_if_present() {
  for path in "$@"; do
    [[ -e "${path}" || -L "${path}" ]] || continue
    chown -R "${SSH_USER}:${SSH_USER}" "${path}" 2>/dev/null || true
  done
}

remove_managed_block() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v start="${start_marker}" -v end="${end_marker}" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
  ' "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

remove_legacy_tmux_autostart_block() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { skip=0 }
    skip == 0 && ($0 ~ /^if \[ -n "\$\{PS1:-\}" \] .*PROJECT_AUTO_TMUX_ATTACH.*$/ || $0 ~ /^if \[ -t 0 \] && \[ -t 1 \] && \[ -n "\$\{PS1:-\}" \] .*PROJECT_AUTO_TMUX_ATTACH.*$/) {
      skip=1
      next
    }
    skip == 1 {
      if ($0 ~ /^fi$/) {
        skip=0
      }
      next
    }
    { print }
  ' "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

remove_exact_line() {
  local file="$1"
  local needle="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v needle="${needle}" '$0 != needle { print }' "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

wait_for_authorized_keys() {
  local warned=0
  while [[ ! -s "${AUTHORIZED_KEYS_FILE}" ]]; do
    if (( warned == 0 )); then
      echo "[WARN] waiting for authorized_keys at ${AUTHORIZED_KEYS_FILE}; native attach will start once the secret is mounted" >&2
      warned=1
    fi
    sleep "${AUTHORIZED_KEYS_WAIT_INTERVAL}"
  done
}

start_sackd() {
  local sackd_log="/tmp/sackd.log"
  local sackd_cmd

  if [[ ! -x "${SACKD_BIN}" ]]; then
    echo "[WARN] sackd is not installed in the workspace SSH image; native Slurm configless mode is unavailable" >&2
    return 0
  fi

  if [[ ! -r "${SLURM_AUTH_KEY_FILE}" ]]; then
    echo "[FAIL] missing readable Slurm auth key at ${SLURM_AUTH_KEY_FILE}" >&2
    return 1
  fi

  mkdir -p "${SLURM_RUNTIME_DIR}"
  if id slurm >/dev/null 2>&1; then
    chown slurm:slurm "${SLURM_RUNTIME_DIR}" 2>/dev/null || true
  fi
  chmod 0755 "${SLURM_RUNTIME_DIR}" 2>/dev/null || true

  if pgrep -x sackd >/dev/null 2>&1 && [[ -S "${SLURM_SACK_SOCKET}" && -r "${SLURM_CONF_FILE}" ]]; then
    return 0
  fi
  if pgrep -x sackd >/dev/null 2>&1; then
    pkill -x sackd >/dev/null 2>&1 || true
    sleep 1
  fi

  rm -f "${SLURM_SACK_SOCKET}" "${sackd_log}"
  cp "${SLURM_AUTH_KEY_FILE}" "${SLURM_RUNTIME_KEY_FILE}"
  if id slurm >/dev/null 2>&1; then
    chown slurm:slurm "${SLURM_RUNTIME_KEY_FILE}" 2>/dev/null || true
  fi
  chmod 0600 "${SLURM_RUNTIME_KEY_FILE}" 2>/dev/null || true

  # This sidecar is not supervised by systemd, so run sackd in the
  # foreground and background it from the shell instead.
  sackd_cmd="exec ${SACKD_BIN} -D --conf-server '${SLURM_CONF_SERVER}' --key-file '${SLURM_RUNTIME_KEY_FILE}'"
  if id slurm >/dev/null 2>&1; then
    su -s /bin/sh slurm -c "${sackd_cmd}" >"${sackd_log}" 2>&1 &
  else
    bash -lc "${sackd_cmd}" >"${sackd_log}" 2>&1 &
  fi

  for _ in $(seq 1 30); do
    if [[ -S "${SLURM_SACK_SOCKET}" && -r "${SLURM_CONF_FILE}" ]]; then
      return 0
    fi
    sleep 1
  done

  echo "[FAIL] sackd did not become ready for native Slurm access" >&2
  pgrep -a -x sackd >&2 || true
  if [[ -f "${sackd_log}" ]]; then
    tail -n 50 "${sackd_log}" >&2 || true
  fi
  return 1
}

# Dropbear rejects public-key auth for locked accounts. We explicitly unlock the
# workspace user here while still keeping password auth disabled via `-s`.
passwd -d "${SSH_USER}" >/dev/null 2>&1 || true

mkdir -p "${HOST_KEYS_DIR}" "${USER_HOME}/.ssh" "${WORKSPACE_ROOT}" "${HEALTH_DIR}"
mkdir -p "${PERSISTENT_HOME}" "${PERSISTENT_HOME}/.config" "${PERSISTENT_HOME}/.config/gh"
mkdir -p "${HELPER_BIN_DIR}"
mkdir -p "${PERSISTENT_HOME}/.local"
mkdir -p "${TMUX_SOCKET_DIR}"
mkdir -p "${VSCODE_SERVER_DIR}"
rm -f "${SSH_READY_FILE}"
chmod 0700 "${USER_HOME}/.ssh"
chmod 0700 "${TMUX_SOCKET_DIR}" 2>/dev/null || true
find "${TMUX_SOCKET_DIR}" -mindepth 1 -maxdepth 1 -type d -name 'tmux-*' -exec chmod 0700 {} + 2>/dev/null || true
chown_if_present "${USER_HOME}/.ssh" "${HOST_KEYS_DIR}" "${WORKSPACE_ROOT}" "${HEALTH_DIR}"
chown_if_present \
  "${PERSISTENT_HOME}" \
  "${PERSISTENT_HOME}/.config" \
  "${PERSISTENT_HOME}/.config/gh" \
  "${HELPER_BIN_DIR}" \
  "${PERSISTENT_HOME}/.local" \
  "${TMUX_SOCKET_DIR}" \
  "${VSCODE_SERVER_DIR}"

wait_for_authorized_keys

cp "${AUTHORIZED_KEYS_FILE}" "${USER_HOME}/.ssh/authorized_keys"
chmod 0600 "${USER_HOME}/.ssh/authorized_keys"
chown "${SSH_USER}:${SSH_USER}" "${USER_HOME}/.ssh/authorized_keys"

if [[ ! -f "${HOST_KEYS_DIR}/dropbear_ed25519_host_key" ]]; then
  dropbearkey -t ed25519 -f "${HOST_KEYS_DIR}/dropbear_ed25519_host_key" >/dev/null 2>&1
fi
if [[ ! -f "${HOST_KEYS_DIR}/dropbear_rsa_host_key" ]]; then
  dropbearkey -t rsa -s 4096 -f "${HOST_KEYS_DIR}/dropbear_rsa_host_key" >/dev/null 2>&1
fi
chmod 0600 \
  "${HOST_KEYS_DIR}/dropbear_ed25519_host_key" \
  "${HOST_KEYS_DIR}/dropbear_rsa_host_key"
chown_if_present "${USER_HOME}" "${WORKSPACE_ROOT}" \
  "${HOST_KEYS_DIR}/dropbear_ed25519_host_key" \
  "${HOST_KEYS_DIR}/dropbear_rsa_host_key"

if [[ "${PERSISTENT_HOME}" != "${USER_HOME}" ]]; then
  mkdir -p "${USER_HOME}/.config"
  rm -rf "${USER_HOME}/.config/gh"
  ln -sfn "${PERSISTENT_HOME}/.config/gh" "${USER_HOME}/.config/gh"
  ln -sfn "${PERSISTENT_HOME}/.local" "${USER_HOME}/.local"
  rm -rf "${USER_HOME}/.vscode-server"
  ln -sfn "${VSCODE_SERVER_DIR}" "${USER_HOME}/.vscode-server"
fi

cat > "${HELPERS_FILE}" <<EOF
export PATH="\$HOME/bin:\$PATH"
export PROJECT_WORKSPACE_ROOT="${WORKSPACE_ROOT}"
export PROJECT_TMUX_SESSION="${PROJECT_TMUX_SESSION}"
export PROJECT_AUTO_TMUX_ATTACH="${PROJECT_AUTO_TMUX_ATTACH}"
export TMUX_TMPDIR="${TMUX_SOCKET_DIR}"
export BEAGLE_HPC_LAB_ROOT="/workspace/beagle/k8s/hpc-sota"
export SLURM_CONF="${SLURM_CONF_FILE}"
export BEAGLE_WORKSPACE_SLURM_CONF_SERVER="${SLURM_CONF_SERVER}"

wrepo() { cd "${WORKSPACE_ROOT}"; }
wst() { git -C "${WORKSPACE_ROOT}" status -sb "\$@"; }
wsync() { git -C "${WORKSPACE_ROOT}" pull --ff-only "\$@"; }
wbranches() { git -C "${WORKSPACE_ROOT}" branch -vv "\$@"; }
wlog() { git -C "${WORKSPACE_ROOT}" log --oneline --decorate --graph -20 "\$@"; }
ghst() { gh auth status "\$@"; }
wpready() {
  gh auth status &&
  git -C "${WORKSPACE_ROOT}" remote -v &&
  git -C "${WORKSPACE_ROOT}" status -sb
}
gpushcheck() { "$HOME/bin/project-gh-push-check" "${WORKSPACE_ROOT}" "\$@"; }
tmx() {
  _tmux_uid="\$(id -u)"
  mkdir -p "\${TMUX_TMPDIR}/tmux-\${_tmux_uid}"
  chmod 700 "\${TMUX_TMPDIR}" "\${TMUX_TMPDIR}/tmux-\${_tmux_uid}" 2>/dev/null || true
  umask 077
  tmux new -As "${PROJECT_TMUX_SESSION}" -c "${WORKSPACE_ROOT}"
}
ensure_beagle_lab_ops() {
  _lab_ops_file="\${BEAGLE_HPC_LAB_ROOT}/ops/lab-ops.sh"
  if [ ! -f "\${_lab_ops_file}" ]; then
    echo "[warn] Beagle HPC control plane is not synced into the habitat at \${BEAGLE_HPC_LAB_ROOT}" >&2
    echo "[warn] run: /home/devsounio/projects/sounio/sounio-maintain.sh sync-control-plane" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "\${_lab_ops_file}"
}
slurm_native_ready() {
  slurm_native_client_compatible &&
  [ -S "/run/slurm/sack.socket" ] &&
  [ -r "\${SLURM_CONF:-/run/slurm/conf/slurm.conf}" ]
}
slurm_native_client_compatible() {
  _slurm_client_version=""
  if command -v dpkg-query >/dev/null 2>&1; then
    _slurm_client_version="\$(dpkg-query -W -f='\${Version}\n' slurm-smd-client 2>/dev/null || dpkg-query -W -f='\${Version}\n' slurm-client 2>/dev/null || true)"
  fi
  case "\${_slurm_client_version}" in
    25.*)
      return 0
      ;;
  esac
  return 1
}
_lab_slurm_bridge() {
  ensure_beagle_lab_ops || return 1
  lab_slurm_exec "\$@"
}
slurm_native_or_bridge() {
  _slurm_cmd="\$1"
  shift
  if command -v "\${_slurm_cmd}" >/dev/null 2>&1 && slurm_native_ready; then
    command "\${_slurm_cmd}" "\$@"
    return \$?
  fi
  _lab_slurm_bridge "\${_slurm_cmd}" "\$@"
}
sinfo() { slurm_native_or_bridge sinfo "\$@"; }
squeue() { slurm_native_or_bridge squeue "\$@"; }
sacct() { slurm_native_or_bridge sacct "\$@"; }
sacctmgr() { slurm_native_or_bridge sacctmgr "\$@"; }
sbatch() { slurm_native_or_bridge sbatch "\$@"; }
scancel() { slurm_native_or_bridge scancel "\$@"; }
scontrol() { slurm_native_or_bridge scontrol "\$@"; }
srun() {
  if command -v srun >/dev/null 2>&1 && slurm_native_ready; then
    command srun "\$@"
    return \$?
  fi
  ensure_beagle_lab_ops || return 1
  _slurm_pod="\$(lab_login_pod)" || return 1
  if [ -t 0 ] && [ -t 1 ]; then
    lab_kctl -n slurm-pilot exec -it "\${_slurm_pod}" -- srun "\$@"
    return \$?
  fi
  lab_kctl -n slurm-pilot exec "\${_slurm_pod}" -- srun "\$@"
}
EOF

cat > "${PUSH_CHECK_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-${PROJECT_WORKSPACE_ROOT:-$PWD}}"
BRANCH_NAME="${2:-chore/github-push-check-$(date +%m%d%H%M%S)}"

gh auth status >/dev/null
git -C "${REPO_ROOT}" switch -c "${BRANCH_NAME}"
git -C "${REPO_ROOT}" push -u origin "${BRANCH_NAME}"

echo "[OK] push check branch created and pushed: ${BRANCH_NAME}"
EOF

chmod 0755 "${PUSH_CHECK_SCRIPT}"
chown "${SSH_USER}:${SSH_USER}" "${HELPERS_FILE}" "${PUSH_CHECK_SCRIPT}"

if [[ ! -f "${BASHRC_FILE}" ]]; then
  cat > "${BASHRC_FILE}" <<EOF
# Persistent shell config for the ${PROJECT_SLUG} cluster workspace.
EOF
fi

cat > "${PROFILE_FILE}" <<'EOF'
# Beagle-managed login profile.
# Keep plain sh login shells POSIX-safe and only source .bashrc from bash.
export PATH="$HOME/bin:$HOME/.elan/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
EOF

if [[ ! -f "${ZSHENV_FILE}" ]]; then
  cat > "${ZSHENV_FILE}" <<'EOF'
export PATH="$HOME/.local/node-v20.20.2-linux-x64/bin:$HOME/.local/bin:$PATH"
EOF
fi

if [[ ! -f "${ZSHRC_FILE}" ]]; then
  cat > "${ZSHRC_FILE}" <<'EOF'
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
EOF
fi

if [[ ! -f "${TMUX_CONF_FILE}" ]]; then
  cat > "${TMUX_CONF_FILE}" <<'EOF'
set -g mouse on
set -g history-limit 100000
setw -g mode-keys vi
set -g status-keys vi
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
bind r source-file ~/.tmux.conf \; display-message "tmux config reloaded"
EOF
fi

remove_managed_block "${BASHRC_FILE}" "${HELPERS_BLOCK_START}" "${HELPERS_BLOCK_END}"
remove_managed_block "${BASHRC_FILE}" "${TMUX_BLOCK_START}" "${TMUX_BLOCK_END}"
remove_legacy_tmux_autostart_block "${BASHRC_FILE}"
remove_exact_line "${BASHRC_FILE}" "alias tmx='tmux new -As main'"
remove_exact_line "${BASHRC_FILE}" 'export TMUX_TMPDIR=/workspace/.home/openvscode-server/.tmux'

cat >> "${BASHRC_FILE}" <<EOF

${HELPERS_BLOCK_START}
# Beagle-managed shell helpers for the ${PROJECT_SLUG} workspace.
if [ -f "\$HOME/.beagle_shell_helpers.sh" ]; then
  . "\$HOME/.beagle_shell_helpers.sh"
fi
${HELPERS_BLOCK_END}

${TMUX_BLOCK_START}
if [ -t 0 ] && [ -t 1 ] && [ -n "\${PS1:-}" ] && [ -z "\${TMUX:-}" ] && [ "\${PROJECT_AUTO_TMUX_ATTACH:-false}" = "true" ] && command -v tmux >/dev/null 2>&1; then
  exec tmux new -As "\${PROJECT_TMUX_SESSION:-main}" -c "\${PROJECT_WORKSPACE_ROOT:-\$PWD}"
fi
${TMUX_BLOCK_END}
EOF

cat > "${BASH_PROFILE_FILE}" <<'EOF'
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
EOF

chown "${SSH_USER}:${SSH_USER}" "${BASHRC_FILE}" "${BASH_PROFILE_FILE}"
chown "${SSH_USER}:${SSH_USER}" "${PROFILE_FILE}" "${ZSHENV_FILE}" "${ZSHRC_FILE}" "${TMUX_CONF_FILE}" "${TMUX_SOCKET_DIR}"

if [[ "${PERSISTENT_HOME}" != "${USER_HOME}" ]]; then
  ln -sfn "${BASHRC_FILE}" "${USER_HOME}/.bashrc"
  ln -sfn "${BASH_PROFILE_FILE}" "${USER_HOME}/.bash_profile"
  ln -sfn "${HELPERS_FILE}" "${USER_HOME}/.beagle_shell_helpers.sh"
  ln -sfn "${PROFILE_FILE}" "${USER_HOME}/.profile"
  ln -sfn "${ZSHENV_FILE}" "${USER_HOME}/.zshenv"
  ln -sfn "${ZSHRC_FILE}" "${USER_HOME}/.zshrc"
  ln -sfn "${TMUX_CONF_FILE}" "${USER_HOME}/.tmux.conf"
  ln -sfn "${HELPER_BIN_DIR}" "${USER_HOME}/bin"
fi

if [[ -n "${GIT_USER_NAME}" && -n "${GIT_USER_EMAIL}" ]]; then
  GIT_CONFIG_FILE="${PERSISTENT_HOME}/.gitconfig"
  touch "${GIT_CONFIG_FILE}"
  git config --file "${GIT_CONFIG_FILE}" user.name "${GIT_USER_NAME}"
  git config --file "${GIT_CONFIG_FILE}" user.email "${GIT_USER_EMAIL}"
  git config --file "${GIT_CONFIG_FILE}" init.defaultBranch main
  git config --file "${GIT_CONFIG_FILE}" pull.rebase false
  git config --file "${GIT_CONFIG_FILE}" --add safe.directory "${WORKSPACE_ROOT}"
  git config --file "${GIT_CONFIG_FILE}" --replace-all credential."https://github.com".helper "${GIT_CREDENTIAL_HELPER}"
  git config --file "${GIT_CONFIG_FILE}" --replace-all credential."https://gist.github.com".helper "${GIT_CREDENTIAL_HELPER}"
  chown "${SSH_USER}:${SSH_USER}" "${GIT_CONFIG_FILE}"
  if [[ "${PERSISTENT_HOME}" != "${USER_HOME}" ]]; then
    ln -sfn "${GIT_CONFIG_FILE}" "${USER_HOME}/.gitconfig"
  fi
fi

# We intentionally do not pre-create the tmux session during SSH container
# bootstrap. With a shared TMUX socket under the persistent home, the first
# interactive IDE or SSH client can create/attach the session safely via the
# auto-attach shell path without forcing tmux to open a terminal here.

start_sackd

if [[ ! -x /usr/lib/sftp-server && -x /usr/lib/openssh/sftp-server ]]; then
  ln -sf /usr/lib/openssh/sftp-server /usr/lib/sftp-server
fi

printf 'ready\n' > "${SSH_READY_FILE}"
exec /usr/sbin/dropbear \
  -F \
  -E \
  -s \
  -w \
  -p "${SSH_PORT}" \
  -r "${HOST_KEYS_DIR}/dropbear_ed25519_host_key" \
  -r "${HOST_KEYS_DIR}/dropbear_rsa_host_key"
