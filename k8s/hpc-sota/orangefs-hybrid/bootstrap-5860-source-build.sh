#!/usr/bin/env bash
set -euo pipefail

host="${ORANGEFS_HOST:-root@10.100.100.3}"
pass="${ORANGEFS_PASS:?defina ORANGEFS_PASS no ambiente (nunca no script); prefira chave SSH}"
base="${ORANGEFS_BASE:-/var/lib/orangefs-lab}"
repo_url="${ORANGEFS_REPO_URL:-https://github.com/waltligon/orangefs.git}"

ssh_cmd=(
  sshpass -p "$pass"
  ssh
  -o StrictHostKeyChecking=no
  "$host"
)

"${ssh_cmd[@]}" "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  proxmox-headers-\$(uname -r) \
  autoconf \
  autoconf-archive \
  automake \
  libtool \
  bison \
  flex \
  pkg-config \
  git \
  gcc \
  make \
  python3 \
  liblmdb-dev \
  libssl-dev \
  libxml2-dev \
  zlib1g-dev

install -d -m 0755 '$base'

if [ ! -d '$base/orangefs-src/.git' ]; then
  git clone --depth 1 '$repo_url' '$base/orangefs-src'
else
  git -C '$base/orangefs-src' pull --ff-only
fi

git -C '$base/orangefs-src' rev-parse HEAD > '$base/orangefs-src/.current-head'
echo '== source head =='
cat '$base/orangefs-src/.current-head'
echo '== workspace =='
df -h '$base'
"
