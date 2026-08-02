#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.2}"
SRC_ROOT="${SRC_ROOT:-/zfast/orangefs-lab}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail

cd /zfast/orangefs-lab/orangefs-src

python3 - <<'PY'
from pathlib import Path

p = Path("configure.ac")
lines = p.read_text().splitlines()
needle = "The kernel source tree does not appear to be 2.6 or 3.X or 4.X or 5.X or 6.X"
joined = "\n".join(lines)
if needle in joined:
    print("kernel 5/6 patch already present")
else:
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
    print("applied kernel 5/6 patch")
PY

nl -ba configure.ac | sed -n '787,799p'

autoreconf -fi -I maint/config >/tmp/orangefs-autoreconf.log 2>&1

python3 - <<'PY'
from pathlib import Path

p = Path("configure")
lines = p.read_text().splitlines()

branch_idx = next((i for i, line in enumerate(lines) if "UTS_RELEASE..56\\\\." in line), None)
if branch_idx is None:
    raise SystemExit("generated configure 5/6 branch not found")

lines[branch_idx] = "    elif test -r  $withval/include/generated/utsrelease.h && grep -qE UTS_RELEASE..[56]\\\\. $withval/include/generated/utsrelease.h; then"
lines[branch_idx + 1] = "        vers=`sed -n '/UTS_RELEASE/{; s/.*\"\\([0-9]\\.[0-9]\\).*\".*/\\1/; p; }' $withval/include/generated/utsrelease.h`"

p.write_text("\n".join(lines) + "\n")
print("patched generated configure for kernel 5/6 detection")
PY

install -d -m 0755 /zfast/orangefs-lab/orangefs-build
cd /zfast/orangefs-lab/orangefs-build
../orangefs-src/configure \
  --prefix=/zfast/orangefs-lab/install \
  --with-db-backend=lmdb \
  --enable-usrint \
  --enable-usrint-kmount \
  --with-kernel=/usr/src/linux-headers-6.17.13-2-pve \
  >/tmp/orangefs-configure.log 2>&1

printf '\n=== CONFIGURE TAIL ===\n'
tail -n 120 /tmp/orangefs-configure.log
REMOTE
