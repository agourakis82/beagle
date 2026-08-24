#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
TEMPLATE="$ROOT_DIR/k8s/workspace-platform/templates/sounio-loom-canary-image-build-job.yaml.tmpl"
MODE=dry-run
KEEP=0
NAMESPACE=beagle
NODE_NAME=t560-proxmox
BUILD_JOB_NAME="sounio-loom-image-$(date -u +%Y%m%d%H%M%S)"
BEAGLE_REPO_URL=https://github.com/agourakis82/beagle.git
BEAGLE_SOURCE_REF="$(git -C "$ROOT_DIR" symbolic-ref --short HEAD)"
BEAGLE_SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
IMAGE_REPOSITORY=192.168.3.207:5003/sounio-loom-canary
IMAGE_TAG=20260824-native-sounio-v1
EVIDENCE_DIR=''
TIMEOUT=20m
EXECUTED=0

usage() {
  cat <<'USAGE'
Usage: build-sounio-loom-canary-image.sh [options]

Renders and server-validates the Kaniko Job by default. --execute requires the
current Beagle commit to be clean and pushed on its current branch.

Options:
  --execute                 build and publish the image
  --keep                    retain the completed Job
  --job-name NAME           exact sounio-loom-image-* Job name
  --image-tag TAG           registry tag (default: 20260824-native-sounio-v1)
  --evidence-dir DIR        output directory
  --timeout DURATION        Job timeout (default: 20m)
  -h, --help                show this help
USAGE
}

fail() {
  printf 'sounio-loom-canary-image: FAIL: %s\n' "$*" >&2
  exit 1
}

duration_seconds() {
  local value="$1" amount="${1%?}" suffix="${1: -1}"
  case "$suffix" in
    s) printf '%s\n' "$amount" ;;
    m) printf '%s\n' "$((amount * 60))" ;;
    h) printf '%s\n' "$((amount * 3600))" ;;
    *) fail "unsupported timeout: $value" ;;
  esac
}

while (($#)); do
  case "$1" in
    --execute) MODE=execute; shift ;;
    --keep) KEEP=1; shift ;;
    --job-name) [[ $# -ge 2 ]] || fail '--job-name requires a value'; BUILD_JOB_NAME="$2"; shift 2 ;;
    --image-tag) [[ $# -ge 2 ]] || fail '--image-tag requires a value'; IMAGE_TAG="$2"; shift 2 ;;
    --evidence-dir) [[ $# -ge 2 ]] || fail '--evidence-dir requires a value'; EVIDENCE_DIR="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || fail '--timeout requires a value'; TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ "$BUILD_JOB_NAME" =~ ^sounio-loom-image-[a-z0-9-]+$ && ${#BUILD_JOB_NAME} -le 63 ]] || \
  fail 'Job name must match sounio-loom-image-[a-z0-9-]+ and fit DNS-63'
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'image tag contains unsupported characters'
[[ "$TIMEOUT" =~ ^[1-9][0-9]*[smh]$ ]] || fail 'timeout must look like 1200s, 20m, or 1h'
command -v kubectl >/dev/null || fail 'kubectl is required'
command -v curl >/dev/null || fail 'curl is required'

IMAGE_DESTINATION="$IMAGE_REPOSITORY:$IMAGE_TAG"
EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/$BUILD_JOB_NAME-evidence}"
mkdir -p "$EVIDENCE_DIR"
RENDERED="$EVIDENCE_DIR/rendered.yaml"
export NAMESPACE NODE_NAME BUILD_JOB_NAME BEAGLE_REPO_URL BEAGLE_SOURCE_REF
export BEAGLE_SOURCE_COMMIT IMAGE_DESTINATION

rendered="$(<"$TEMPLATE")"
for variable in NAMESPACE NODE_NAME BUILD_JOB_NAME BEAGLE_REPO_URL \
  BEAGLE_SOURCE_REF BEAGLE_SOURCE_COMMIT IMAGE_DESTINATION; do
  placeholder="\${$variable}"
  rendered="${rendered//$placeholder/${!variable}}"
done
printf '%s\n' "$rendered" > "$RENDERED"
kubectl apply --dry-run=server -f "$RENDERED" > "$EVIDENCE_DIR/server-dry-run.txt"

if [[ "$MODE" == dry-run ]]; then
  printf 'SOUNIO_LOOM_CANARY_IMAGE_DRY_RUN=true job=%s image=%s manifest=%s\n' \
    "$BUILD_JOB_NAME" "$IMAGE_DESTINATION" "$RENDERED"
  exit 0
fi

[[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]] || \
  fail 'Beagle worktree must be clean before a live image build'
remote_sha="$(git -C "$ROOT_DIR" ls-remote --heads origin "refs/heads/$BEAGLE_SOURCE_REF" | awk '{print $1}')"
[[ "$remote_sha" == "$BEAGLE_SOURCE_COMMIT" ]] || \
  fail "Beagle source commit is not pushed on origin/$BEAGLE_SOURCE_REF"
kubectl get node "$NODE_NAME" >/dev/null
if kubectl -n "$NAMESPACE" get job "$BUILD_JOB_NAME" >/dev/null 2>&1; then
  fail "refusing pre-existing Job: $BUILD_JOB_NAME"
fi

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$EXECUTED" == 1 ]]; then
    kubectl -n "$NAMESPACE" logs "job/$BUILD_JOB_NAME" -c kaniko \
      > "$EVIDENCE_DIR/kaniko.log" 2>&1 || true
  fi
  if [[ "$EXECUTED" == 1 && "$KEEP" == 0 ]]; then
    kubectl -n "$NAMESPACE" delete job "$BUILD_JOB_NAME" \
      --ignore-not-found --wait=true --timeout=180s >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

EXECUTED=1
kubectl apply -f "$RENDERED" > "$EVIDENCE_DIR/apply.txt"
deadline="$((SECONDS + $(duration_seconds "$TIMEOUT")))"
while ((SECONDS < deadline)); do
  succeeded="$(kubectl -n "$NAMESPACE" get job "$BUILD_JOB_NAME" \
    -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  failed="$(kubectl -n "$NAMESPACE" get job "$BUILD_JOB_NAME" \
    -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  if [[ "$succeeded" == 1 ]]; then
    printf 'job=%s state=complete\n' "$BUILD_JOB_NAME" > "$EVIDENCE_DIR/wait.txt"
    break
  fi
  [[ -z "$failed" || "$failed" == 0 ]] || fail "Kaniko Job failed: $BUILD_JOB_NAME"
  sleep 2
done
[[ "${succeeded:-}" == 1 ]] || fail "Kaniko Job timed out after $TIMEOUT: $BUILD_JOB_NAME"
manifest_headers="$EVIDENCE_DIR/manifest-headers.txt"
curl --fail --silent --show-error --dump-header "$manifest_headers" --output "$EVIDENCE_DIR/manifest.json" \
  --header 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  "http://192.168.3.207:5003/v2/sounio-loom-canary/manifests/$IMAGE_TAG"
image_digest="$(awk 'tolower($1) == "docker-content-digest:" {gsub("\r", "", $2); print $2}' "$manifest_headers" | tail -1)"
[[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail 'registry omitted the immutable image digest'

cat > "$EVIDENCE_DIR/receipt.txt" <<EOF
SOUNIO_LOOM_CANARY_IMAGE_BUILD_PASS=true
schema=sounio-loom-canary-image-build-v1
beagle_source_commit=$BEAGLE_SOURCE_COMMIT
image_tag=$IMAGE_DESTINATION
image_digest=$IMAGE_REPOSITORY@$image_digest
EOF
printf 'SOUNIO_LOOM_CANARY_IMAGE_BUILD_PASS=true image=%s@%s evidence=%s\n' \
  "$IMAGE_REPOSITORY" "$image_digest" "$EVIDENCE_DIR"
