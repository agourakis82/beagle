#!/usr/bin/env bash
set -euo pipefail

if (($#)); then
  NODES=("$@")
else
  NODES=(t560-proxmox r770-proxmox r740-proxmox 5860-proxmox)
fi
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${SSHPASS:-}" ]]; then
  SSH_CMD=(sshpass -e ssh -o StrictHostKeyChecking=no)
  SCP_CMD=(sshpass -e scp -q -o StrictHostKeyChecking=no)
else
  SSH_CMD=(ssh -o StrictHostKeyChecking=no)
  SCP_CMD=(scp -q -o StrictHostKeyChecking=no)
fi

for node in "${NODES[@]}"; do
  echo "[INFO] configuring registry mirrors on ${node}"
  "${SCP_CMD[@]}" \
    "${SOURCE_DIR}/containerd-dockerhub-mirror-hosts.toml" \
    "${SOURCE_DIR}/containerd-ghcr-mirror-hosts.toml" \
    "${SOURCE_DIR}/containerd-registry-k8s-mirror-hosts.toml" \
    "root@${node}:/tmp/"
  "${SSH_CMD[@]}" "root@${node}" 'bash -s' <<'EOF'
set -euo pipefail
python3 - <<'PY'
from pathlib import Path

path = Path("/etc/containerd/config.toml")
text = path.read_text()
needle = '[plugins."io.containerd.grpc.v1.cri".registry]'
config_line = '    config_path = "/etc/containerd/certs.d"'

if 'config_path = "/etc/containerd/certs.d"' not in text:
    if 'config_path = ""' in text:
        text = text.replace('config_path = ""', 'config_path = "/etc/containerd/certs.d"')
    elif needle in text:
        text = text.replace(needle, needle + "\n" + config_line, 1)
    else:
        text = text.rstrip() + "\n\n" + needle + "\n" + config_line + "\n"
    path.write_text(text)

conf_dir = Path("/etc/containerd/conf.d")
if conf_dir.exists():
    for cfg in conf_dir.glob("*.toml"):
        text = cfg.read_text()
        if 'config_path = "/etc/containerd/certs.d"' in text:
            continue
        if "version = 3" in text:
            section = '[plugins."io.containerd.cri.v1.images".registry]'
            line = '  config_path = "/etc/containerd/certs.d"'
        else:
            section = '[plugins."io.containerd.grpc.v1.cri".registry]'
            line = '  config_path = "/etc/containerd/certs.d"'
        if 'config_path = ""' in text:
            text = text.replace('config_path = ""', 'config_path = "/etc/containerd/certs.d"')
        elif section in text:
            text = text.replace(section, section + "\n" + line, 1)
        else:
            text = text.rstrip() + "\n\n" + section + "\n" + line + "\n"
        cfg.write_text(text)
PY

mkdir -p /etc/containerd/certs.d/docker.io /etc/containerd/certs.d/ghcr.io /etc/containerd/certs.d/registry.k8s.io
install -m 0644 /tmp/containerd-dockerhub-mirror-hosts.toml /etc/containerd/certs.d/docker.io/hosts.toml
install -m 0644 /tmp/containerd-ghcr-mirror-hosts.toml /etc/containerd/certs.d/ghcr.io/hosts.toml
install -m 0644 /tmp/containerd-registry-k8s-mirror-hosts.toml /etc/containerd/certs.d/registry.k8s.io/hosts.toml
systemctl restart containerd
sleep 2
systemctl is-active containerd >/dev/null
crictl info 2>/dev/null | grep -A3 -m1 registry || true
EOF
done
