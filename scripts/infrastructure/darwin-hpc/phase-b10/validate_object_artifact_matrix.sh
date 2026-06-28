#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b10"
RUN_ID=${RUN_ID:?RUN_ID is required}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/object-artifacts"
RGW_TARGET_ENV=${RGW_TARGET_ENV:-"${CONTRACT_ROOT}/rgw-artifact-target.env"}

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

check_file() {
  local path=$1
  [[ -f "${path}" && -s "${path}" ]] || {
    echo "missing or empty file: ${path}" >&2
    exit 1
  }
}

ensure_python_dep() {
  if python3 - <<'PY' >/dev/null 2>&1
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec("boto3") and importlib.util.find_spec("botocore") else 1)
PY
  then
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y python3-boto3 python3-botocore >/dev/null
}

validate_manifest_file() {
  local path=$1
  local expected_profile=$2

  jq -e --arg profile "${expected_profile}" '
    .manifest_format == "darwin-b101-object-artifact-v1" and
    .publication_target_id == "hpc-artifacts-v1" and
    .source_phase == "B10.2" and
    .profile_id == $profile and
    .object_bucket == "darwin-hpc-artifacts" and
    (.object_key | test("^hpc/(cpu-short-v1|cpu-batch-v1|gpu-single-v1)/[0-9]+/[A-Za-z0-9._-]+/artifact\\.bin$")) and
    (.manifest_object_key | test("^hpc/(cpu-short-v1|cpu-batch-v1|gpu-single-v1)/[0-9]+/[A-Za-z0-9._-]+/artifact-manifest\\.json$")) and
    (.published_checksum | test("^[a-f0-9]{64}$")) and
    (.published_objects | length == 3)
  ' "${path}" >/dev/null
}

main() {
  require_cmd jq
  require_cmd python3
  check_file "${RGW_TARGET_ENV}"

  for path in \
    "${RESULT_DIR}/B102_RESULT.md" \
    "${RESULT_DIR}/cpu-batch-object-manifest.json" \
    "${RESULT_DIR}/cpu-batch-object-head.txt" \
    "${RESULT_DIR}/gpu-object-manifest.json" \
    "${RESULT_DIR}/gpu-object-head.txt" \
    "${RESULT_DIR}/publish-log.txt" \
    "${RESULT_DIR}/final-cluster-health.txt" \
    "${RESULT_DIR}/cpu-batch-source-artifact.txt" \
    "${RESULT_DIR}/gpu-source-artifact.txt" \
    "${RESULT_DIR}/cpu-batch-source-stdout.txt" \
    "${RESULT_DIR}/gpu-source-stdout.txt"; do
    check_file "${path}"
  done

  source "${RGW_TARGET_ENV}"
  [[ "${RGW_BUCKET}" != "${RGW_VELERO_BUCKET}" ]] || {
    echo "artifact bucket matches Velero bucket" >&2
    exit 1
  }

  validate_manifest_file "${RESULT_DIR}/cpu-batch-object-manifest.json" "cpu-batch-v1"
  validate_manifest_file "${RESULT_DIR}/gpu-object-manifest.json" "gpu-single-v1"

  jq -e 'length == 4' "${RESULT_DIR}/cpu-batch-object-head.txt" >/dev/null
  jq -e 'length == 4' "${RESULT_DIR}/gpu-object-head.txt" >/dev/null
  jq -e '.node_list == "t560-proxmox" and .profile_id == "cpu-batch-v1" and .state == "COMPLETED"' "${RESULT_DIR}/cpu-batch-source-artifact.txt" >/dev/null
  jq -e '.node_list == "r740-proxmox" and .profile_id == "gpu-single-v1" and .state == "COMPLETED"' "${RESULT_DIR}/gpu-source-artifact.txt" >/dev/null
  grep -q 'CPU_BATCH_PHASE:finalize' "${RESULT_DIR}/cpu-batch-source-stdout.txt"
  grep -q 'NVIDIA RTX A5000' "${RESULT_DIR}/gpu-source-stdout.txt"
  grep -q 'slurmctld=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'slurmrestd=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 't560-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'r770-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q '5860-proxmox' "${RESULT_DIR}/final-cluster-health.txt"

  ensure_python_dep
  export RESULT_DIR RGW_ENDPOINT RGW_BUCKET RGW_ACCESS_KEY RGW_SECRET_KEY
  python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

import boto3

result_dir = Path(os.environ["RESULT_DIR"])
s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["RGW_ENDPOINT"],
    aws_access_key_id=os.environ["RGW_ACCESS_KEY"],
    aws_secret_access_key=os.environ["RGW_SECRET_KEY"],
    region_name="us-east-1",
)

for manifest_name in ("cpu-batch-object-manifest.json", "gpu-object-manifest.json"):
    manifest = json.loads((result_dir / manifest_name).read_text())
    object_keys = [entry["object_key"] for entry in manifest["published_objects"]]
    object_keys.append(manifest["manifest_object_key"])
    for object_key in object_keys:
        body = s3.get_object(Bucket=manifest["object_bucket"], Key=object_key)["Body"].read()
        sha = hashlib.sha256(body).hexdigest()
        if object_key == manifest["manifest_object_key"]:
            expected = hashlib.sha256((result_dir / manifest_name).read_bytes()).hexdigest()
        else:
            expected = next(entry["published_checksum"] for entry in manifest["published_objects"] if entry["object_key"] == object_key)
        if sha != expected:
            raise SystemExit(f"checksum mismatch for {object_key}")
PY

  echo "[OK] B10.2 multi-profile object publication validation passed"
}

main "$@"
