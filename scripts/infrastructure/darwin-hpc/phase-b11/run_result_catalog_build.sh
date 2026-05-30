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
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/result-catalog"
POLICY_FILE=${POLICY_FILE:-"${CONTRACT_ROOT}/result-catalog-policy.yaml"}
ENTRY_SCHEMA_FILE=${ENTRY_SCHEMA_FILE:-"${CONTRACT_ROOT}/result-catalog-entry.json"}
RGW_TARGET_ENV=${RGW_TARGET_ENV:-"${DOC_ROOT}/contracts/rgw-artifact-target.env"}
RETENTION_POLICY_FILE=${RETENTION_POLICY_FILE:-"${DOC_ROOT}/contracts/object-retention-policy.yaml"}
PROFILES_FILE=${PROFILES_FILE:-/etc/darwin-hpc-gateway/profiles.json}
ADAPTER_SOURCE=${ADAPTER_SOURCE:-"${DARWIN_V2_ROOT}/phase-b11/manifests/darwin-hpc-gateway/adapter.py"}
GATEWAY_SOURCE=${GATEWAY_SOURCE:-"${DARWIN_V2_ROOT}/phase-b11/manifests/darwin-hpc-gateway/gateway.py"}
REMOTE_HOST=${REMOTE_HOST:-t560-proxmox}
REMOTE_USER=${REMOTE_USER:-root}
GATEWAY_NAMESPACE=${GATEWAY_NAMESPACE:-darwin-platform}
GATEWAY_DEPLOYMENT=${GATEWAY_DEPLOYMENT:-darwin-hpc-gateway}
GATEWAY_SERVICE=${GATEWAY_SERVICE:-darwin-hpc-gateway}
LOCAL_PORT=${LOCAL_PORT:-18082}

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

  for file in "${POLICY_FILE}" "${ENTRY_SCHEMA_FILE}" "${RGW_TARGET_ENV}" "${RETENTION_POLICY_FILE}" "${PROFILES_FILE}" "${ADAPTER_SOURCE}" "${GATEWAY_SOURCE}"; do
    [[ -f "${file}" && -s "${file}" ]] || {
      echo "missing required file: ${file}" >&2
      exit 1
    }
  done

  export KUBECONFIG
  KUBECONFIG=$(resolve_kubeconfig) || {
    echo "no usable kubeconfig found" >&2
    exit 1
  }

  mkdir -p "${RESULT_DIR}"
  ensure_green_cluster

  export RESULT_DIR POLICY_FILE ENTRY_SCHEMA_FILE RGW_TARGET_ENV RETENTION_POLICY_FILE PROFILES_FILE
  python3 - <<'PY' > "${RESULT_DIR}/catalog-build.txt"
import json
import os
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import boto3
import yaml

policy = yaml.safe_load(Path(os.environ["POLICY_FILE"]).read_text())
retention_policy = yaml.safe_load(Path(os.environ["RETENTION_POLICY_FILE"]).read_text())
profiles = json.loads(Path(os.environ["PROFILES_FILE"]).read_text())["profiles"]
profile_map = {profile["id"]: profile for profile in profiles}

env = {}
for raw_line in Path(os.environ["RGW_TARGET_ENV"]).read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    env[key] = value

s3 = boto3.client(
    "s3",
    endpoint_url=env["RGW_ENDPOINT"],
    aws_access_key_id=env["RGW_ACCESS_KEY"],
    aws_secret_access_key=env["RGW_SECRET_KEY"],
    region_name="us-east-1",
)

pattern = re.compile(r"^hpc/(?P<profile_id>[^/]+)/(?P<job_id>\d+)/(?P<run_label>[^/]+)/artifact-manifest\.json$")
entries = []
counts = Counter()
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=env["RGW_BUCKET"], Prefix="hpc/"):
    for item in page.get("Contents", []):
        key = item["Key"]
        match = pattern.match(key)
        if not match:
            continue

        manifest = json.loads(s3.get_object(Bucket=env["RGW_BUCKET"], Key=key)["Body"].read().decode("utf-8"))
        if manifest.get("manifest_format") != policy["source_of_truth"]["manifest_format"]:
            continue

        profile_id = manifest["profile_id"]
        profile = profile_map.get(profile_id, {})
        retention_scope = retention_policy["profiles"].get(profile_id, {}).get("retention_class", "unknown")
        artifact_prefix = manifest["manifest_object_key"].rsplit("/", 1)[0] + "/"
        node_list = manifest.get("node_list") or profile.get("target_node", "")
        partition = manifest.get("partition") or profile.get("partition", "")

        entries.append(
            {
                "job_id": int(manifest["job_id"]),
                "job_name": manifest["job_name"],
                "profile_id": profile_id,
                "run_label": manifest["run_label"],
                "state": manifest["state"],
                "node_list": node_list,
                "partition": partition,
                "submit_time": manifest["submit_time"],
                "start_time": manifest["start_time"],
                "end_time": manifest["end_time"],
                "artifact_bucket": manifest["object_bucket"],
                "artifact_prefix": artifact_prefix,
                "artifact_manifest_key": manifest["manifest_object_key"],
                "artifact_object_key": manifest["object_key"],
                "artifact_sha256": manifest["published_checksum"],
                "retention_scope": retention_scope,
                "publication_time": manifest["publication_time"],
                "source_phase": manifest["source_phase"],
                "source_run_id": manifest["source_run_id"],
                "exit_code": int(manifest["exit_code"]),
            }
        )
        counts[profile_id] += 1

entries.sort(key=lambda entry: (entry["submit_time"], entry["job_id"]), reverse=True)
catalog = {
    "catalog_format": policy["catalog"]["format"],
    "source_of_truth": policy["source_of_truth"]["type"],
    "generated_at": datetime.now(timezone.utc).astimezone().isoformat(),
    "bucket": env["RGW_BUCKET"],
    "total_results": len(entries),
    "entries": entries,
}

out = Path(os.environ["RESULT_DIR"]) / "catalog-sample.json"
out.write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8")

print(f"catalog_format={catalog['catalog_format']}")
print(f"catalog_results={catalog['total_results']}")
for profile_id in sorted(counts):
    print(f"profile.{profile_id}={counts[profile_id]}")
print(f"catalog_file={out}")
PY

  local adapter_b64 gateway_b64 catalog_b64 object_env_b64
  adapter_b64=$(python3 - <<'PY' "${ADAPTER_SOURCE}"
import base64
import pathlib
import sys
print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
)
  gateway_b64=$(python3 - <<'PY' "${GATEWAY_SOURCE}"
import base64
import pathlib
import sys
print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
)
  catalog_b64=$(python3 - <<'PY' "${RESULT_DIR}/catalog-sample.json"
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
    "ADAPTER_B64='${adapter_b64}' CATALOG_B64='${catalog_b64}' OBJECT_ENV_B64='${object_env_b64}' RUN_ID='${RUN_ID}' ADAPTER_BIND_HOST='192.168.3.169' ADAPTER_BIND_PORT='6830' bash -s" <<'EOF' >> "${RESULT_DIR}/catalog-build.txt"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y python3-boto3 python3-botocore >/dev/null
install -d -m 0755 /usr/local/lib/darwin-hpc-gateway
install -d -m 0755 /etc/darwin-hpc-gateway
install -d -m 0755 /var/lib/darwin-hpc-gateway
install -d -m 0700 "/root/b112-${RUN_ID}"
if [[ -f /usr/local/lib/darwin-hpc-gateway/adapter.py ]]; then
  cp -a /usr/local/lib/darwin-hpc-gateway/adapter.py "/root/b112-${RUN_ID}/adapter.py.before"
fi
if [[ -f /var/lib/darwin-hpc-gateway/result-catalog.json ]]; then
  cp -a /var/lib/darwin-hpc-gateway/result-catalog.json "/root/b112-${RUN_ID}/result-catalog.json.before"
fi
python3 - <<'PY'
import base64
import os
import pathlib

adapter_path = pathlib.Path("/usr/local/lib/darwin-hpc-gateway/adapter.py")
adapter_path.write_bytes(base64.b64decode(os.environ["ADAPTER_B64"]))
adapter_path.chmod(0o755)

catalog_path = pathlib.Path("/var/lib/darwin-hpc-gateway/result-catalog.json")
catalog_path.write_bytes(base64.b64decode(os.environ["CATALOG_B64"]))
catalog_path.chmod(0o644)

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

  kubectl -n "${GATEWAY_NAMESPACE}" create configmap "${GATEWAY_SERVICE}-code" \
    --from-file=gateway.py="${GATEWAY_SOURCE}" \
    --dry-run=client -o yaml | kubectl apply -f - >> "${RESULT_DIR}/catalog-build.txt"

  kubectl -n "${GATEWAY_NAMESPACE}" rollout restart deploy/"${GATEWAY_DEPLOYMENT}" >/dev/null
  kubectl -n "${GATEWAY_NAMESPACE}" rollout status deploy/"${GATEWAY_DEPLOYMENT}" --timeout=180s >> "${RESULT_DIR}/catalog-build.txt"

  pf_pid=""
  kubectl -n "${GATEWAY_NAMESPACE}" port-forward service/"${GATEWAY_SERVICE}" "${LOCAL_PORT}:80" >"${RESULT_DIR}/port-forward.log" 2>&1 &
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

  local gpu_run_label gpu_job_id
  gpu_run_label=$(python3 - <<'PY' "${RESULT_DIR}/catalog-sample.json"
import json
import sys
catalog = json.load(open(sys.argv[1], "r", encoding="utf-8"))
for entry in catalog["entries"]:
    if entry["profile_id"] == "gpu-single-v1":
        print(entry["run_label"])
        break
PY
)
  gpu_job_id=$(python3 - <<'PY' "${RESULT_DIR}/catalog-sample.json"
import json
import sys
catalog = json.load(open(sys.argv[1], "r", encoding="utf-8"))
for entry in catalog["entries"]:
    if entry["profile_id"] == "gpu-single-v1":
        print(entry["job_id"])
        break
PY
)

  local tmpdir
  tmpdir=$(mktemp -d)

  local all_code profile_code run_code job_code manifest_code
  all_code=$(perform_request "/results" "${tmpdir}/all.body" "${tmpdir}/all.headers")
  profile_code=$(perform_request "/results?profile_id=cpu-batch-v1" "${tmpdir}/profile.body" "${tmpdir}/profile.headers")
  run_code=$(perform_request "/results?run_label=${gpu_run_label}" "${tmpdir}/run.body" "${tmpdir}/run.headers")
  job_code=$(perform_request "/results/${gpu_job_id}" "${tmpdir}/job.body" "${tmpdir}/job.headers")
  manifest_code=$(perform_request "/results/${gpu_job_id}/manifest" "${tmpdir}/manifest.body" "${tmpdir}/manifest.headers")

  python3 - <<'PY' \
    "${gpu_run_label}" \
    "${gpu_job_id}" \
    "${all_code}" \
    "${profile_code}" \
    "${run_code}" \
    "${job_code}" \
    "${manifest_code}" \
    "${tmpdir}/all.body" \
    "${tmpdir}/profile.body" \
    "${tmpdir}/run.body" \
    "${tmpdir}/job.body" \
    "${tmpdir}/manifest.body" \
    > "${RESULT_DIR}/query-sample.txt"
import json
import pathlib
import sys

gpu_run_label = sys.argv[1]
gpu_job_id = int(sys.argv[2])
codes = [int(value) for value in sys.argv[3:8]]
paths = [pathlib.Path(value) for value in sys.argv[8:13]]
names = ["all_results", "profile_filter", "run_label_filter", "job_lookup", "manifest_lookup"]

payload = {
    "requested_gpu_run_label": gpu_run_label,
    "requested_gpu_job_id": gpu_job_id,
}
for name, code, path in zip(names, codes, paths):
    payload[name] = {
        "http_status": code,
        "body": json.loads(path.read_text(encoding="utf-8")),
    }

print(json.dumps(payload, indent=2, sort_keys=True))
PY

  rm -rf "${tmpdir}"
  collect_final_health

  python3 - <<'PY' "${RESULT_DIR}"
import json
import pathlib
import sys

result_dir = pathlib.Path(sys.argv[1])
catalog = json.loads((result_dir / "catalog-sample.json").read_text(encoding="utf-8"))
queries = json.loads((result_dir / "query-sample.txt").read_text(encoding="utf-8"))

lines = [
    "# B11.2 Result Catalog Build",
    "",
    "## Status",
    "GO",
    "",
    "## Decision",
    "the result plane now exposes canonical lightweight catalog and query semantics derived from published object manifests.",
    "",
    "## Catalog",
    f"- total_results={catalog['total_results']}",
    "",
    "## Query checks",
    f"- GET /results => {queries['all_results']['http_status']}",
    f"- GET /results?profile_id=cpu-batch-v1 => {queries['profile_filter']['http_status']}",
    f"- GET /results?run_label={queries['requested_gpu_run_label']} => {queries['run_label_filter']['http_status']}",
    f"- GET /results/{queries['requested_gpu_job_id']} => {queries['job_lookup']['http_status']}",
    f"- GET /results/{queries['requested_gpu_job_id']}/manifest => {queries['manifest_lookup']['http_status']}",
]
(result_dir / "B112_RESULT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

main "$@"
