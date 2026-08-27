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

echo "==> staging conclave-search source from $CONCLAVE_SEARCH_DIR"
mkdir -p "$CTX/conclave-search-src"
cp -r "$CONCLAVE_SEARCH_DIR/src"    "$CTX/conclave-search-src/src"
cp -r "$CONCLAVE_SEARCH_DIR/search" "$CTX/conclave-search-src/search"

cp "$HERE/app.py" "$HERE/requirements.txt" "$HERE/Dockerfile" "$CTX/"

echo "==> building $IMAGE with $ENGINE"
"$ENGINE" build -t "$IMAGE" "$CTX"
echo "==> done: $IMAGE"
