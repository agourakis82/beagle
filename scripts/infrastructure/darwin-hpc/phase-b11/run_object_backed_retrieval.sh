#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
DARWIN_V2_ROOT=${DARWIN_V2_ROOT:-/root/darwin-v2}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b11"
RUN_ID=${RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/object-retrieval"
POLICY_FILE=${POLICY_FILE:-"${CONTRACT_ROOT}/object-retrieval-policy.yaml"}
RGW_TARGET_ENV=${RGW_TARGET_ENV:-"${DOC_ROOT}/contracts/rgw-artifact-target.env"}
ADAPTER_SOURCE=${ADAPTER_SOURCE:-"${DARWIN_V2_ROOT}/phase-b11/manifests/darwin-hpc-gateway/adapter.py"}
REMOTE_HOST=${REMOTE_HOST:-t560-proxmox}
REMOTE_USER=${REMOTE_USER:-root}
GATEWAY_NAMESPACE=${GATEWAY_NAMESPACE:-darwin-platform}
GATEWAY_SERVICE=${GATEWAY_SERVICE:-darwin-hpc-gateway}
LOCAL_PORT=${LOCAL_PORT:-18081}

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

resolve_kubeconfig() {
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    printf '%s\n' /etc/kubernetes/admin.conf
    return 0
  fi
  if [[ -n "${KUBECONFIG:-}" && -f "${KUBECONFIG}" ]]; then
    printf '%s\n' "${KUBECONFIG}"
    return 0
  fi
  if [[ -f /root/.kube/config ]]; then
    printf '%s\n' /root/.kube/config
    return 0
  fi
  return 1
}

remote_known_hosts() {
  local host=$1
  local file="/etc/pve/nodes/${host}/ssh_known_hosts"
  if [[ -f "${file}" ]]; then
    printf '%s\n' "${file}"
  fi
}

remote_ssh() {
  local host=$1
  shift
  local known_hosts_file
  known_hosts_file=$(remote_known_hosts "${host}")
  local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)

  if [[ -n "${known_hosts_file}" ]]; then
    ssh_opts+=(-o StrictHostKeyChecking=yes -o UserKnownHostsFile="${known_hosts_file}")
  else
    ssh_opts+=(-o StrictHostKeyChecking=accept-new)
  fi

  ssh "${ssh_opts[@]}" "${REMOTE_USER}@${host}" "$@"
}

ensure_green_cluster() {
  local node
  for node in t560-proxmox r770-proxmox 5860-proxmox; do
    local ready
    ready=$(kubectl get node "${node}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')
    [[ "${ready}" == "True" ]] || {
      echo "node not Ready: ${node}" >&2
      exit 1
    }
  done
}

wait_for_gateway() {
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

perform_request() {
  local path=$1
  local body_path=$2
  local headers_path=$3
  curl -sS -D "${headers_path}" -o "${body_path}" -w '%{http_code}' "http://127.0.0.1:${LOCAL_PORT}${path}"
}

collect_final_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## kubernetes-nodes"
    kubectl get nodes -o wide || true
    echo
    echo "## gateway"
    kubectl -n "${GATEWAY_NAMESPACE}" get deploy,svc,pods -l app.kubernetes.io/name="${GATEWAY_SERVICE}" -o wide || true
    echo
    if command -v cilium >/dev/null 2>&1; then
      echo "## cilium"
      cilium status --wait --wait-duration=30s || true
      echo
    fi
    echo "## slurm-units"
    for unit in slurmctld slurmrestd munge darwin-slurm-control-adapter; do
      printf '%s=%s\n' "${unit}" "$(systemctl is-active "${unit}" 2>/dev/null || true)"
    done
    echo "active-scheduler=slurm-pilot"
    echo "legacy-adapter-mode=legacy-catalog-only"
    echo
    echo "## slurm-pilot"
    kubectl -n slurm-pilot get pods,svc -o wide || true
    echo
    if command -v scontrol >/dev/null 2>&1; then
      echo "## scontrol-ping"
      scontrol ping || true
      echo
    fi
    if command -v sinfo >/dev/null 2>&1; then
      echo "## slurm-sinfo"
      sinfo -N -l || true
      echo
    fi
  } > "${RESULT_DIR}/final-cluster-health.txt"
}

main() {
  require_cmd kubectl
  require_cmd python3
  require_cmd curl
  require_cmd ssh

  [[ -f "${POLICY_FILE}" && -s "${POLICY_FILE}" ]] || {
    echo "missing policy file: ${POLICY_FILE}" >&2
    exit 1
  }
  [[ -f "${RGW_TARGET_ENV}" && -s "${RGW_TARGET_ENV}" ]] || {
    echo "missing RGW target env: ${RGW_TARGET_ENV}" >&2
    exit 1
  }
  [[ -f "${ADAPTER_SOURCE}" && -s "${ADAPTER_SOURCE}" ]] || {
    echo "missing adapter source: ${ADAPTER_SOURCE}" >&2
    exit 1
  }

  export KUBECONFIG
  KUBECONFIG=$(resolve_kubeconfig) || {
    echo "no usable kubeconfig found" >&2
    exit 1
  }

  mkdir -p "${RESULT_DIR}"
  ensure_green_cluster

  local adapter_b64 object_env_b64
  adapter_b64=$(python3 - <<'PY' "${ADAPTER_SOURCE}"
import base64
import pathlib
import sys
print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
)
  object_env_b64=$(python3 - <<'PY' "${RGW_TARGET_ENV}"
import base64
import pathlib
import sys
print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
)

  remote_ssh "${REMOTE_HOST}" \
    "ADAPTER_B64='${adapter_b64}' OBJECT_ENV_B64='${object_env_b64}' RUN_ID='${RUN_ID}' ADAPTER_BIND_HOST='192.168.3.169' ADAPTER_BIND_PORT='6830' bash -s" <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y python3-boto3 python3-botocore >/dev/null
install -d -m 0755 /usr/local/lib/darwin-hpc-gateway
install -d -m 0755 /etc/darwin-hpc-gateway
install -d -m 0700 "/root/b111-${RUN_ID}"
if [[ -f /usr/local/lib/darwin-hpc-gateway/adapter.py ]]; then
  cp -a /usr/local/lib/darwin-hpc-gateway/adapter.py "/root/b111-${RUN_ID}/adapter.py.before"
fi
python3 - <<'PY'
import base64
import os
import pathlib

adapter_path = pathlib.Path("/usr/local/lib/darwin-hpc-gateway/adapter.py")
adapter_path.write_bytes(base64.b64decode(os.environ["ADAPTER_B64"]))
adapter_path.chmod(0o755)

env_path = pathlib.Path("/etc/darwin-hpc-gateway/object-store.env")
env_path.write_bytes(base64.b64decode(os.environ["OBJECT_ENV_B64"]))
env_path.chmod(0o600)
PY
systemctl restart darwin-slurm-control-adapter
systemctl is-active darwin-slurm-control-adapter
for _ in $(seq 1 20); do
  if curl -fsS "http://${ADAPTER_BIND_HOST}:${ADAPTER_BIND_PORT}/healthz" >/dev/null; then
    exit 0
  fi
  sleep 1
done
exit 1
EOF

  kubectl -n "${GATEWAY_NAMESPACE}" get deploy "${GATEWAY_SERVICE}" >/dev/null
  local pf_log="${RESULT_DIR}/port-forward.log"
  pf_pid=""
  kubectl -n "${GATEWAY_NAMESPACE}" port-forward service/"${GATEWAY_SERVICE}" "${LOCAL_PORT}:80" >"${pf_log}" 2>&1 &
  pf_pid=$!
  cleanup() {
    local pid="${pf_pid:-}"
    if [[ -n "${pid}" ]]; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup EXIT

  wait_for_gateway || {
    echo "gateway did not become reachable through port-forward" >&2
    exit 1
  }

  export RGW_TARGET_ENV RESULT_DIR POLICY_FILE
  python3 - <<'PY' > "${RESULT_DIR}/retrieval-targets.json"
import json
import os
import re
from pathlib import Path

import boto3
import yaml

env = {}
for line in Path(os.environ["RGW_TARGET_ENV"]).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    env[key] = value

policy = yaml.safe_load(Path(os.environ["POLICY_FILE"]).read_text())
s3 = boto3.client(
    "s3",
    endpoint_url=env["RGW_ENDPOINT"],
    aws_access_key_id=env["RGW_ACCESS_KEY"],
    aws_secret_access_key=env["RGW_SECRET_KEY"],
    region_name="us-east-1",
)

result = {}
pattern = re.compile(r"^hpc/(?P<profile>[^/]+)/(?P<job_id>\d+)/(?P<run_label>[^/]+)/artifact-manifest\.json$")
for profile in policy["profiles"]:
    best = None
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=env["RGW_BUCKET"], Prefix=f"hpc/{profile}/"):
        for item in page.get("Contents", []):
            match = pattern.match(item["Key"])
            if not match:
                continue
            candidate = {
                "profile_id": profile,
                "job_id": int(match.group("job_id")),
                "run_label": match.group("run_label"),
                "manifest_object_key": item["Key"],
                "last_modified": item["LastModified"].astimezone().isoformat(),
            }
            if best is None or item["LastModified"] > best["raw_last_modified"]:
                candidate["raw_last_modified"] = item["LastModified"]
                best = candidate
    if best is None:
        raise SystemExit(f"no published manifest found for profile {profile}")
    best.pop("raw_last_modified", None)
    result[profile] = best

print(json.dumps(result, indent=2, sort_keys=True))
PY

  retrieve_profile() {
    local profile_id=$1
    local output_prefix=$2
    local tmpdir
    tmpdir=$(mktemp -d)
    local job_id
    job_id=$(python3 - <<'PY' "${RESULT_DIR}/retrieval-targets.json" "${profile_id}"
import json
import sys
targets = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(targets[sys.argv[2]]["job_id"])
PY
)

    local status_code manifest_code artifact_code stdout_code stderr_code
    status_code=$(perform_request "/jobs/${job_id}" "${tmpdir}/status.body" "${tmpdir}/status.headers")
    manifest_code=$(perform_request "/jobs/${job_id}/artifact-manifest" "${tmpdir}/manifest.body" "${tmpdir}/manifest.headers")
    artifact_code=$(perform_request "/jobs/${job_id}/artifact" "${tmpdir}/artifact.body" "${tmpdir}/artifact.headers")
    stdout_code=$(perform_request "/jobs/${job_id}/stdout" "${tmpdir}/stdout.body" "${tmpdir}/stdout.headers")
    stderr_code=$(perform_request "/jobs/${job_id}/stderr" "${tmpdir}/stderr.body" "${tmpdir}/stderr.headers")

    python3 - <<'PY' \
      "${profile_id}" \
      "${job_id}" \
      "${status_code}" \
      "${manifest_code}" \
      "${artifact_code}" \
      "${stdout_code}" \
      "${stderr_code}" \
      "${tmpdir}/status.body" \
      "${tmpdir}/manifest.body" \
      "${tmpdir}/artifact.body" \
      "${tmpdir}/artifact.headers" \
      "${tmpdir}/stdout.body" \
      "${tmpdir}/stderr.body" \
      > "${RESULT_DIR}/${output_prefix}-retrieval.txt"
import hashlib
import json
import pathlib
import sys

profile_id, job_id = sys.argv[1], int(sys.argv[2])
status_code, manifest_code, artifact_code, stdout_code, stderr_code = [int(v) for v in sys.argv[3:8]]
status_path = pathlib.Path(sys.argv[8])
manifest_path = pathlib.Path(sys.argv[9])
artifact_path = pathlib.Path(sys.argv[10])
artifact_headers_path = pathlib.Path(sys.argv[11])
stdout_path = pathlib.Path(sys.argv[12])
stderr_path = pathlib.Path(sys.argv[13])

status_body = json.loads(status_path.read_text(encoding="utf-8"))
manifest_body = json.loads(manifest_path.read_text(encoding="utf-8"))
artifact_bytes = artifact_path.read_bytes()
stdout_bytes = stdout_path.read_bytes()
stderr_bytes = stderr_path.read_bytes()

content_type = ""
for line in artifact_headers_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if line.lower().startswith("content-type:"):
        content_type = line.split(":", 1)[1].strip()
        break

payload = {
    "profile_id": profile_id,
    "job_id": job_id,
    "job_summary_http_status": status_code,
    "job_summary": status_body,
    "artifact_manifest_http_status": manifest_code,
    "artifact_manifest": manifest_body,
    "artifact_http_status": artifact_code,
    "artifact_content_type": content_type,
    "artifact_sha256": hashlib.sha256(artifact_bytes).hexdigest(),
    "artifact_size": len(artifact_bytes),
    "stdout_http_status": stdout_code,
    "stdout_sha256": hashlib.sha256(stdout_bytes).hexdigest(),
    "stdout_text": stdout_bytes.decode("utf-8", errors="replace"),
    "stderr_http_status": stderr_code,
    "stderr_sha256": hashlib.sha256(stderr_bytes).hexdigest(),
    "stderr_text": stderr_bytes.decode("utf-8", errors="replace"),
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY

    rm -rf "${tmpdir}"
  }

  retrieve_profile "cpu-short-v1" "cpu-short"
  retrieve_profile "cpu-batch-v1" "cpu-batch"
  retrieve_profile "gpu-single-v1" "gpu"

  collect_final_health

  python3 - <<'PY' "${RESULT_DIR}"
import json
import pathlib
import sys

result_dir = pathlib.Path(sys.argv[1])
profiles = {
    "cpu-short": "cpu-short-v1",
    "cpu-batch": "cpu-batch-v1",
    "gpu": "gpu-single-v1",
}
lines = [
    "# B11.1 Object-backed Retrieval Result",
    "",
    "## Status",
    "GO",
    "",
    "## Decision",
    "the lab-facing gateway now resolves canonical published artifacts from the object plane as the primary retrieval path.",
    "",
    "## Profiles",
]
for prefix, profile_id in profiles.items():
    payload = json.loads((result_dir / f"{prefix}-retrieval.txt").read_text(encoding="utf-8"))
    manifest = payload["artifact_manifest"]
    lines.append(
        f"- {profile_id}: job_id={payload['job_id']}, source={payload['job_summary'].get('artifact_source', 'missing')}, manifest_key={manifest.get('manifest_object_key', 'missing')}"
    )
(result_dir / "B111_RESULT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

main "$@"
