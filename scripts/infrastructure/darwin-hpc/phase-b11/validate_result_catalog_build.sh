#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../../.." && pwd)
DOC_ROOT="${REPO_ROOT}/docs/darwin/hpc"
CONTRACT_ROOT="${DOC_ROOT}/contracts"
ARTIFACT_ROOT=${ARTIFACT_ROOT:-"${REPO_ROOT}/.artifacts/darwin-hpc"}
PHASE_ROOT="${ARTIFACT_ROOT}/phase-b11"
RUN_ID=${RUN_ID:?RUN_ID is required}
RESULT_DIR="${PHASE_ROOT}/${RUN_ID}/result-catalog"
POLICY_FILE=${POLICY_FILE:-"${CONTRACT_ROOT}/result-catalog-policy.yaml"}
ENTRY_SCHEMA_FILE=${ENTRY_SCHEMA_FILE:-"${CONTRACT_ROOT}/result-catalog-entry.json"}

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
  check_file "${ENTRY_SCHEMA_FILE}"
  check_file "${RESULT_DIR}/B112_RESULT.md"
  check_file "${RESULT_DIR}/catalog-build.txt"
  check_file "${RESULT_DIR}/catalog-sample.json"
  check_file "${RESULT_DIR}/query-sample.txt"
  check_file "${RESULT_DIR}/final-cluster-health.txt"

  python3 - <<'PY' "${POLICY_FILE}" "${ENTRY_SCHEMA_FILE}" "${RESULT_DIR}/catalog-sample.json" "${RESULT_DIR}/query-sample.txt"
import json
import re
import sys

import yaml

policy = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
schema = json.load(open(sys.argv[2], "r", encoding="utf-8"))
catalog = json.load(open(sys.argv[3], "r", encoding="utf-8"))
queries = json.load(open(sys.argv[4], "r", encoding="utf-8"))

if policy["source_of_truth"]["type"] != "object-plane":
    raise SystemExit("catalog source of truth is not object-plane")
if sorted(policy["minimum_filters"]) != ["job_id", "profile_id", "run_label"]:
    raise SystemExit("minimum filters do not match expected canonical set")
if "/results" not in policy["gateway"]["stable_endpoints"]:
    raise SystemExit("missing /results endpoint in policy")

if catalog["catalog_format"] != policy["catalog"]["format"]:
    raise SystemExit("catalog format mismatch")
if catalog["source_of_truth"] != "object-plane":
    raise SystemExit("catalog source_of_truth mismatch")

entries = catalog["entries"]
if len(entries) < 3:
    raise SystemExit("catalog has fewer than 3 entries")
if catalog["total_results"] != len(entries):
    raise SystemExit("catalog total_results mismatch")

required = schema["required"]
properties = schema["properties"]
for entry in entries:
    missing = sorted(set(required) - set(entry))
    if missing:
      raise SystemExit(f"catalog entry missing fields: {', '.join(missing)}")
    for field, spec in properties.items():
        if field not in entry:
            continue
        value = entry[field]
        if spec.get("type") == "integer" and not isinstance(value, int):
            raise SystemExit(f"{field} is not integer")
        if spec.get("type") == "string" and not isinstance(value, str):
            raise SystemExit(f"{field} is not string")
        if "const" in spec and value != spec["const"]:
            raise SystemExit(f"{field} const mismatch")
        if "enum" in spec and value not in spec["enum"]:
            raise SystemExit(f"{field} enum mismatch")
        if "pattern" in spec and not re.match(spec["pattern"], value):
            raise SystemExit(f"{field} pattern mismatch: {value}")

expected = {
    24: ("cpu-short-v1", "t560-proxmox"),
    31: ("cpu-batch-v1", "t560-proxmox"),
    32: ("gpu-single-v1", "r740-proxmox"),
}
by_job = {entry["job_id"]: entry for entry in entries}
for job_id, (profile_id, node_name) in expected.items():
    if job_id not in by_job:
        raise SystemExit(f"missing catalog entry for job_id={job_id}")
    entry = by_job[job_id]
    if entry["profile_id"] != profile_id:
        raise SystemExit(f"profile mismatch for job_id={job_id}")
    if entry["node_list"] != node_name:
        raise SystemExit(f"node_list mismatch for job_id={job_id}")

for key in ("all_results", "profile_filter", "run_label_filter", "job_lookup", "manifest_lookup"):
    if queries[key]["http_status"] != 200:
        raise SystemExit(f"{key} did not return 200")

all_results = queries["all_results"]["body"]
if all_results["total"] != len(entries):
    raise SystemExit("all_results total mismatch")
if len(all_results["results"]) != len(entries):
    raise SystemExit("all_results result length mismatch")

profile_filter = queries["profile_filter"]["body"]
if profile_filter["total"] < 1:
    raise SystemExit("profile filter returned no results")
if any(entry["profile_id"] != "cpu-batch-v1" for entry in profile_filter["results"]):
    raise SystemExit("profile filter returned wrong profile")

run_label_filter = queries["run_label_filter"]["body"]
requested_run_label = queries["requested_gpu_run_label"]
if run_label_filter["total"] != 1:
    raise SystemExit("run_label filter did not isolate one result")
if run_label_filter["results"][0]["run_label"] != requested_run_label:
    raise SystemExit("run_label filter returned wrong result")

job_lookup = queries["job_lookup"]["body"]
requested_job_id = queries["requested_gpu_job_id"]
if job_lookup["job_id"] != requested_job_id:
    raise SystemExit("job lookup returned wrong job_id")
if job_lookup["node_list"] != "r740-proxmox":
    raise SystemExit("job lookup did not preserve gpu node_list")

manifest_lookup = queries["manifest_lookup"]["body"]
if manifest_lookup["job_id"] != requested_job_id:
    raise SystemExit("manifest lookup returned wrong job_id")
if manifest_lookup["manifest_object_key"] != job_lookup["artifact_manifest_key"]:
    raise SystemExit("manifest lookup key does not match catalog entry")
PY

  grep -q 'catalog_results=' "${RESULT_DIR}/catalog-build.txt"
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

  echo "[OK] B11.2 result catalog validation passed"
}

main "$@"
