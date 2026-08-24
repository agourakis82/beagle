#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
TEMPLATE="$ROOT_DIR/k8s/workspace-platform/templates/sounio-loom-replay-canary.yaml.tmpl"
MODE=dry-run
KEEP=0
NAMESPACE=beagle
CANARY_NAME="sounio-loom-replay-$(date -u +%Y%m%d%H%M%S)"
NODE_NAME=t560-proxmox
STORAGE_CLASS=ceph-rbd-ssd-rwop
STORAGE_SIZE=5Gi
WORKSPACE_IMAGE=192.168.3.207:5003/sounio-lab-beagle-workspace-ssh-20260619-chownfix:slurm-warn-20260811
SOUNIO_REPO_URL=https://github.com/Sounio-lang/sounio.git
SOUNIO_SOURCE_REF=lane/codex-1/20260814
SOUNIO_SOURCE_COMMIT=''
EVIDENCE_DIR=''
TIMEOUT=900s
PROTECTED_POD=sounio-workspace-control-0
EXECUTED=0

usage() {
  cat <<'USAGE'
Usage: run-sounio-loom-replay-canary.sh [options]

Renders and server-validates an isolated retained-PVC StatefulSet by default.
Live execution requires both --execute and an exact 40-character Sounio SHA.

Options:
  --execute                 apply the canary and execute all three Pod phases
  --keep                    retain the canary StatefulSet, Service, and PVC
  --name NAME               exact sounio-loom-replay-* resource prefix
  --source-commit SHA       required exact Sounio commit
  --source-ref REF          clone ref containing SHA
  --evidence-dir DIR        output directory (default: /tmp/NAME-evidence)
  --timeout DURATION        kubectl wait duration (default: 900s)
  -h, --help                show this help
USAGE
}

fail() {
  printf 'sounio-loom-replay-canary: FAIL: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --execute) MODE=execute; shift ;;
    --keep) KEEP=1; shift ;;
    --name) [[ $# -ge 2 ]] || fail '--name requires a value'; CANARY_NAME="$2"; shift 2 ;;
    --source-commit) [[ $# -ge 2 ]] || fail '--source-commit requires a value'; SOUNIO_SOURCE_COMMIT="$2"; shift 2 ;;
    --source-ref) [[ $# -ge 2 ]] || fail '--source-ref requires a value'; SOUNIO_SOURCE_REF="$2"; shift 2 ;;
    --evidence-dir) [[ $# -ge 2 ]] || fail '--evidence-dir requires a value'; EVIDENCE_DIR="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || fail '--timeout requires a value'; TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ "$CANARY_NAME" =~ ^sounio-loom-replay-[a-z0-9-]+$ && ${#CANARY_NAME} -le 63 ]] || \
  fail 'resource name must match sounio-loom-replay-[a-z0-9-]+ and fit DNS-63'
[[ "$CANARY_NAME" != sounio-workspace* && "$CANARY_NAME" != *control* ]] || \
  fail 'resource name overlaps a protected workspace identity'
[[ "$SOUNIO_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || \
  fail '--source-commit must be an exact lowercase 40-character Git SHA'
[[ "$SOUNIO_SOURCE_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || fail 'source ref contains unsupported characters'
[[ "$TIMEOUT" =~ ^[1-9][0-9]*[smh]$ ]] || fail 'timeout must look like 900s, 15m, or 1h'
command -v kubectl >/dev/null || fail 'kubectl is required'

EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/$CANARY_NAME-evidence}"
mkdir -p "$EVIDENCE_DIR"
RENDERED="$EVIDENCE_DIR/rendered.yaml"
BEAGLE_SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
export NAMESPACE CANARY_NAME NODE_NAME STORAGE_CLASS STORAGE_SIZE WORKSPACE_IMAGE
export SOUNIO_REPO_URL SOUNIO_SOURCE_REF SOUNIO_SOURCE_COMMIT BEAGLE_SOURCE_COMMIT

rendered="$(<"$TEMPLATE")"
for variable in NAMESPACE CANARY_NAME NODE_NAME STORAGE_CLASS STORAGE_SIZE \
  WORKSPACE_IMAGE SOUNIO_REPO_URL SOUNIO_SOURCE_REF SOUNIO_SOURCE_COMMIT \
  BEAGLE_SOURCE_COMMIT; do
  placeholder="\${$variable}"
  rendered="${rendered//$placeholder/${!variable}}"
done
printf '%s\n' "$rendered" > "$RENDERED"

kubectl apply --dry-run=server -f "$RENDERED" > "$EVIDENCE_DIR/server-dry-run.txt"
if [[ "$MODE" == dry-run ]]; then
  printf 'SOUNIO_LOOM_REPLAY_CANARY_DRY_RUN=true name=%s manifest=%s validation=%s\n' \
    "$CANARY_NAME" "$RENDERED" "$EVIDENCE_DIR/server-dry-run.txt"
  exit 0
fi

[[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]] || \
  fail 'Beagle worktree must be clean before live execution'
branch="$(git -C "$ROOT_DIR" symbolic-ref --short HEAD)"
remote_sha="$(git -C "$ROOT_DIR" ls-remote --heads origin "refs/heads/$branch" | awk '{print $1}')"
[[ "$remote_sha" == "$BEAGLE_SOURCE_COMMIT" ]] || \
  fail "Beagle source commit is not pushed on origin/$branch"
kubectl get storageclass "$STORAGE_CLASS" >/dev/null
kubectl get node "$NODE_NAME" >/dev/null

for resource in "service/$CANARY_NAME" "statefulset/$CANARY_NAME" \
  "pod/$CANARY_NAME-0" "pvc/state-$CANARY_NAME-0"; do
  if kubectl -n "$NAMESPACE" get "$resource" >/dev/null 2>&1; then
    fail "refusing pre-existing canary resource: $resource"
  fi
done

protected_before="$(kubectl -n "$NAMESPACE" get pod "$PROTECTED_POD" \
  -o jsonpath='{.metadata.uid} {.status.phase}')"
[[ "$protected_before" == *' Running' ]] || fail "protected workspace is not Running: $protected_before"
printf 'protected_pod=%s before=%s\n' "$PROTECTED_POD" "$protected_before" \
  > "$EVIDENCE_DIR/protected-workspace.txt"

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$EXECUTED" == 1 ]]; then
    kubectl -n "$NAMESPACE" get pod "$CANARY_NAME-0" -o yaml \
      > "$EVIDENCE_DIR/final-pod.yaml" 2>/dev/null || true
  fi
  if [[ "$EXECUTED" == 1 && "$KEEP" == 0 ]]; then
    kubectl -n "$NAMESPACE" delete statefulset "$CANARY_NAME" \
      --ignore-not-found --wait=true --timeout=180s >/dev/null 2>&1 || true
    kubectl -n "$NAMESPACE" delete service "$CANARY_NAME" \
      --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
    kubectl -n "$NAMESPACE" delete pvc "state-$CANARY_NAME-0" \
      --ignore-not-found --wait=true --timeout=180s >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

EXECUTED=1
kubectl apply -f "$RENDERED" > "$EVIDENCE_DIR/apply.txt"
kubectl -n "$NAMESPACE" rollout status "statefulset/$CANARY_NAME" --timeout="$TIMEOUT" \
  > "$EVIDENCE_DIR/rollout.txt"
POD="$CANARY_NAME-0"

pod_uid() {
  kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.metadata.uid}'
}

wait_successor() {
  local predecessor_uid="$1" successor_uid='' attempt
  kubectl -n "$NAMESPACE" delete pod "$POD" --wait=true --timeout=180s \
    > "$EVIDENCE_DIR/delete-$predecessor_uid.txt"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout="$TIMEOUT" >/dev/null
  for attempt in $(seq 1 120); do
    successor_uid="$(pod_uid 2>/dev/null || true)"
    [[ -n "$successor_uid" && "$successor_uid" != "$predecessor_uid" ]] && {
      printf '%s\n' "$successor_uid"
      return 0
    }
    sleep 1
  done
  fail "StatefulSet did not replace Pod UID $predecessor_uid"
}

run_phase() {
  local phase="$1" output="$2"
  kubectl -n "$NAMESPACE" exec "$POD" -- \
    bash /state/sounio/scripts/ci/sounio_loom_pod_replay_canary.sh "$phase" \
    | tee "$output"
}

uid_one="$(pod_uid)"
run_phase phase-one "$EVIDENCE_DIR/phase-one.txt"
uid_two="$(wait_successor "$uid_one")"
run_phase phase-two "$EVIDENCE_DIR/phase-two.txt"
uid_three="$(wait_successor "$uid_two")"
run_phase phase-three "$EVIDENCE_DIR/phase-three.txt"

kubectl -n "$NAMESPACE" exec "$POD" -- \
  bash /state/sounio/scripts/ci/sounio_loom_pod_replay_canary.sh report \
  > "$EVIDENCE_DIR/result.txt"
grep -q '^SOUNIO_LOOM_SEPARATE_POD_REPLAY_PASS=true$' "$EVIDENCE_DIR/result.txt" || \
  fail 'final canary result did not pass'
[[ "$uid_one" != "$uid_two" && "$uid_one" != "$uid_three" && "$uid_two" != "$uid_three" ]] || \
  fail 'canary did not observe three distinct Kubernetes Pod UIDs'

protected_after="$(kubectl -n "$NAMESPACE" get pod "$PROTECTED_POD" \
  -o jsonpath='{.metadata.uid} {.status.phase}')"
printf 'after=%s\n' "$protected_after" >> "$EVIDENCE_DIR/protected-workspace.txt"
[[ "$protected_after" == "$protected_before" ]] || \
  fail "protected workspace identity changed: before=$protected_before after=$protected_after"

cat > "$EVIDENCE_DIR/runner-receipt.txt" <<EOF
SOUNIO_LOOM_REAL_POD_CANARY_PASS=true
schema=beagle-sounio-loom-real-pod-canary-v1
beagle_source_commit=$BEAGLE_SOURCE_COMMIT
sounio_source_commit=$SOUNIO_SOURCE_COMMIT
namespace=$NAMESPACE
statefulset=$CANARY_NAME
pod_uid_one=$uid_one
pod_uid_two=$uid_two
pod_uid_three=$uid_three
protected_workspace=$PROTECTED_POD
protected_workspace_uid_phase=$protected_after
cleanup_requested=$((1 - KEEP))
EOF

printf 'SOUNIO_LOOM_REAL_POD_CANARY_PASS=true name=%s evidence=%s pod_uids=%s,%s,%s\n' \
  "$CANARY_NAME" "$EVIDENCE_DIR" "$uid_one" "$uid_two" "$uid_three"
