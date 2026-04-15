#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_ID=${RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/retention"
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

write_result() {
  python3 - <<'PY' "${RESULT_DIR}/retention-dryrun.txt" "${RESULT_DIR}/B103_RESULT.md" "${RUN_ID}"
import pathlib
import sys

dryrun = pathlib.Path(sys.argv[1]).read_text().splitlines()
run_id = sys.argv[3]
candidate_lines = [line for line in dryrun if line and not line.startswith("#")][1:]
eligible = [line for line in candidate_lines if "\twould-delete\t" in line]

pathlib.Path(sys.argv[2]).write_text(
    "# B10.3 Retention / Lifecycle Policy Result\n\n"
    "## Status\n"
    "GO\n\n"
    "## Decision\n"
    "the first retention policy is explicit, candidate discovery is coherent, and the first canonical evaluation remained dry-run only.\n\n"
    "## Dry-run Summary\n"
    f"- run id: {run_id}\n"
    f"- evaluated objects: {len(candidate_lines)}\n"
    f"- dry-run delete candidates: {len(eligible)}\n"
    "- destructive mode: disabled\n",
    encoding="utf-8",
)
PY
}

main() {
  require_cmd jq
  require_cmd kubectl
  require_cmd python3
  check_file() { [[ -f "$1" && -s "$1" ]]; }

  check_file "${RGW_TARGET_ENV}" || { echo "missing RGW target env: ${RGW_TARGET_ENV}" >&2; exit 1; }
  check_file "${RETENTION_POLICY}" || { echo "missing retention policy: ${RETENTION_POLICY}" >&2; exit 1; }

  export KUBECONFIG
  KUBECONFIG=$(resolve_kubeconfig) || {
    echo "no usable kubeconfig found" >&2
    exit 1
  }

  mkdir -p "${RESULT_DIR}"
  exec > >(tee "${RESULT_DIR}/retention-dryrun.txt") 2>&1

  ensure_green_cluster
  ensure_python_dep
  source "${RGW_TARGET_ENV}"
  export RGW_ENDPOINT RGW_BUCKET RGW_ACCESS_KEY RGW_SECRET_KEY RETENTION_POLICY RESULT_DIR

  [[ "${RGW_BUCKET}" != "${RGW_VELERO_BUCKET}" ]] || {
    echo "retention bucket must not match Velero bucket" >&2
    exit 1
  }

  python3 - <<'PY'
import json
import os
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path

import boto3
import yaml

policy = yaml.safe_load(Path(os.environ["RETENTION_POLICY"]).read_text())
result_dir = Path(os.environ["RESULT_DIR"])
now = datetime.now(timezone.utc)

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["RGW_ENDPOINT"],
    aws_access_key_id=os.environ["RGW_ACCESS_KEY"],
    aws_secret_access_key=os.environ["RGW_SECRET_KEY"],
    region_name="us-east-1",
)

paginator = s3.get_paginator("list_objects_v2")
pages = paginator.paginate(Bucket=os.environ["RGW_BUCKET"], Prefix=policy["target"]["key_prefix_family"])

key_re = re.compile(r"^hpc/(?P<profile>[^/]+)/(?P<job_id>\d+)/(?P<run_label>[^/]+)/(?P<object_name>[^/]+)$")
objects = []
for page in pages:
    for obj in page.get("Contents", []):
        key = obj["Key"]
        match = key_re.match(key)
        if not match:
            continue
        profile = match.group("profile")
        object_name = match.group("object_name")
        profile_policy = policy["profiles"].get(profile)
        if not profile_policy:
            continue
        rule = profile_policy["artifact_rules"].get(object_name)
        if not rule:
            continue
        last_modified = obj["LastModified"]
        retain_days = int(rule["retain_days"])
        eligible_at = last_modified + timedelta(days=retain_days)
        eligible = now >= eligible_at
        action = "would-delete" if eligible else "retain"
        objects.append(
            {
                "profile_id": profile,
                "job_id": int(match.group("job_id")),
                "run_label": match.group("run_label"),
                "object_name": object_name,
                "object_key": key,
                "size_bytes": obj["Size"],
                "last_modified": last_modified.astimezone().isoformat(),
                "retention_class": profile_policy["retention_class"],
                "retain_days": retain_days,
                "eligible_at": eligible_at.astimezone().isoformat(),
                "eligible": eligible,
                "action": action,
                "mode": policy["execution"]["first_canonical_run_mode"],
            }
        )

objects.sort(key=lambda item: (item["profile_id"], item["job_id"], item["object_name"]))

candidate_path = result_dir / "candidate-objects.txt"
plan_path = result_dir / "retention-plan.txt"
dryrun_path = result_dir / "retention-dryrun.txt"

plan_lines = [
    "# B10.3 retention plan",
    f"bucket={policy['target']['bucket']}",
    f"forbidden_bucket={policy['target']['forbidden_bucket']}",
    f"execution_mode={policy['execution']['first_canonical_run_mode']}",
    "profiles:",
]
for profile_id, profile_policy in policy["profiles"].items():
    plan_lines.append(f"- {profile_id}: class={profile_policy['retention_class']}")
    for object_name, rule in profile_policy["artifact_rules"].items():
        preserve = str(rule.get("preserve_longer_than_payload", False)).lower()
        plan_lines.append(
            f"  - {object_name}: retain_days={rule['retain_days']} preserve_longer_than_payload={preserve}"
        )
plan_path.write_text("\n".join(plan_lines) + "\n", encoding="utf-8")

candidate_lines = [
    "# discovered object candidates",
    "profile_id\tjob_id\trun_label\tobject_name\tsize_bytes\tlast_modified",
]
for item in objects:
    candidate_lines.append(
        "\t".join(
            [
                item["profile_id"],
                str(item["job_id"]),
                item["run_label"],
                item["object_name"],
                str(item["size_bytes"]),
                item["last_modified"],
            ]
        )
    )
candidate_path.write_text("\n".join(candidate_lines) + "\n", encoding="utf-8")

dryrun_lines = [
    "# retention dry-run",
    "profile_id\tjob_id\trun_label\tobject_name\tretention_class\tretain_days\teligible_at\teligible\taction\tmode",
]
for item in objects:
    dryrun_lines.append(
        "\t".join(
            [
                item["profile_id"],
                str(item["job_id"]),
                item["run_label"],
                item["object_name"],
                item["retention_class"],
                str(item["retain_days"]),
                item["eligible_at"],
                str(item["eligible"]).lower(),
                item["action"],
                item["mode"],
            ]
        )
    )
dryrun_path.write_text("\n".join(dryrun_lines) + "\n", encoding="utf-8")

print(dryrun_path.read_text(), end="")
PY

  collect_final_health
  write_result
  echo "B10.3 retention dry-run artifacts written to ${RESULT_DIR}"
}

main "$@"
