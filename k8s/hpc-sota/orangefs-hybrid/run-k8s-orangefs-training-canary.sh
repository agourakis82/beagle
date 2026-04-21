#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:-Urso1982!}"
T560=root@10.100.100.2
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf
MANIFEST="$BASE/k8s/jobset-ddp-training-canary-orangefs.yaml"
JOBSET="orangefs-train"
NAMESPACE="beagle"
WRITE_DATASET="${WRITE_DATASET:-1}"
WRITE_CHECKPOINT="${WRITE_CHECKPOINT:-1}"
WRITE_SCRATCH="${WRITE_SCRATCH:-1}"
SCRATCH_MB="${SCRATCH_MB:-16}"
SERIALIZE_ARTIFACT_WRITES="${SERIALIZE_ARTIFACT_WRITES:-1}"
INIT_METHOD_MODE="${INIT_METHOD_MODE:-tcp}"
FORCE_BACKEND="${FORCE_BACKEND:-}"
DIST_TIMEOUT_SECONDS="${DIST_TIMEOUT_SECONDS:-90}"
RUN_ID="${RUN_ID:-$(date +%s)}"
LAUNCHER_MODE="${LAUNCHER_MODE:-manual}"
TMP_MANIFEST="$(mktemp)"

cleanup() {
  rm -f "$TMP_MANIFEST"
}
trap cleanup EXIT

remote_k() {
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl $*"
}

echo "[1/4] label OrangeFS client nodes"
remote_k "label node r740-proxmox sounio.dev/orangefs-client=true --overwrite"
remote_k "label node r770-proxmox sounio.dev/orangefs-client=true --overwrite"

echo "[2/4] clear previous JobSet if present"
remote_k "-n $NAMESPACE delete jobset $JOBSET --ignore-not-found=true"
remote_k "-n $NAMESPACE delete pod -l jobset.sigs.k8s.io/jobset-name=$JOBSET --ignore-not-found=true --force --grace-period=0" || true
sleep 5

echo "[3/4] apply OrangeFS training canary"
python3 - "$MANIFEST" "$TMP_MANIFEST" "$WRITE_DATASET" "$WRITE_CHECKPOINT" "$WRITE_SCRATCH" "$SCRATCH_MB" "$SERIALIZE_ARTIFACT_WRITES" "$INIT_METHOD_MODE" "$FORCE_BACKEND" "$DIST_TIMEOUT_SECONDS" "$RUN_ID" "$LAUNCHER_MODE" <<'PY'
import sys
import yaml

(
    src,
    dst,
    write_dataset,
    write_checkpoint,
    write_scratch,
    scratch_mb,
    serialize_artifact_writes,
    init_method_mode,
    force_backend,
    dist_timeout_seconds,
    run_id,
    launcher_mode,
) = sys.argv[1:]
with open(src, "r", encoding="utf-8") as fh:
    docs = list(yaml.safe_load_all(fh))

jobset = None
for doc in docs:
    if doc and doc.get("kind") == "JobSet":
        jobset = doc
        break

if jobset is None:
    raise SystemExit("JobSet document not found in manifest")

mapping = {
    "WRITE_DATASET": write_dataset,
    "WRITE_CHECKPOINT": write_checkpoint,
    "WRITE_SCRATCH": write_scratch,
    "SCRATCH_MB": scratch_mb,
    "SERIALIZE_ARTIFACT_WRITES": serialize_artifact_writes,
    "INIT_METHOD_MODE": init_method_mode,
    "FORCE_BACKEND": force_backend,
    "DIST_TIMEOUT_SECONDS": dist_timeout_seconds,
    "RUN_ID": run_id,
}
for replicated_job in jobset["spec"]["replicatedJobs"]:
    container = replicated_job["template"]["spec"]["template"]["spec"]["containers"][0]
    env = container["env"]
    for item in env:
        name = item.get("name")
        if name in mapping:
            item["value"] = str(mapping[name])

    if launcher_mode == "torchrun":
        for item in env:
            if item.get("name") == "INIT_METHOD_MODE":
                item["value"] = "torchrun"
        container["command"] = [
        "/bin/bash",
        "-lc",
        "set -euo pipefail\n"
        "RDZV_DNS=${MASTER_HOST}\n"
        "RDZV_PORT=${MASTER_PORT}\n"
        "export RDZV_DNS RDZV_PORT POD_NAMESPACE JOBSET_SUBDOMAIN\n"
        "RDZV_HOST=$(python - <<'PY'\n"
        "import os, socket, time\n"
        "host = os.environ['RDZV_DNS']\n"
        "port = int(os.environ['RDZV_PORT'])\n"
        "namespace = os.environ['POD_NAMESPACE']\n"
        "subdomain = os.environ['JOBSET_SUBDOMAIN']\n"
        "candidates = []\n"
        "def add(candidate):\n"
        "    if candidate and candidate not in candidates:\n"
        "        candidates.append(candidate)\n"
        "add(host)\n"
        "if host.endswith(f'.{subdomain}'):\n"
        "    add(f'{host}.{namespace}.svc')\n"
        "    add(f'{host}.{namespace}.svc.cluster.local')\n"
        "elif '.' not in host:\n"
        "    add(f'{host}.{subdomain}')\n"
        "    add(f'{host}.{subdomain}.{namespace}.svc')\n"
        "    add(f'{host}.{subdomain}.{namespace}.svc.cluster.local')\n"
        "    add(f'{host}.{namespace}.svc')\n"
        "    add(f'{host}.{namespace}.svc.cluster.local')\n"
        "deadline = time.time() + 90\n"
        "last_error = None\n"
        "while time.time() < deadline:\n"
        "    for candidate in candidates:\n"
        "        try:\n"
        "            infos = socket.getaddrinfo(candidate, port, family=socket.AF_INET, type=socket.SOCK_STREAM)\n"
        "            ip = infos[0][4][0]\n"
        "            print(ip)\n"
        "            raise SystemExit(0)\n"
        "        except OSError as exc:\n"
        "            last_error = exc\n"
        "    time.sleep(1)\n"
        "raise SystemExit(f'rdzv DNS host={host} candidates={candidates} port={port} not resolvable: {last_error}')\n"
        "PY\n"
        ")\n"
        "export RDZV_DNS RDZV_HOST RDZV_PORT\n"
        "torchrun --nnodes=2 --nproc-per-node=1 "
        "--node-rank=${NODE_RANK} "
        "--rdzv-id=${RUN_ID} "
        "--rdzv-backend=c10d "
        "--rdzv-endpoint=${RDZV_HOST}:${RDZV_PORT} "
        "/config/train_canary.py\n",
        ]

with open(dst, "w", encoding="utf-8") as fh:
    yaml.safe_dump_all(docs, fh, sort_keys=False)
PY
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$TMP_MANIFEST" "$T560:/tmp/jobset-ddp-training-canary-orangefs.yaml" >/dev/null
remote_k "apply -f /tmp/jobset-ddp-training-canary-orangefs.yaml"

echo "[4/4] current status"
remote_k "-n $NAMESPACE get jobset $JOBSET -o wide"
remote_k "-n $NAMESPACE get pods -o wide | egrep '$JOBSET|NAME' || true"

echo "Use these follow-ups:"
echo "  KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n $NAMESPACE get pods -o wide | grep $JOBSET"
echo "  KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n $NAMESPACE logs <pod-name>"
