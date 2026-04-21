#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.3}"
BASE="${BASE:-/var/lib/orangefs-lab}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-Urso1982!}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS:-Urso1982!}" ssh -o StrictHostKeyChecking=no)
fi

"${SSH_BASE[@]}" "${TARGET_HOST}" "BASE='${BASE}' bash -s" <<'REMOTE'
set -euo pipefail

src="$BASE/orangefs-src"
build="$BASE/orangefs-build-serveronly-dyn"
prefix="$BASE/install-serveronly-dyn"
kheaders="/usr/src/linux-headers-$(uname -r)"

cd "$src"

python3 - <<'PY'
from pathlib import Path

p = Path("configure.ac")
lines = p.read_text().splitlines()
needle = "The kernel source tree does not appear to be 2.6 or 3.X or 4.X or 5.X or 6.X"
joined = "\n".join(lines)
if needle not in joined:
    four_idx = next((i for i, line in enumerate(lines) if "UTS_RELEASE..4" in line), None)
    if four_idx is None:
        raise SystemExit("expected 4.x kernel branch not found")

    err_idx = next(
        (i for i, line in enumerate(lines) if "The kernel source tree does not appear to be 2.6 or 3.X or 4.X" in line),
        None,
    )
    if err_idx is None:
        raise SystemExit("expected kernel error line not found")

    insert_at = four_idx + 2
    lines[err_idx] = "        AC_MSG_ERROR(The kernel source tree does not appear to be 2.6 or 3.X or 4.X or 5.X or 6.X)"
    lines[insert_at:insert_at] = [
        "    elif test -r  $withval/include/generated/utsrelease.h && grep -qE UTS_RELEASE..[56]\\\\. $withval/include/generated/utsrelease.h; then",
        "        vers=`sed -n '/UTS_RELEASE/{; s/.*\"\\\\([0-9]\\\\.[0-9]\\\\).*\".*/\\\\1/; p; }' $withval/include/generated/utsrelease.h`",
    ]
    p.write_text("\n".join(lines) + "\n")
PY

autoreconf -fi -I maint/config >/tmp/orangefs-autoreconf-5860.log 2>&1

python3 - <<'PY'
from pathlib import Path

p = Path("configure")
lines = p.read_text().splitlines()

if not any("UTS_RELEASE..[56]\\\\." in line for line in lines):
    four_idx = next((i for i, line in enumerate(lines) if "UTS_RELEASE..4\\\\." in line), None)
    if four_idx is None:
        raise SystemExit("generated configure 4.x branch not found")
    insert_at = four_idx + 2
    lines[insert_at:insert_at] = [
        "    elif test -r  $withval/include/generated/utsrelease.h && grep -qE UTS_RELEASE..[56]\\\\. $withval/include/generated/utsrelease.h; then",
        "        vers=`sed -n '/UTS_RELEASE/{; s/.*\"\\([0-9]\\.[0-9]\\).*\".*/\\1/; p; }' $withval/include/generated/utsrelease.h`",
    ]

p.write_text("\n".join(lines) + "\n")
PY

rm -rf "$build"
mkdir -p "$build"
cd "$build"

"$src/configure" \
  --prefix="$prefix" \
  --with-db-backend=lmdb \
  --with-kernel="$kheaders" \
  --disable-olib \
  --disable-threaded

mkdir -p src/common/statecomp
cp -f "$src/src/common/statecomp/parser.c" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/parser.h" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/parser.o" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/scanner.c" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/scanner.o" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/codegen.o" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/statecomp" src/common/statecomp/ || true
cp -f "$src/src/common/statecomp/statecomp.o" src/common/statecomp/ || true

BUILD_ROOT="$build" SOURCE_ROOT="$src" python3 - <<'PY'
import os, shlex, shutil, subprocess

build_root = os.environ["BUILD_ROOT"]
source_root = os.environ["SOURCE_ROOT"]
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
file src/server/pvfs2-server
REMOTE
