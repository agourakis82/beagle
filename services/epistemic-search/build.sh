#!/usr/bin/env bash
# services/epistemic-search/build.sh
# Stages the Sounio runtime and conclave-search source into a build
# context, then builds the service image. Mirrors
# services/sounio-inference/build.sh's exact staging pattern.
set -euo pipefail

SOUNIO_DIR="${SOUNIO_DIR:-/home/devsounio/sounio}"
CONCLAVE_SEARCH_DIR="${CONCLAVE_SEARCH_DIR:-/home/devsounio/conclave-search}"
IMAGE="${IMAGE:-epistemic-search:dev}"
ENGINE="${ENGINE:-podman}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT

echo "==> staging Sounio runtime from $SOUNIO_DIR"
mkdir -p "$CTX/sounio-runtime/bin"
cp "$SOUNIO_DIR/bin/souc"               "$CTX/sounio-runtime/bin/"
cp "$SOUNIO_DIR/bin/souc-linux-x86_64"  "$CTX/sounio-runtime/bin/"
cp -r "$SOUNIO_DIR/stdlib"              "$CTX/sounio-runtime/stdlib"

# conclave-search's src/main.sio imports multiple search::* modules (see
# search/), which needs Madaros's modular/multi-file import resolver --
# lean_single (the single-file bootstrap engine) cannot resolve `use
# search::foo::*` across separate files and fails compilation with
# "error: no main". So also stage the Madaros launcher + raw ELF, not just
# the bin/souc shim + lean_single fallback, so bin/souc routes to Madaros
# by default instead of silently falling back to lean_single.
cp "$SOUNIO_DIR/bin/madaros"             "$CTX/sounio-runtime/bin/"
cp "$SOUNIO_DIR/bin/madaros-linux-x86_64" "$CTX/sounio-runtime/bin/"

# bin/souc resolves the actual compiled-compiler ELF in this order:
# artifacts/self-hosted/madaros, then bin/madaros-linux-x86_64 (see
# bin/souc's own _resolve_madaros). bin/madaros-linux-x86_64 is a
# checked-in artifact that can silently predate self-hosted/ fixes (e.g.
# the arena size bump, eea3a449f) -- D19 found exactly this: a stale
# 2 GiB-arena compiler shipped in this image despite the fix landing in
# self-hosted/ long before. Stage the freshly-built artifact so a
# `bash scripts/ci/build_modular_madaros.sh artifacts/self-hosted/madaros`
# run in $SOUNIO_DIR before invoking this script is what actually gets
# used, not whatever bin/madaros-linux-x86_64 happens to contain.
mkdir -p "$CTX/sounio-runtime/artifacts/self-hosted"
if [ -f "$SOUNIO_DIR/artifacts/self-hosted/madaros" ]; then
  cp "$SOUNIO_DIR/artifacts/self-hosted/madaros" "$CTX/sounio-runtime/artifacts/self-hosted/madaros"
else
  echo "==> WARNING: $SOUNIO_DIR/artifacts/self-hosted/madaros not found -- falling back to bin/madaros-linux-x86_64, which may be stale. Run: bash scripts/ci/build_modular_madaros.sh artifacts/self-hosted/madaros (in \$SOUNIO_DIR) first." >&2
  cp "$SOUNIO_DIR/bin/madaros-linux-x86_64" "$CTX/sounio-runtime/artifacts/self-hosted/madaros"
fi

echo "==> staging conclave-search source from $CONCLAVE_SEARCH_DIR"
mkdir -p "$CTX/conclave-search-src"
cp -r "$CONCLAVE_SEARCH_DIR/src"    "$CTX/conclave-search-src/src"
cp -r "$CONCLAVE_SEARCH_DIR/search" "$CTX/conclave-search-src/search"

echo "==> staging internal CA root"
bash "$HERE/../../k8s/conclave-search-tls/extract-ca-root.sh" > "$CTX/internal-ip-ca-root.crt"

cp "$HERE/app.py" "$HERE/requirements.txt" "$HERE/Dockerfile" "$CTX/"

echo "==> building $IMAGE with $ENGINE"
"$ENGINE" build -t "$IMAGE" "$CTX"
echo "==> done: $IMAGE"
