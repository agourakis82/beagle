#!/usr/bin/env bash
set -u -o pipefail

PACKET_PATH="${1:-}"
LANE="${2:-cpu}"

die() {
  echo "[sounio-foundry][error] $*" >&2
  exit 1
}

note() {
  echo "[sounio-foundry][info] $*"
}

[[ -n "${PACKET_PATH}" ]] || die "missing run_packet.json path"
[[ -f "${PACKET_PATH}" ]] || die "run packet not found: ${PACKET_PATH}"
[[ "${LANE}" == "cpu" || "${LANE}" == "gpu" ]] || die "invalid lane: ${LANE}"

json_get() {
  local expr="$1"
  local default_value="${2:-}"
  python3 - "${PACKET_PATH}" "${expr}" "${default_value}" <<'PY'
import json
import sys

path, expr, default = sys.argv[1:4]
data = json.load(open(path, encoding="utf-8"))
cur = data
for part in expr.split("."):
    if not part:
        continue
    if isinstance(cur, dict):
        cur = cur.get(part)
    else:
        cur = None
        break
if cur is None:
    print(default)
else:
    print(cur)
PY
}

RUN_ID="$(json_get run_id "${SOUNIO_RUN_ID:-unknown}")"
PROFILE="$(json_get profile full-compiler)"
ARTIFACT_ROOT="$(json_get artifact_root "")"
SNAPSHOT_PATH="$(json_get source.snapshot_path "")"
COMPILER_BINARY="$(json_get compiler_binary bin/souc)"

[[ -n "${ARTIFACT_ROOT}" ]] || die "artifact_root missing from run packet"

if [[ "${LANE}" == "gpu" ]]; then
  SUMMARY_FILE="${ARTIFACT_ROOT}/summary-gpu.json"
  RESULTS_FILE="${ARTIFACT_ROOT}/results-gpu.tsv"
  HASHES_FILE="${ARTIFACT_ROOT}/artifact_hashes-gpu.tsv"
  JUNIT_FILE="${ARTIFACT_ROOT}/junit-gpu.xml"
else
  SUMMARY_FILE="${ARTIFACT_ROOT}/summary.json"
  RESULTS_FILE="${ARTIFACT_ROOT}/results.tsv"
  HASHES_FILE="${ARTIFACT_ROOT}/artifact_hashes.tsv"
  JUNIT_FILE="${ARTIFACT_ROOT}/junit.xml"
fi

LOG_DIR="${ARTIFACT_ROOT}/logs"
SCRATCH_ROOT="/tmp/sounio-foundry/${RUN_ID}/${LANE}"
SRC_DIR="${SCRATCH_ROOT}/src"

mkdir -p "${ARTIFACT_ROOT}" "${LOG_DIR}" "${SCRATCH_ROOT}"
if [[ "$(readlink -f "${PACKET_PATH}")" != "$(readlink -f "${ARTIFACT_ROOT}/run_packet.json" 2>/dev/null || true)" ]]; then
  cp -f "${PACKET_PATH}" "${ARTIFACT_ROOT}/run_packet.json"
fi

export SOUNIO_RUN_ID="${RUN_ID}"
export SOUNIO_PROFILE="${PROFILE}"
export SOUNIO_SCRATCH="${SCRATCH_ROOT}"
export SOUNIO_ARTIFACTS="${ARTIFACT_ROOT}"
export SOUNIO_TEST_JUNIT_FILE="${ARTIFACT_ROOT}/test-suite-junit.xml"
export SOUNIO_TEST_RESULTS_DIR="${ARTIFACT_ROOT}/test-results"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'lane\tphase\tlayer\tstatus\tseconds\tlog\n' >"${RESULTS_FILE}"

PHASE_ROWS="${SCRATCH_ROOT}/phase_rows.tsv"
: >"${PHASE_ROWS}"

record_phase() {
  local phase="$1"
  local layer="$2"
  local status="$3"
  local seconds="$4"
  local log_path="$5"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${LANE}" "${phase}" "${layer}" "${status}" "${seconds}" "${log_path}" | tee -a "${RESULTS_FILE}" >>"${PHASE_ROWS}"
}

extract_snapshot() {
  local log_path="${LOG_DIR}/${LANE}-snapshot.log"
  local start elapsed
  start="$(date +%s)"
  {
    echo "run_id=${RUN_ID}"
    echo "lane=${LANE}"
    echo "snapshot=${SNAPSHOT_PATH}"
    echo "scratch=${SCRATCH_ROOT}"
  } >"${log_path}"

  if [[ -z "${SNAPSHOT_PATH}" || ! -f "${SNAPSHOT_PATH}" ]]; then
    elapsed="$(( $(date +%s) - start ))"
    echo "snapshot missing or unavailable" >>"${log_path}"
    record_phase "snapshot" "snapshot" "fail" "${elapsed}" "${log_path}"
    return 1
  fi

  rm -rf "${SRC_DIR}"
  mkdir -p "${SRC_DIR}"
  if tar -xzf "${SNAPSHOT_PATH}" -C "${SRC_DIR}" >>"${log_path}" 2>&1; then
    elapsed="$(( $(date +%s) - start ))"
    record_phase "snapshot" "snapshot" "pass" "${elapsed}" "${log_path}"
    return 0
  fi

  elapsed="$(( $(date +%s) - start ))"
  record_phase "snapshot" "snapshot" "fail" "${elapsed}" "${log_path}"
  return 1
}

run_phase() {
  local phase="$1"
  local layer="$2"
  local required="$3"
  local command_text="$4"
  local log_path="${LOG_DIR}/${LANE}-${phase}.log"
  local start elapsed

  start="$(date +%s)"
  {
    echo "run_id=${RUN_ID}"
    echo "lane=${LANE}"
    echo "phase=${phase}"
    echo "layer=${layer}"
    echo "source=${SOUNIO_SOURCE}"
    echo "scratch=${SOUNIO_SCRATCH}"
    echo "artifacts=${SOUNIO_ARTIFACTS}"
    echo "command=${command_text}"
    echo
  } >"${log_path}"

  (
    cd "${SOUNIO_SOURCE}" || exit 97
    bash -lc "${command_text}"
  ) >>"${log_path}" 2>&1
  local rc=$?
  elapsed="$(( $(date +%s) - start ))"

  if [[ "${rc}" -eq 0 ]]; then
    record_phase "${phase}" "${layer}" "pass" "${elapsed}" "${log_path}"
    return 0
  fi

  if [[ "${required}" == "required" ]]; then
    record_phase "${phase}" "${layer}" "fail" "${elapsed}" "${log_path}"
    return 1
  fi

  record_phase "${phase}" "${layer}" "not_run" "${elapsed}" "${log_path}"
  return 0
}

run_optional_script() {
  local phase="$1"
  local layer="$2"
  local script="$3"
  local command_text="${4:-bash ${script}}"
  if [[ ! -f "${SOUNIO_SOURCE}/${script}" ]]; then
    record_phase "${phase}" "${layer}" "not_run" "0" "${LOG_DIR}/${LANE}-${phase}.log"
    printf 'optional script not present: %s\n' "${script}" >"${LOG_DIR}/${LANE}-${phase}.log"
    return 0
  fi
  run_phase "${phase}" "${layer}" "required" "${command_text}"
}

run_bootstrap_fixed_point() {
  local log_path="${LOG_DIR}/${LANE}-bootstrap_fixed_point.log"
  if [[ ! -f "${SOUNIO_SOURCE}/scripts/ci/bootstrap_chain_gate.sh" ]]; then
    record_phase "bootstrap_fixed_point" "bootstrap_fixed_point" "not_run" "0" "${log_path}"
    printf 'optional script not present: %s\n' "scripts/ci/bootstrap_chain_gate.sh" >"${log_path}"
    return 0
  fi

  if ! command -v cc >/dev/null 2>&1; then
    record_phase "bootstrap_fixed_point" "bootstrap_fixed_point" "not_run" "0" "${log_path}"
    {
      echo "bootstrap fixed-point gate requires a host C compiler."
      echo "cc was not found on this Slurm lane, so the phase was not run."
      echo "This is a lane dependency gap, not a compiler fixed-point failure."
    } >"${log_path}"
    return 0
  fi

  run_phase "bootstrap_fixed_point" "bootstrap_fixed_point" "required" \
    "bash scripts/ci/bootstrap_chain_gate.sh"
}

run_required_script() {
  local phase="$1"
  local layer="$2"
  local script="$3"
  local command_text="${4:-bash ${script}}"
  if [[ ! -f "${SOUNIO_SOURCE}/${script}" ]]; then
    record_phase "${phase}" "${layer}" "fail" "0" "${LOG_DIR}/${LANE}-${phase}.log"
    printf 'required script not present: %s\n' "${script}" >"${LOG_DIR}/${LANE}-${phase}.log"
    return 1
  fi
  run_phase "${phase}" "${layer}" "required" "${command_text}"
}

write_summary() {
  local summary_path="$1"
  local status_override="${2:-}"
  local finished_at
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 - "${summary_path}" "${PHASE_ROWS}" "${RUN_ID}" "${LANE}" "${PROFILE}" "${STARTED_AT}" "${finished_at}" "${status_override}" <<'PY'
import json
import pathlib
import sys

summary_path, rows_path, run_id, lane, profile, started, finished, status_override = sys.argv[1:9]
counts = {"pass": 0, "fail": 0, "not_run": 0, "partial": 0}
phases = []
failed_layers = []
partial_layers = []

for line in pathlib.Path(rows_path).read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    lane_value, phase, layer, status, seconds, log = line.split("\t", 5)
    counts[status] = counts.get(status, 0) + 1
    phases.append({
        "lane": lane_value,
        "phase": phase,
        "layer": layer,
        "status": status,
        "seconds": int(seconds) if seconds.isdigit() else seconds,
        "log": log,
    })
    if status == "fail" and layer not in failed_layers:
        failed_layers.append(layer)
    if status in ("not_run", "partial") and layer not in partial_layers:
        partial_layers.append(layer)

if status_override:
    status = status_override
elif counts.get("fail", 0):
    status = "fail"
elif counts.get("not_run", 0) or counts.get("partial", 0):
    status = "partial"
else:
    status = "pass"

payload = {
    "schema": "sounio.compiler_foundry.summary.v1",
    "run_id": run_id,
    "lane": lane,
    "profile": profile,
    "status": status,
    "counts": counts,
    "failed_layers": failed_layers,
    "partial_layers": partial_layers,
    "started_at_utc": started,
    "finished_at_utc": finished,
    "artifacts": {
        "artifact_root": str(pathlib.Path(summary_path).parent),
        "results": "results-gpu.tsv" if lane == "gpu" else "results.tsv",
        "junit": "junit-gpu.xml" if lane == "gpu" else "junit.xml",
        "test_suite_junit": "test-suite-junit.xml",
        "test_results": "test-results/",
        "logs": "logs/",
    },
    "phases": phases,
}
pathlib.Path(summary_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

write_junit() {
  python3 - "${JUNIT_FILE}" "${PHASE_ROWS}" "${RUN_ID}" "${LANE}" <<'PY'
import html
import pathlib
import sys

junit_path, rows_path, run_id, lane = sys.argv[1:5]
rows = []
for line in pathlib.Path(rows_path).read_text(encoding="utf-8").splitlines():
    if line.strip():
        rows.append(line.split("\t", 5))
failures = sum(1 for row in rows if row[3] == "fail")
skipped = sum(1 for row in rows if row[3] in ("not_run", "partial"))
parts = [f'<testsuite name="sounio-foundry-{html.escape(lane)}" tests="{len(rows)}" failures="{failures}" skipped="{skipped}">']
for _, phase, layer, status, seconds, log in rows:
    parts.append(f'  <testcase classname="sounio_foundry.{html.escape(layer)}" name="{html.escape(phase)}" time="{html.escape(seconds)}">')
    if status == "fail":
        parts.append(f'    <failure message="{html.escape(layer)} failure">{html.escape(log)}</failure>')
    elif status in ("not_run", "partial"):
        parts.append(f'    <skipped message="{html.escape(status)}">{html.escape(log)}</skipped>')
    parts.append('  </testcase>')
parts.append('</testsuite>')
pathlib.Path(junit_path).write_text("\n".join(parts) + "\n", encoding="utf-8")
PY
}

write_hashes() {
  {
    printf 'sha256\tbytes\tpath\n'
    find "${ARTIFACT_ROOT}" -maxdepth 2 -type f \
      ! -name "$(basename "${HASHES_FILE}")" \
      ! -name 'source.tar.gz' \
      -print0 | sort -z | while IFS= read -r -d '' path; do
        sha="$(sha256sum "${path}" | awk '{print $1}')"
        bytes="$(stat -c%s "${path}" 2>/dev/null || stat -f%z "${path}")"
        printf '%s\t%s\t%s\n' "${sha}" "${bytes}" "${path}"
      done
  } >"${HASHES_FILE}"
}

finalize_and_exit() {
  local rc="$1"
  local status_override="${2:-}"
  write_junit
  write_summary "${SUMMARY_FILE}" "${status_override}"
  write_hashes
  exit "${rc}"
}

if ! extract_snapshot; then
  finalize_and_exit 2 "fail"
fi

export SOUNIO_SOURCE="${SRC_DIR}"

if [[ "${SOUNIO_SOURCE}" == "/workspace/sounio"* ]]; then
  record_phase "safety" "harness" "fail" "0" "${LOG_DIR}/${LANE}-safety.log"
  printf 'refusing to execute against live workspace: %s\n' "${SOUNIO_SOURCE}" >"${LOG_DIR}/${LANE}-safety.log"
  finalize_and_exit 3 "fail"
fi

if [[ "${LANE}" == "cpu" ]]; then
  run_phase "orientation" "harness" "required" \
    "hostname; pwd; env | sort; test -x '${COMPILER_BINARY}'; '${COMPILER_BINARY}' info || '${COMPILER_BINARY}' --version || '${COMPILER_BINARY}' --help"
  if [[ "${PROFILE}" == "orientation" ]]; then
    finalize_and_exit 0 ""
  fi
  if [[ "${PROFILE}" == "corpus-smoke" ]]; then
    run_required_script "corpus_smoke" "check_corpus" "scripts/run_sio_test_suite.sh" \
      "SOUNIO_TEST_JOBS=2 bash scripts/run_sio_test_suite.sh --filter basic_math --format junit --jobs 2"
    finalize_and_exit 0 ""
  fi
  run_required_script "corpus" "check_corpus" "scripts/run_sio_test_suite.sh"
  run_required_script "native_trust" "native_abi" "scripts/ci/native_v2_driver_self_compile_gate.sh"
  run_required_script "science_spine" "epistemic_section" "scripts/ci/native_v2_epistemic_science_spine_gate.sh"
  run_required_script "semantic_hardening" "native_abi" "scripts/ci/native_v2_semantic_hardening_gate.sh"
  run_required_script "f64_ladder" "isa_microarch" "scripts/ci/native_v2_f64_ladder_gate.sh"
  run_required_script "gum_primitives" "epistemic_section" "scripts/ci/native_v2_gum_primitives_gate.sh"
  run_bootstrap_fixed_point
else
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    record_phase "gpu_lane_probe" "gpu_runtime" "not_run" "0" "${LOG_DIR}/${LANE}-gpu_lane_probe.log"
    printf 'nvidia-smi not available in gpu lane\n' >"${LOG_DIR}/${LANE}-gpu_lane_probe.log"
    finalize_and_exit 0 "partial"
  fi
  run_phase "orientation" "harness" "required" \
    "hostname; pwd; nvidia-smi; env | sort; test -x '${COMPILER_BINARY}'; '${COMPILER_BINARY}' info || '${COMPILER_BINARY}' --version || '${COMPILER_BINARY}' --help"
  if [[ "${PROFILE}" == "orientation" ]]; then
    finalize_and_exit 0 ""
  fi
  run_required_script "accel_spine" "epistemic_section" "scripts/ci/native_v2_epistemic_accel_spine_gate.sh"
  run_optional_script "gpu_ptx_codegen" "gpu_ptx" "tests/gpu/gate_ptx_codegen.sh"
  run_required_script "gpu_runtime_parity" "gpu_runtime" "scripts/ci/native_v2_epistemic_gpu_runtime_parity_gate.sh"
fi

if awk -F '\t' 'NR > 1 && $4 == "fail" { found = 1 } END { exit found ? 0 : 1 }' "${RESULTS_FILE}"; then
  finalize_and_exit 1 "fail"
fi

finalize_and_exit 0 ""
