#!/usr/bin/env bash
set -euo pipefail

ORANGEFS_MNT="${ORANGEFS_MNT:-/zfast/orangefs-lab/two-node/mnt}"
LOCAL_PATH="${LOCAL_PATH:-/zfast/orangefs-lab/bench-local}"
OUTDIR="${OUTDIR:-/zfast/orangefs-lab/bench-results/$(date +%Y%m%d-%H%M%S)}"
SIZE_MB="${SIZE_MB:-256}"
FILE_COUNT="${FILE_COUNT:-2000}"

mkdir -p "$OUTDIR" "$LOCAL_PATH"

run_seq() {
  local label="$1"
  local base="$2"
  local file="$base/seq-${SIZE_MB}m.bin"
  mkdir -p "$base"
  sync
  python3 - "$file" "$SIZE_MB" "$label" <<'EOF'
import os, sys, time, hashlib
path = sys.argv[1]
size_mb = int(sys.argv[2])
label = sys.argv[3]
chunk = b"\0" * (1024 * 1024)
start = time.time()
with open(path, "wb") as f:
    for _ in range(size_mb):
        f.write(chunk)
    f.flush()
    os.fsync(f.fileno())
write_s = time.time() - start
start = time.time()
h = hashlib.sha256()
with open(path, "rb") as f:
    while True:
        data = f.read(1024 * 1024)
        if not data:
            break
        h.update(data)
read_s = time.time() - start
print(f"{label},seq_write_mb_s,{size_mb / write_s:.2f}")
print(f"{label},seq_read_mb_s,{size_mb / read_s:.2f}")
print(f"{label},sha256,{h.hexdigest()}")
EOF
}

run_meta() {
  local label="$1"
  local base="$2"
  local dir="$base/meta-${FILE_COUNT}"
  rm -rf "$dir"
  mkdir -p "$dir"
  python3 - "$dir" "$FILE_COUNT" "$label" <<'EOF'
import os, sys, time
dirp = sys.argv[1]
count = int(sys.argv[2])
label = sys.argv[3]
start = time.time()
for i in range(count):
    with open(os.path.join(dirp, f"f{i:05d}.txt"), "w") as f:
        f.write("x")
create_s = time.time() - start
start = time.time()
for i in range(count):
    os.stat(os.path.join(dirp, f"f{i:05d}.txt"))
stat_s = time.time() - start
start = time.time()
for i in range(count):
    os.unlink(os.path.join(dirp, f"f{i:05d}.txt"))
remove_s = time.time() - start
print(f"{label},create_ops_s,{count / create_s:.2f}")
print(f"{label},stat_ops_s,{count / stat_s:.2f}")
print(f"{label},remove_ops_s,{count / remove_s:.2f}")
EOF
  rmdir "$dir"
}

{
  echo "metric_set,path,value"
  run_seq orangefs "$ORANGEFS_MNT" | awk -F, '{print $1","$2","$3}'
  run_meta orangefs "$ORANGEFS_MNT" | awk -F, '{print $1","$2","$3}'
  run_seq local "$LOCAL_PATH" | awk -F, '{print $1","$2","$3}'
  run_meta local "$LOCAL_PATH" | awk -F, '{print $1","$2","$3}'
} | tee "$OUTDIR/results.csv"

echo "Results saved to $OUTDIR/results.csv"
