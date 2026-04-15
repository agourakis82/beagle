#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_ID=${RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/retention-enforcement"
RGW_TARGET_ENV=${RGW_TARGET_ENV:-"${CONTRACT_ROOT}/rgw-artifact-target.env"}
RETENTION_POLICY=${RETENTION_POLICY:-"${CONTRACT_ROOT}/object-retention-policy.yaml"}

readonly SCRIPT_DIR REPO_ROOT DOC_ROOT CONTRACT_ROOT ARTIFACT_ROOT PHASE_ROOT RESULT_DIR

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

ensure_python_dep() {
  if python3 - <<'PY' >/dev/null 2>&1
import importlib.util
import sys
mods = ("boto3", "botocore", "yaml")
sys.exit(0 if all(importlib.util.find_spec(name) for name in mods) else 1)
PY
  then
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y python3-boto3 python3-botocore python3-yaml >/dev/null
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

collect_final_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## kubernetes-nodes"
    kubectl get nodes -o wide || true
    echo
    if command -v cilium >/dev/null 2>&1; then
      echo "## cilium"
      cilium status --wait --wait-duration=30s || true
      echo
    fi
    echo "## slurm-units"
    for unit in slurmctld slurmrestd munge; do
      printf '%s=%s\n' "${unit}" "$(systemctl is-active "${unit}" 2>/dev/null || true)"
    done
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

  [[ -f "${RGW_TARGET_ENV}" && -s "${RGW_TARGET_ENV}" ]] || {
    echo "missing RGW target env: ${RGW_TARGET_ENV}" >&2
    exit 1
  }
  [[ -f "${RETENTION_POLICY}" && -s "${RETENTION_POLICY}" ]] || {
    echo "missing retention policy: ${RETENTION_POLICY}" >&2
    exit 1
  }

  export KUBECONFIG
  KUBECONFIG=$(resolve_kubeconfig) || {
    echo "no usable kubeconfig found" >&2
    exit 1
  }

  mkdir -p "${RESULT_DIR}"
  ensure_green_cluster
  ensure_python_dep

  set -a
  source "${RGW_TARGET_ENV}"
  set +a

  export RGW_ENDPOINT RGW_BUCKET RGW_ACCESS_KEY RGW_SECRET_KEY RGW_VELERO_BUCKET
  export RETENTION_POLICY RESULT_DIR RUN_ID

  [[ "${RGW_BUCKET}" != "${RGW_VELERO_BUCKET}" ]] || {
    echo "enforcement bucket must not match Velero bucket" >&2
    exit 1
  }

  python3 - <<'PY'
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import boto3
import botocore
import yaml

policy = yaml.safe_load(Path(os.environ["RETENTION_POLICY"]).read_text())
result_dir = Path(os.environ["RESULT_DIR"])
run_id = os.environ["RUN_ID"]

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["RGW_ENDPOINT"],
    aws_access_key_id=os.environ["RGW_ACCESS_KEY"],
    aws_secret_access_key=os.environ["RGW_SECRET_KEY"],
    region_name="us-east-1",
)

bucket = os.environ["RGW_BUCKET"]
production_prefix = policy["enforcement_canary"]["production_prefix_guard"]
canary_root = policy["enforcement_canary"]["prefix"]
profile_id = policy["enforcement_canary"]["profile_id"]
job_id = int(policy["enforcement_canary"]["job_id"])
required_object_names = list(policy["enforcement_canary"]["required_object_names"])

run_label = f"b104-{run_id}"
canary_prefix = f"{canary_root}{profile_id}/{job_id}/{run_label}/"
publication_time = datetime.now(timezone.utc).astimezone().isoformat()

production_objects_before = []
paginator = s3.get_paginator("list_objects_v2")
for page in paginator.paginate(Bucket=bucket, Prefix=production_prefix):
    production_objects_before.extend(item["Key"] for item in page.get("Contents", []))

if not production_objects_before:
    raise SystemExit("no production objects found under hpc/ to protect during the canary")

profiles = {}
for key in production_objects_before:
    parts = key.split("/")
    if len(parts) < 5:
        continue
    if parts[0] != "hpc":
        continue
    if parts[-1] != "artifact-manifest.json":
        continue
    profiles[parts[1]] = key

if not profiles:
    raise SystemExit("no production manifest objects found for preservation checks")

preserved_keys = [profiles[profile] for profile in sorted(profiles)]

artifact_payload = {
    "kind": "darwin-b104-retention-canary-artifact",
    "profile_id": profile_id,
    "job_id": job_id,
    "run_label": run_label,
    "disposable": True,
    "created_at": publication_time,
}
artifact_bytes = (json.dumps(artifact_payload, sort_keys=True) + "\n").encode("utf-8")
stdout_bytes = f"STDOUT_CANARY:DARWIN_B104_OK:{run_label}\n".encode("utf-8")
stderr_bytes = f"STDERR_CANARY:DARWIN_B104_OK:{run_label}\n".encode("utf-8")

objects = {
    "artifact.bin": {
        "body": artifact_bytes,
        "content_type": "application/json",
    },
    "stdout.txt": {
        "body": stdout_bytes,
        "content_type": "text/plain; charset=utf-8",
    },
    "stderr.txt": {
        "body": stderr_bytes,
        "content_type": "text/plain; charset=utf-8",
    },
}

published_objects = []
for name, meta in objects.items():
    key = f"{canary_prefix}{name}"
    checksum = hashlib.sha256(meta["body"]).hexdigest()
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=meta["body"],
        ContentType=meta["content_type"],
        Metadata={
            "darwin-phase": "b10.4",
            "darwin-retention-canary": "true",
            "darwin-disposable": "true",
            "darwin-run-id": run_id,
        },
    )
    published_objects.append(
        {
            "artifact_kind": name.replace(".txt", "").replace(".bin", ""),
            "content_type": meta["content_type"],
            "object_key": key,
            "published_checksum": checksum,
            "size_bytes": len(meta["body"]),
        }
    )

manifest_key = f"{canary_prefix}artifact-manifest.json"
artifact_key = f"{canary_prefix}artifact.bin"
artifact_checksum = hashlib.sha256(artifact_bytes).hexdigest()
manifest_payload = {
    "manifest_format": "darwin-b101-object-artifact-v1",
    "phase": "B10.4",
    "enforcement_scope": "canary-only",
    "disposable": True,
    "profile_id": profile_id,
    "job_id": job_id,
    "run_label": run_label,
    "object_bucket": bucket,
    "object_key": artifact_key,
    "manifest_object_key": manifest_key,
    "publication_time": publication_time,
    "published_checksum": artifact_checksum,
    "published_objects": published_objects,
}
manifest_bytes = (json.dumps(manifest_payload, sort_keys=True, indent=2) + "\n").encode("utf-8")
s3.put_object(
    Bucket=bucket,
    Key=manifest_key,
    Body=manifest_bytes,
    ContentType="application/json",
    Metadata={
        "darwin-phase": "b10.4",
        "darwin-retention-canary": "true",
        "darwin-disposable": "true",
        "darwin-run-id": run_id,
    },
)

canary_keys = [f"{canary_prefix}{name}" for name in required_object_names]

plan_lines = [
    "# B10.4 lifecycle enforcement plan",
    f"bucket={bucket}",
    f"production_prefix_guard={production_prefix}",
    f"canary_prefix={canary_prefix}",
    f"destructive_mode=true",
    "delete_candidates:",
]
for key in canary_keys:
    plan_lines.append(f"- {key}")
plan_lines.append("preserved_objects:")
for key in preserved_keys:
    plan_lines.append(f"- {key}")
(result_dir / "enforcement-plan.txt").write_text("\n".join(plan_lines) + "\n", encoding="utf-8")

delete_resp = s3.delete_objects(
    Bucket=bucket,
    Delete={"Objects": [{"Key": key} for key in canary_keys], "Quiet": False},
)
errors = delete_resp.get("Errors", [])
if errors:
    raise SystemExit(f"delete_objects returned errors: {errors}")

deleted_lines = [
    "# deleted canary objects",
    "object_key\tstatus",
]
deleted_confirmed = 0
post_lines = [
    "# post-delete head checks",
]
for key in canary_keys:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        status = "unexpectedly-present"
    except botocore.exceptions.ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in {"404", "NoSuchKey", "NotFound"}:
            status = "deleted-confirmed"
            deleted_confirmed += 1
        else:
            raise
    deleted_lines.append(f"{key}\t{status}")
    post_lines.append(f"deleted_head\t{key}\t{status}")

preserved_lines = [
    "# preserved production objects",
    "object_key\tstatus\tcontent_length",
]
for key in preserved_keys:
    head = s3.head_object(Bucket=bucket, Key=key)
    preserved_lines.append(f"{key}\tpreserved\t{head['ContentLength']}")
    post_lines.append(f"preserved_head\t{key}\tpreserved")

production_objects_after = []
for page in paginator.paginate(Bucket=bucket, Prefix=production_prefix):
    production_objects_after.extend(item["Key"] for item in page.get("Contents", []))

post_lines.append(f"canary_deleted_confirmed\t{deleted_confirmed}")
post_lines.append(f"canary_expected_deleted\t{len(canary_keys)}")
post_lines.append(f"production_prefix_count_before\t{len(production_objects_before)}")
post_lines.append(f"production_prefix_count_after\t{len(production_objects_after)}")
post_lines.append(f"production_prefix_delta\t{len(production_objects_after) - len(production_objects_before)}")

(result_dir / "deleted-objects.txt").write_text("\n".join(deleted_lines) + "\n", encoding="utf-8")
(result_dir / "preserved-objects.txt").write_text("\n".join(preserved_lines) + "\n", encoding="utf-8")
(result_dir / "post-delete-head.txt").write_text("\n".join(post_lines) + "\n", encoding="utf-8")

status = "GO"
decision = (
    "the lifecycle engine performed one bounded destructive delete against the disposable canary prefix only "
    "and left production result bundles intact"
)

if deleted_confirmed != len(canary_keys):
    status = "GO-WITH-BLOCKER"
    decision = "the canary delete ran, but not all disposable canary objects were confirmed absent afterward"
elif len(production_objects_after) != len(production_objects_before):
    status = "NO-GO"
    decision = "the production prefix changed during the canary enforcement run"

(result_dir / "B104_RESULT.md").write_text(
    "# B10.4 Lifecycle Enforcement Canary Result\n\n"
    "## Status\n"
    f"{status}\n\n"
    "## Decision\n"
    f"{decision}\n\n"
    "## Summary\n"
    f"- canary prefix: `{canary_prefix}`\n"
    f"- deleted canary objects: `{deleted_confirmed}` / `{len(canary_keys)}`\n"
    f"- preserved production objects checked: `{len(preserved_keys)}`\n"
    f"- production prefix count before: `{len(production_objects_before)}`\n"
    f"- production prefix count after: `{len(production_objects_after)}`\n",
    encoding="utf-8",
)

exit_code = {"GO": 0, "GO-WITH-BLOCKER": 2, "NO-GO": 1}[status]
(result_dir / ".b104_exit_code").write_text(f"{exit_code}\n", encoding="utf-8")
PY

  collect_final_health
  echo "B10.4 retention enforcement canary artifacts written to ${RESULT_DIR}"
  local exit_code
  exit_code=$(tr -d '\n' < "${RESULT_DIR}/.b104_exit_code")
  return "${exit_code}"
}

main "$@"
