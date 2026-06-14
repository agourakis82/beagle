#!/usr/bin/env bash
# Stage the minimal Sounio runtime (static compiler + stdlib) from a Sounio checkout
# into a build context, then build the service image. Demonstrates exactly what an
# outside consumer needs: bin/souc, bin/souc-linux-x86_64, stdlib/. Nothing else.
set -euo pipefail

SOUNIO_DIR="${SOUNIO_DIR:-/home/devsounio/sounio}"
IMAGE="${IMAGE:-sounio-inference:dev}"
ENGINE="${ENGINE:-podman}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT

echo "==> staging Sounio runtime from $SOUNIO_DIR"
mkdir -p "$CTX/sounio-runtime/bin"
cp "$SOUNIO_DIR/bin/souc"               "$CTX/sounio-runtime/bin/"
cp "$SOUNIO_DIR/bin/souc-linux-x86_64"  "$CTX/sounio-runtime/bin/"
cp -r "$SOUNIO_DIR/stdlib"              "$CTX/sounio-runtime/stdlib"
cp "$HERE/app.py" "$HERE/requirements.txt" "$HERE/Dockerfile" "$CTX/"

echo "==> runtime size: $(du -sh "$CTX/sounio-runtime" | cut -f1) (compiler + stdlib)"
echo "==> building $IMAGE with $ENGINE"
"$ENGINE" build -t "$IMAGE" "$CTX"
echo "==> done: $IMAGE"
