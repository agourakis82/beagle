#!/usr/bin/env bash
set -euo pipefail

host="${ORANGEFS_HOST:-root@10.100.100.2}"
pass="${ORANGEFS_PASS:?defina ORANGEFS_PASS no ambiente (nunca no script); prefira chave SSH}"

ssh_cmd=(
  sshpass -p "$pass"
  ssh
  -o StrictHostKeyChecking=no
  "$host"
)

"${ssh_cmd[@]}" '
set -euo pipefail

src=/zfast/orangefs-lab/orangefs-src
build=/zfast/orangefs-lab/orangefs-build-serveronly-dyn
prefix=/zfast/orangefs-lab/install-serveronly-dyn
kheaders=/usr/src/linux-headers-6.17.13-2-pve

rm -rf "$build"
mkdir -p "$build"
cd "$build"

"$src/configure" \
  --prefix="$prefix" \
  --with-db-backend=lmdb \
  --with-kernel="$kheaders" \
  --disable-olib \
  --disable-threaded

# Out-of-tree builds still miss generated statecomp artifacts on current source.
mkdir -p src/common/statecomp
cp -f "$src/src/common/statecomp/parser.c" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/parser.h" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/parser.o" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/scanner.c" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/scanner.o" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/codegen.o" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/statecomp" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/statecomp.o" src/common/statecomp/ || true

# Some server objects get emitted into the source tree during the mixed build flow.
python3 - <<'"'"'PY'"'"'
import os, shlex, shutil, subprocess
build_root = "/zfast/orangefs-lab/orangefs-build-serveronly-dyn"
source_root = "/zfast/orangefs-lab/orangefs-src"
mk = subprocess.check_output("make -pn", shell=True, text=True, stderr=subprocess.DEVNULL)
serverobjs = None
for line in mk.splitlines():
    if line.startswith("SERVEROBJS :="):
        serverobjs = shlex.split(line.split(":=", 1)[1].strip())
        break
if not serverobjs:
    raise SystemExit("SERVEROBJS not found")
for rel in serverobjs:
    b = os.path.join(build_root, rel)
    s = os.path.join(source_root, rel)
    if (not os.path.exists(b)) and os.path.exists(s):
        os.makedirs(os.path.dirname(b), exist_ok=True)
        shutil.copy2(s, b)
PY

make -j1 src/server/pvfs2-server V=1
'
