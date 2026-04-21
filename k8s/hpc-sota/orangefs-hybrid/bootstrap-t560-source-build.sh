#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.2}"
SRC_ROOT="${SRC_ROOT:-/zfast/orangefs-lab}"
REPO_URL="${REPO_URL:-https://github.com/waltligon/orangefs.git}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

echo "==> Bootstrapping OrangeFS source-build workspace on ${TARGET_HOST}"

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<REMOTE
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
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
  liblmdb-dev \
  libssl-dev \
  libxml2-dev \
  zlib1g-dev

install -d -m 0755 "${SRC_ROOT}"

if [[ ! -d "${SRC_ROOT}/orangefs-src/.git" ]]; then
  git clone --depth 1 "${REPO_URL}" "${SRC_ROOT}/orangefs-src"
else
  git -C "${SRC_ROOT}/orangefs-src" pull --ff-only
fi

git -C "${SRC_ROOT}/orangefs-src" rev-parse HEAD > "${SRC_ROOT}/orangefs-src/.current-head"
echo "== source head =="
cat "${SRC_ROOT}/orangefs-src/.current-head"

echo "== workspace =="
df -h "${SRC_ROOT}"
REMOTE
