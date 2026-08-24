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
SUCCESSOR_NODE=r740-proxmox
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
SECRET_CREATED=0
KEY_WORK=''
SIGNER_KEY_ID=''

usage() {
  cat <<'USAGE'
Usage: run-sounio-loom-replay-canary.sh [options]

Renders and server-validates an isolated retained-PVC StatefulSet by default.
Live execution requires both --execute and an exact 40-character Sounio SHA.

Options:
  --execute                 apply the canary and execute four signed Pod phases
  --keep                    retain the canary StatefulSet, Service, and PVC
  --name NAME               exact sounio-loom-replay-* resource prefix
  --source-commit SHA       required exact Sounio commit
  --source-ref REF          clone ref containing SHA
  --successor-node NODE     move the first successor to this distinct node
  --image IMAGE             canary image tag or immutable digest
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
    --successor-node) [[ $# -ge 2 ]] || fail '--successor-node requires a value'; SUCCESSOR_NODE="$2"; shift 2 ;;
    --image) [[ $# -ge 2 ]] || fail '--image requires a value'; WORKSPACE_IMAGE="$2"; shift 2 ;;
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
[[ "$NODE_NAME" =~ ^[a-z0-9.-]+$ && "$SUCCESSOR_NODE" =~ ^[a-z0-9.-]+$ ]] || \
  fail 'node names contain unsupported characters'
[[ "$SUCCESSOR_NODE" != "$NODE_NAME" ]] || fail 'successor node must differ from the initial node'
[[ "$WORKSPACE_IMAGE" =~ ^[A-Za-z0-9./:@_-]+$ ]] || fail 'image reference contains unsupported characters'
[[ "$TIMEOUT" =~ ^[1-9][0-9]*[smh]$ ]] || fail 'timeout must look like 900s, 15m, or 1h'
command -v kubectl >/dev/null || fail 'kubectl is required'
command -v openssl >/dev/null || fail 'OpenSSL is required'

EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/$CANARY_NAME-evidence}"
mkdir -p "$EVIDENCE_DIR"
RENDERED="$EVIDENCE_DIR/rendered.yaml"
SIGNING_SECRET="$CANARY_NAME-signing"
BEAGLE_SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
export NAMESPACE CANARY_NAME NODE_NAME STORAGE_CLASS STORAGE_SIZE WORKSPACE_IMAGE
export SOUNIO_REPO_URL SOUNIO_SOURCE_REF SOUNIO_SOURCE_COMMIT BEAGLE_SOURCE_COMMIT
export SIGNING_SECRET

rendered="$(<"$TEMPLATE")"
for variable in NAMESPACE CANARY_NAME NODE_NAME STORAGE_CLASS STORAGE_SIZE \
  WORKSPACE_IMAGE SOUNIO_REPO_URL SOUNIO_SOURCE_REF SOUNIO_SOURCE_COMMIT \
  BEAGLE_SOURCE_COMMIT SIGNING_SECRET; do
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
kubectl get node "$SUCCESSOR_NODE" >/dev/null

for resource in "service/$CANARY_NAME" "statefulset/$CANARY_NAME" \
  "pod/$CANARY_NAME-0" "pvc/state-$CANARY_NAME-0" "secret/$SIGNING_SECRET"; do
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
  if [[ "$SECRET_CREATED" == 1 && "$KEEP" == 0 ]]; then
    kubectl -n "$NAMESPACE" delete secret "$SIGNING_SECRET" \
      --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
  fi
  if [[ -n "$KEY_WORK" && -d "$KEY_WORK" ]]; then
    rm -f "$KEY_WORK/private.pem" "$KEY_WORK/public.pem" "$KEY_WORK/secret.yaml"
    rmdir "$KEY_WORK" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT

KEY_WORK="$(mktemp -d "${TMPDIR:-/tmp}/$CANARY_NAME-signing.XXXXXX")"
openssl genpkey -algorithm ED25519 -out "$KEY_WORK/private.pem"
openssl pkey -in "$KEY_WORK/private.pem" -pubout -out "$KEY_WORK/public.pem"
install -m 0600 "$KEY_WORK/public.pem" "$EVIDENCE_DIR/signer-public.pem"
SIGNER_KEY_ID="$(sha256sum "$EVIDENCE_DIR/signer-public.pem" | awk '{print $1}')"
kubectl -n "$NAMESPACE" create secret generic "$SIGNING_SECRET" \
  --from-file=private.pem="$KEY_WORK/private.pem" \
  --from-file=public.pem="$KEY_WORK/public.pem" --dry-run=client -o yaml \
  > "$KEY_WORK/secret.yaml"
kubectl apply -f "$KEY_WORK/secret.yaml" > "$EVIDENCE_DIR/signing-secret-apply.txt"
SECRET_CREATED=1
rm -f "$KEY_WORK/private.pem" "$KEY_WORK/secret.yaml"

EXECUTED=1
kubectl apply -f "$RENDERED" > "$EVIDENCE_DIR/apply.txt"
kubectl -n "$NAMESPACE" rollout status "statefulset/$CANARY_NAME" --timeout="$TIMEOUT" \
  > "$EVIDENCE_DIR/rollout.txt"
POD="$CANARY_NAME-0"

pod_uid() {
  kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.metadata.uid}'
}

pod_node() {
  kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.spec.nodeName}'
}

wait_successor() {
  local predecessor_uid="$1" expected_node="$2" successor_uid='' successor_node='' attempt
  kubectl -n "$NAMESPACE" delete pod "$POD" --wait=true --timeout=180s \
    > "$EVIDENCE_DIR/delete-$predecessor_uid.txt"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout="$TIMEOUT" >/dev/null
  for attempt in $(seq 1 120); do
    successor_uid="$(pod_uid 2>/dev/null || true)"
    successor_node="$(pod_node 2>/dev/null || true)"
    [[ -n "$successor_uid" && "$successor_uid" != "$predecessor_uid" && \
       "$successor_node" == "$expected_node" ]] && {
      printf '%s\n' "$successor_uid"
      return 0
    }
    sleep 1
  done
  fail "StatefulSet did not replace Pod UID $predecessor_uid on node $expected_node"
}

move_successor() {
  local predecessor_uid="$1" expected_node="$2" successor_uid successor_node
  kubectl -n "$NAMESPACE" patch statefulset "$CANARY_NAME" --type=merge \
    --patch "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$expected_node\"}}}}}" \
    > "$EVIDENCE_DIR/move-$predecessor_uid-to-$expected_node.txt"
  kubectl -n "$NAMESPACE" rollout status "statefulset/$CANARY_NAME" \
    --timeout="$TIMEOUT" > "$EVIDENCE_DIR/move-rollout-$predecessor_uid.txt"
  successor_uid="$(pod_uid)"
  successor_node="$(pod_node)"
  [[ "$successor_uid" != "$predecessor_uid" && "$successor_node" == "$expected_node" ]] || \
    fail "cross-node rollout retained uid=$successor_uid node=$successor_node"
  printf '%s\n' "$successor_uid"
}

run_phase() {
  local phase="$1" output="$2"
  kubectl -n "$NAMESPACE" exec "$POD" -- \
    bash /state/sounio/scripts/ci/sounio_loom_pod_replay_canary.sh "$phase" \
    | tee "$output"
}

result_value() {
  local key="$1" value
  value="$(sed -n "s/^${key}=//p" "$EVIDENCE_DIR/result.txt")"
  [[ -n "$value" && "$value" != *$'\n'* ]] || \
    fail "result must contain exactly one non-empty $key value"
  printf '%s\n' "$value"
}

export_signed_receipt() {
  local label="$1" generation="$2" expected_digest="$3"
  local receipt="$EVIDENCE_DIR/signed-receipt-$label.txt"
  local verification="$EVIDENCE_DIR/signed-receipt-$label-verification.txt"
  local actual_digest

  kubectl -n "$NAMESPACE" exec "$POD" -- bash -lc '
    set -euo pipefail
    generation="$1"
    mapfile -t receipts < <(
      find /state/loom-pod-replay/loom \
        -path "*/generations/$generation/sounio-continuity.receipt" -type f -print
    )
    [[ ${#receipts[@]} -eq 1 ]]
    cat "${receipts[0]}"
  ' _ "$generation" > "$receipt"

  actual_digest="$(sha256sum "$receipt" | awk '{print $1}')"
  [[ "$actual_digest" == "$expected_digest" ]] || \
    fail "exported receipt $label digest mismatch: expected=$expected_digest actual=$actual_digest"

  kubectl -n "$NAMESPACE" exec "$POD" -- bash -lc '
    set -euo pipefail
    generation="$1"
    mapfile -t receipts < <(
      find /state/loom-pod-replay/loom \
        -path "*/generations/$generation/sounio-continuity.receipt" -type f -print
    )
    [[ ${#receipts[@]} -eq 1 ]]
    SOUNIO_COORD_RUNTIME_MODE=local \
      /state/sounio/bin/sounio-loom verify-continuity-receipt \
      --receipt "${receipts[0]}" \
      --public-key /var/run/sounio-loom-signing/public.pem \
      --adapter /state/sounio/tools/loom/_build/default/src/sounio-loom-continuity-runtime
  ' _ "$generation" > "$verification"
  grep -q '^LOOM_CONTINUITY_RECEIPT_VERIFIED schema=loom-native-continuity-receipt-v2 algorithm=ed25519 ' \
    "$verification" || \
    fail "public-key verification failed for exported receipt $label"
  grep -q " key_id=$SIGNER_KEY_ID " "$verification" || \
    fail "public-key verification used an unexpected signer for receipt $label"
  grep -q " receipt_sha256=$expected_digest " "$verification" || \
    fail "public-key verification reported an unexpected digest for receipt $label"
}

uid_one="$(pod_uid)"
node_one="$(pod_node)"
[[ "$node_one" == "$NODE_NAME" ]] || fail "initial Pod landed on unexpected node $node_one"
run_phase phase-one "$EVIDENCE_DIR/phase-one.txt"
uid_two="$(move_successor "$uid_one" "$SUCCESSOR_NODE")"
node_two="$(pod_node)"
run_phase phase-two "$EVIDENCE_DIR/phase-two.txt"
uid_three="$(wait_successor "$uid_two" "$SUCCESSOR_NODE")"
node_three="$(pod_node)"
run_phase phase-three "$EVIDENCE_DIR/phase-three.txt"
uid_four="$(wait_successor "$uid_three" "$SUCCESSOR_NODE")"
node_four="$(pod_node)"
run_phase phase-four "$EVIDENCE_DIR/phase-four.txt"

kubectl -n "$NAMESPACE" exec "$POD" -- \
  bash /state/sounio/scripts/ci/sounio_loom_pod_replay_canary.sh report \
  > "$EVIDENCE_DIR/result.txt"
grep -q '^SOUNIO_LOOM_SEPARATE_POD_REPLAY_PASS=true$' "$EVIDENCE_DIR/result.txt" || \
  fail 'final canary result did not pass'
grep -q '^signature_algorithm=ed25519$' "$EVIDENCE_DIR/result.txt" || \
  fail 'final canary result omitted Ed25519 authentication'
grep -q '^signed_predecessor_chain=verified$' "$EVIDENCE_DIR/result.txt" || \
  fail 'final canary result omitted the signed predecessor chain'
result_signer_key_id="$(sed -n 's/^signer_key_id=//p' "$EVIDENCE_DIR/result.txt")"
[[ "$result_signer_key_id" == "$SIGNER_KEY_ID" ]] || \
  fail 'canary signer identity does not match the generated public key'
for label in one two three four; do
  export_signed_receipt "$label" \
    "$(result_value "generation_$label")" \
    "$(result_value "native_sounio_receipt_${label}_sha256")"
done
[[ "$uid_one" != "$uid_two" && "$uid_one" != "$uid_three" && "$uid_one" != "$uid_four" && \
   "$uid_two" != "$uid_three" && "$uid_two" != "$uid_four" && \
   "$uid_three" != "$uid_four" ]] || \
  fail 'canary did not observe four distinct Kubernetes Pod UIDs'
[[ "$node_one" != "$node_two" && "$node_two" == "$node_three" && \
   "$node_three" == "$node_four" ]] || \
  fail 'canary did not preserve the declared cross-node transition and successors'

protected_after="$(kubectl -n "$NAMESPACE" get pod "$PROTECTED_POD" \
  -o jsonpath='{.metadata.uid} {.status.phase}')"
printf 'after=%s\n' "$protected_after" >> "$EVIDENCE_DIR/protected-workspace.txt"
[[ "$protected_after" == "$protected_before" ]] || \
  fail "protected workspace identity changed: before=$protected_before after=$protected_after"

cat > "$EVIDENCE_DIR/runner-receipt.txt" <<EOF
SOUNIO_LOOM_REAL_POD_CANARY_PASS=true
schema=beagle-sounio-loom-real-pod-canary-v3
beagle_source_commit=$BEAGLE_SOURCE_COMMIT
sounio_source_commit=$SOUNIO_SOURCE_COMMIT
namespace=$NAMESPACE
statefulset=$CANARY_NAME
pod_uid_one=$uid_one
pod_node_one=$node_one
pod_uid_two=$uid_two
pod_node_two=$node_two
pod_uid_three=$uid_three
pod_node_three=$node_three
pod_uid_four=$uid_four
pod_node_four=$node_four
cross_node_transition=$node_one->$node_two
signature_algorithm=ed25519
signer_key_id=$SIGNER_KEY_ID
signer_public_key_sha256=$SIGNER_KEY_ID
signed_receipt_bundle=4
public_receipt_verifications=4
signing_secret=$SIGNING_SECRET
protected_workspace=$PROTECTED_POD
protected_workspace_uid_phase=$protected_after
cleanup_requested=$((1 - KEEP))
EOF

printf 'SOUNIO_LOOM_REAL_POD_CANARY_PASS=true name=%s evidence=%s pod_uids=%s,%s,%s,%s nodes=%s,%s,%s,%s signer=%s\n' \
  "$CANARY_NAME" "$EVIDENCE_DIR" "$uid_one" "$uid_two" "$uid_three" \
  "$uid_four" "$node_one" "$node_two" "$node_three" "$node_four" \
  "$SIGNER_KEY_ID"
