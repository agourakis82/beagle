#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b11"
RUN_ID=${RUN_ID:?RUN_ID is required}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/object-retrieval"
POLICY_FILE=${POLICY_FILE:-"${CONTRACT_ROOT}/object-retrieval-policy.yaml"}

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

main() {
  require_cmd python3
  require_cmd grep

  check_file "${POLICY_FILE}"
  check_file "${RESULT_DIR}/B111_RESULT.md"
  check_file "${RESULT_DIR}/cpu-short-retrieval.txt"
  check_file "${RESULT_DIR}/cpu-batch-retrieval.txt"
  check_file "${RESULT_DIR}/gpu-retrieval.txt"
  check_file "${RESULT_DIR}/final-cluster-health.txt"

  python3 - <<'PY' "${POLICY_FILE}" "${RESULT_DIR}/cpu-short-retrieval.txt" "${RESULT_DIR}/cpu-batch-retrieval.txt" "${RESULT_DIR}/gpu-retrieval.txt"
import json
import re
import sys
import yaml

policy = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
assert policy["artifact_source"]["primary"] == "object-plane"
assert policy["artifact_source"]["bucket"] == "darwin-hpc-artifacts"
assert "/jobs/{job_id}/artifact" in policy["stable_endpoints"]

profiles = [
    ("cpu-short-v1", sys.argv[2]),
    ("cpu-batch-v1", sys.argv[3]),
    ("gpu-single-v1", sys.argv[4]),
]

for profile_id, path in profiles:
    payload = json.load(open(path, "r", encoding="utf-8"))
    manifest = payload["artifact_manifest"]
    summary = payload["job_summary"]
    if payload["profile_id"] != profile_id:
        raise SystemExit(f"profile mismatch in {path}: {payload['profile_id']} != {profile_id}")
    if payload["job_summary_http_status"] != 200:
        raise SystemExit(f"job summary did not return 200 for {profile_id}")
    if payload["artifact_manifest_http_status"] != 200:
        raise SystemExit(f"artifact manifest did not return 200 for {profile_id}")
    if payload["artifact_http_status"] != 200:
        raise SystemExit(f"artifact did not return 200 for {profile_id}")
    if payload["stdout_http_status"] != 200:
        raise SystemExit(f"stdout did not return 200 for {profile_id}")
    if payload["stderr_http_status"] != 200:
        raise SystemExit(f"stderr did not return 200 for {profile_id}")
    if summary.get("artifact_source") != "object-plane":
        raise SystemExit(f"artifact source is not object-plane for {profile_id}")
    if manifest.get("retrieval_source") != "object-plane":
        raise SystemExit(f"manifest retrieval source is not object-plane for {profile_id}")
    if manifest.get("object_bucket") != "darwin-hpc-artifacts":
        raise SystemExit(f"unexpected object bucket for {profile_id}")
    if manifest.get("manifest_format") != "darwin-b101-object-artifact-v1":
        raise SystemExit(f"unexpected manifest format for {profile_id}")
    if not re.match(r"^hpc/(cpu-short-v1|cpu-batch-v1|gpu-single-v1)/[0-9]+/[A-Za-z0-9._-]+/artifact-manifest\.json$", manifest.get("manifest_object_key", "")):
        raise SystemExit(f"unexpected manifest object key for {profile_id}")
    if not re.match(r"^hpc/(cpu-short-v1|cpu-batch-v1|gpu-single-v1)/[0-9]+/[A-Za-z0-9._-]+/artifact\.bin$", manifest.get("object_key", "")):
        raise SystemExit(f"unexpected artifact object key for {profile_id}")
    published = {entry["artifact_kind"]: entry for entry in manifest.get("published_objects", [])}
    if sorted(published) != ["artifact", "stderr", "stdout"]:
        raise SystemExit(f"unexpected published objects for {profile_id}")
    if payload["artifact_sha256"] != manifest.get("published_checksum"):
        raise SystemExit(f"artifact checksum mismatch for {profile_id}")
    if payload["stdout_sha256"] != published["stdout"]["published_checksum"]:
        raise SystemExit(f"stdout checksum mismatch for {profile_id}")
    if payload["stderr_sha256"] != published["stderr"]["published_checksum"]:
        raise SystemExit(f"stderr checksum mismatch for {profile_id}")
    if profile_id == "gpu-single-v1" and summary.get("node_list") != "r740-proxmox":
        raise SystemExit("gpu retrieval did not resolve the r740-backed job")
PY

  grep -q 'DARWIN_B95_CPU_SHORT_V1_OK' "${RESULT_DIR}/cpu-short-retrieval.txt"
  grep -q 'CPU_BATCH_PHASE:finalize' "${RESULT_DIR}/cpu-batch-retrieval.txt"
  grep -q 'NVIDIA RTX A5000' "${RESULT_DIR}/gpu-retrieval.txt"
  grep -Eq 'slurmctld=(inactive|unknown)' "${RESULT_DIR}/final-cluster-health.txt"
  grep -Eq 'slurmrestd=(inactive|unknown)' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'darwin-slurm-control-adapter=active' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'active-scheduler=slurm-pilot' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'legacy-adapter-mode=legacy-catalog-only' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'slurm-pilot-controller' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'slurm-pilot-restapi' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'slurm-pilot-login-slinky' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 't560-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q 'r770-proxmox' "${RESULT_DIR}/final-cluster-health.txt"
  grep -q '5860-proxmox' "${RESULT_DIR}/final-cluster-health.txt"

  echo "[OK] B11.1 object-backed retrieval validation passed"
}

main "$@"
