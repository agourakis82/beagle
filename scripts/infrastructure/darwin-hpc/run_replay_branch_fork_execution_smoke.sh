#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/replay-branch-fork-execution}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18497}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B256_BASE_OUT="${B256_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/code-provenance-capture}"

REPLAY_EXECUTION_SOURCE_FILE="${REPLAY_EXECUTION_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/replay_execution.rs}"
RUN_CAPSULE_SOURCE_FILE="${RUN_CAPSULE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/run_capsule.rs}"
WORKBENCH_RUN_SOURCE_FILE="${WORKBENCH_RUN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_run.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B257_REPLAY_BRANCH_FORK_EXECUTION.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B257_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B257_KNOWN_LIMITS.md}"
REPLAY_REQUEST_SCHEMA_FILE="${REPLAY_REQUEST_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/replay-request-schema.yaml}"
REPLAY_EXECUTION_SCHEMA_FILE="${REPLAY_EXECUTION_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/replay-execution-schema.yaml}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require base64
require curl
require git
require jq
require rg
require sha256sum
require ss
require sudo

resolve_kubectl() {
  if [[ -n "${KUBECTL}" ]]; then
    printf '%s\n' "${KUBECTL}"
    return 0
  fi
  if [[ -r /etc/kubernetes/admin.conf ]]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    printf '%s\n' kubectl
    return 0
  fi
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
    return 0
  fi
  printf '%s\n' kubectl
}

resolve_operator_api_token() {
  local encoded_token=""
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token in secret ${SECRET_NAME}" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

choose_local_port() {
  local port="$1"
  local tries=0
  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done
  echo "[FAIL] unable to find a free local port starting at $1" >&2
  exit 1
}

start_port_forward() {
  local port="$1"
  local log_file="$2"
  : > "${log_file}"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${port}:8080" >"${log_file}" 2>&1 &
  PF_PID=$!
  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${log_file}" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${port}" >&2
      cat "${log_file}" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "[FAIL] port-forward did not bind local port ${port}" >&2
  cat "${log_file}" >&2 || true
  exit 1
}

stop_port_forward() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}

wait_for_health() {
  local port="$1"
  local target="$2"
  local ready=0
  for _ in $(seq 1 30); do
    if curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
      "http://127.0.0.1:${port}/health" > "${target}.tmp" 2>/dev/null; then
      mv "${target}.tmp" "${target}"
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != "1" ]]; then
    echo "[FAIL] Beagle health endpoint did not become ready on port ${port}" >&2
    exit 1
  fi
}

capture_cluster_health() {
  {
    echo "captured_at=$(date -Iseconds)"
    echo
    echo "## beagle"
    ${KUBECTL} -n "${NAMESPACE}" get deploy,svc,pods -l app.kubernetes.io/part-of=beagle -o wide || true
    echo
    echo "## nodes"
    ${KUBECTL} get nodes -o wide || true
    echo
    if command -v scontrol >/dev/null 2>&1; then
      echo "## scontrol-ping"
      scontrol ping || true
      echo
    fi
    if command -v sinfo >/dev/null 2>&1; then
      echo "## sinfo"
      sinfo -N -l || true
      echo
    fi
  } > "${OUT}/final-cluster-health.txt"
}

append_lockfile_fingerprint() {
  local current_json="$1"
  local relative_path="$2"
  local file_path="$3"
  local digest
  digest="$(sha256sum "${file_path}" | awk '{print $1}')"
  jq -nc \
    --argjson current "${current_json}" \
    --arg relative_path "${relative_path}" \
    --arg sha256 "${digest}" \
    '$current + [{relative_path: $relative_path, sha256: $sha256}]'
}

cleanup() {
  stop_port_forward
}
trap cleanup EXIT

KUBECTL="$(resolve_kubectl)"
mkdir -p "${OUT}"

REPLAY_EXECUTION_SOURCE_PRESENT=0
RUN_CAPSULE_SOURCE_PRESENT=0
WORKBENCH_RUN_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
REPLAY_REQUEST_SCHEMA_PRESENT=0
REPLAY_EXECUTION_SCHEMA_PRESENT=0
B256_BASE_PRESENT=0

if rg -q "ReplayExecutionReceipt|execute_replay_request|read_latest_replay_execution" "${REPLAY_EXECUTION_SOURCE_FILE}"; then
  REPLAY_EXECUTION_SOURCE_PRESENT=1
fi
if rg -q "source_intent_text|replay_execution_path|source_source_fingerprint" "${RUN_CAPSULE_SOURCE_FILE}"; then
  RUN_CAPSULE_SOURCE_PRESENT=1
fi
if rg -q "orchestrate_workbench_run|WorkbenchRunDispatchRequest|record_run_capsule" "${WORKBENCH_RUN_SOURCE_FILE}"; then
  WORKBENCH_RUN_SOURCE_PRESENT=1
fi
if rg -q "pub mod replay_execution|ReplayExecutionReceipt|execute_replay_request" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/replay-execution|ReplayExecutionRequestBody|workstream_replay_execution_dispatch_handler" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${REPLAY_REQUEST_SCHEMA_FILE}" ]] && REPLAY_REQUEST_SCHEMA_PRESENT=1
[[ -f "${REPLAY_EXECUTION_SCHEMA_FILE}" ]] && REPLAY_EXECUTION_SCHEMA_PRESENT=1
[[ -f "${B256_BASE_OUT}/smoke.json" ]] && B256_BASE_PRESENT=1

LOCAL_PORT="$(choose_local_port "${LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=180s > "${OUT}/rollout-before.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/collaborative-workbench" \
  > "${OUT}/workbench-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-request" \
  > "${OUT}/replay-request-before.json"

WORKSPACE_ID="$(jq -r '.workspace_id' "${OUT}/workbench-before.json")"
SESSION_ID="$(jq -r '.session_id' "${OUT}/workbench-before.json")"
WORKSPACE_ROOT="$(jq -r '.workbench_session.workspace_root // .workspace_root // empty' "${OUT}/workbench-before.json")"
PROBE_REPO_ROOT="${PROBE_REPO_ROOT:-${ROOT}}"
ATTESTED_REPO_ROOT="${ATTESTED_REPO_ROOT:-${WORKSPACE_ROOT:-${PROBE_REPO_ROOT}}}"
REPLAY_RUN_LABEL="${REPLAY_RUN_LABEL:-b257-$(date +%m%d%H%M%S)-replay}"
FORK_RUN_LABEL="${FORK_RUN_LABEL:-${REPLAY_RUN_LABEL}-fork}"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${SESSION_ID}" > "${OUT}/session-id.txt"
echo "${REPLAY_RUN_LABEL}" > "${OUT}/replay-run-label.txt"
echo "${FORK_RUN_LABEL}" > "${OUT}/fork-run-label.txt"

BRANCH="$(git -C "${PROBE_REPO_ROOT}" rev-parse --abbrev-ref HEAD)"
COMMIT="$(git -C "${PROBE_REPO_ROOT}" rev-parse HEAD)"
TREE_ISH="$(git -C "${PROBE_REPO_ROOT}" rev-parse HEAD^{tree})"
if [[ -n "$(git -C "${PROBE_REPO_ROOT}" status --porcelain --untracked-files=no)" ]]; then
  DIRTY_STATE="dirty"
  PATCH_REF="patch-sha256:$(git -C "${PROBE_REPO_ROOT}" diff --no-ext-diff --binary HEAD -- | sha256sum | awk '{print $1}')"
else
  DIRTY_STATE="clean"
  PATCH_REF=""
fi

LOCKFILE_FINGERPRINTS='[]'
for relative_path in \
  Cargo.lock \
  package-lock.json \
  pnpm-lock.yaml \
  yarn.lock \
  bun.lockb \
  uv.lock \
  poetry.lock \
  Manifest.toml; do
  file_path="${PROBE_REPO_ROOT}/${relative_path}"
  if [[ -f "${file_path}" ]]; then
    LOCKFILE_FINGERPRINTS="$(append_lockfile_fingerprint "${LOCKFILE_FINGERPRINTS}" "${relative_path}" "${file_path}")"
  fi
done

SOURCE_FINGERPRINT_PAYLOAD="$(jq -nc \
  --arg repo_root "${ATTESTED_REPO_ROOT}" \
  --arg branch "${BRANCH}" \
  --arg commit "${COMMIT}" \
  --arg tree_ish "${TREE_ISH}" \
  --arg dirty_state "${DIRTY_STATE}" \
  --arg patch_ref "${PATCH_REF}" \
  --argjson lockfile_fingerprints "${LOCKFILE_FINGERPRINTS}" '
  {
    repo_root: (if $repo_root == "" then null else $repo_root end),
    branch: $branch,
    commit: $commit,
    tree_ish: $tree_ish,
    dirty_state: $dirty_state,
    patch_ref: (if $patch_ref == "" then null else $patch_ref end),
    lockfile_fingerprints: $lockfile_fingerprints
  }'
)"
SOURCE_FINGERPRINT="$(printf '%s' "${SOURCE_FINGERPRINT_PAYLOAD}" | sha256sum | awk '{print $1}')"

jq -nc \
  --argjson replay_execution_source_present "${REPLAY_EXECUTION_SOURCE_PRESENT}" \
  --argjson run_capsule_source_present "${RUN_CAPSULE_SOURCE_PRESENT}" \
  --argjson workbench_run_source_present "${WORKBENCH_RUN_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson replay_request_schema_present "${REPLAY_REQUEST_SCHEMA_PRESENT}" \
  --argjson replay_execution_schema_present "${REPLAY_EXECUTION_SCHEMA_PRESENT}" \
  --argjson b256_base_present "${B256_BASE_PRESENT}" \
  --arg probe_repo_root "${PROBE_REPO_ROOT}" \
  --arg attested_repo_root "${ATTESTED_REPO_ROOT}" \
  --arg branch "${BRANCH}" \
  --arg commit "${COMMIT}" \
  --arg tree_ish "${TREE_ISH}" \
  --arg dirty_state "${DIRTY_STATE}" \
  --arg patch_ref "${PATCH_REF}" \
  --arg source_fingerprint "${SOURCE_FINGERPRINT}" \
  --argjson lockfile_fingerprints "${LOCKFILE_FINGERPRINTS}" '
  {
    replay_execution_source_present: $replay_execution_source_present,
    run_capsule_source_present: $run_capsule_source_present,
    workbench_run_source_present: $workbench_run_source_present,
    lib_source_present: $lib_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    replay_request_schema_present: $replay_request_schema_present,
    replay_execution_schema_present: $replay_execution_schema_present,
    b256_base_present: $b256_base_present,
    probe_repo_root: $probe_repo_root,
    attested_repo_root: $attested_repo_root,
    expected_branch: $branch,
    expected_commit: $commit,
    expected_tree_ish: $tree_ish,
    expected_dirty_state: $dirty_state,
    expected_patch_ref: (if $patch_ref == "" then null else $patch_ref end),
    expected_source_fingerprint: $source_fingerprint,
    expected_lockfile_fingerprints: $lockfile_fingerprints
  }' > "${OUT}/source-summary.json"

jq -nc \
  --arg run_label "${REPLAY_RUN_LABEL}" \
  --arg attested_repo_root "${ATTESTED_REPO_ROOT}" \
  --arg branch "${BRANCH}" \
  --arg commit "${COMMIT}" \
  --arg tree_ish "${TREE_ISH}" \
  --arg dirty_state "${DIRTY_STATE}" \
  --arg patch_ref "${PATCH_REF}" \
  --arg source_fingerprint "${SOURCE_FINGERPRINT}" \
  --argjson lockfile_fingerprints "${LOCKFILE_FINGERPRINTS}" '
  {
    requested_by: "partner-dev",
    requester_role_id: "partner-dev",
    execution_mode: "replay",
    run_label: $run_label,
    reservation_note: "Reserve the bounded partner-dev cpu-short lane for the canonical B25.7 replay execution.",
    dispatch_note: "Dispatch one bounded replay execution through the existing workbench lane so the latest capsule becomes a real replay run.",
    poll_interval_seconds: 5,
    timeout_seconds: 600,
    code_provenance_capture: {
      workspace_snapshot: {
        repo_root: (if $attested_repo_root == "" then null else $attested_repo_root end),
        branch: $branch,
        commit: $commit,
        tree_ish: $tree_ish,
        dirty_state: $dirty_state,
        patch_ref: (if $patch_ref == "" then null else $patch_ref end),
        note: "B25.7 replay execution carries the current workspace attestation so the rerun keeps strong code provenance."
      },
      source_fingerprint: {
        source_fingerprint: $source_fingerprint,
        lockfile_fingerprints: $lockfile_fingerprints,
        note: "B25.7 replay execution carries the current lockfile and source fingerprint attestation."
      }
    }
  }' > "${OUT}/replay-execution-replay-request.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/replay-execution-replay-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-execution" \
  > "${OUT}/replay-execution-replay-response.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule-after-replay.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-request" \
  > "${OUT}/replay-request-after-replay.json"

jq -nc \
  --arg run_label "${FORK_RUN_LABEL}" \
  --arg attested_repo_root "${ATTESTED_REPO_ROOT}" \
  --arg branch "${BRANCH}" \
  --arg commit "${COMMIT}" \
  --arg tree_ish "${TREE_ISH}" \
  --arg dirty_state "${DIRTY_STATE}" \
  --arg patch_ref "${PATCH_REF}" \
  --arg source_fingerprint "${SOURCE_FINGERPRINT}" \
  --argjson lockfile_fingerprints "${LOCKFILE_FINGERPRINTS}" '
  {
    requested_by: "partner-dev",
    requester_role_id: "partner-dev",
    execution_mode: "branch-fork",
    run_label: $run_label,
    reservation_note: "Reserve the bounded partner-dev cpu-short lane for the canonical B25.7 branch fork execution.",
    dispatch_note: "Dispatch one bounded branch fork execution through the same workbench lane so the latest replay can become an explicit fork receipt.",
    poll_interval_seconds: 5,
    timeout_seconds: 600,
    code_provenance_capture: {
      workspace_snapshot: {
        repo_root: (if $attested_repo_root == "" then null else $attested_repo_root end),
        branch: $branch,
        commit: $commit,
        tree_ish: $tree_ish,
        dirty_state: $dirty_state,
        patch_ref: (if $patch_ref == "" then null else $patch_ref end),
        note: "B25.7 branch fork execution carries the current workspace attestation so the fork stays provenance-aware."
      },
      source_fingerprint: {
        source_fingerprint: $source_fingerprint,
        lockfile_fingerprints: $lockfile_fingerprints,
        note: "B25.7 branch fork execution carries the current source fingerprint attestation."
      }
    }
  }' > "${OUT}/replay-execution-fork-request.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/replay-execution-fork-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-execution" \
  > "${OUT}/replay-execution-fork-response.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-execution" \
  > "${OUT}/replay-execution-latest.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule-after-fork.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-diff" \
  > "${OUT}/run-diff-after-fork.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-request" \
  > "${OUT}/replay-request-after-fork.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/replay-execution" \
  > "${OUT}/replay-execution-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule-after-restart.json"

jq -n \
  --slurpfile source_summary "${OUT}/source-summary.json" \
  --slurpfile replay_request_before "${OUT}/replay-request-before.json" \
  --slurpfile replay_response "${OUT}/replay-execution-replay-response.json" \
  --slurpfile run_capsule_after_replay "${OUT}/run-capsule-after-replay.json" \
  --slurpfile replay_request_after_replay "${OUT}/replay-request-after-replay.json" \
  --slurpfile fork_response "${OUT}/replay-execution-fork-response.json" \
  --slurpfile replay_execution_latest "${OUT}/replay-execution-latest.json" \
  --slurpfile run_capsule_after_fork "${OUT}/run-capsule-after-fork.json" \
  --slurpfile run_diff_after_fork "${OUT}/run-diff-after-fork.json" \
  --slurpfile replay_execution_after_restart "${OUT}/replay-execution-after-restart.json" \
  --slurpfile run_capsule_after_restart "${OUT}/run-capsule-after-restart.json" \
  '{
    status: "ok",
    phase: "B25.7",
    workstream_id: $run_capsule_after_fork[0].workstream_id,
    workspace_id: $run_capsule_after_fork[0].workspace_id,
    session_id: $run_capsule_after_fork[0].session_id,
    same_beagle_owned_identity: (
      $replay_response[0].replay_execution.same_beagle_owned_identity and
      $fork_response[0].replay_execution.same_beagle_owned_identity and
      $run_capsule_after_fork[0].same_beagle_owned_identity and
      $run_diff_after_fork[0].same_beagle_owned_identity and
      $replay_execution_after_restart[0].same_beagle_owned_identity
    ),
    replay_source_run_id: $replay_response[0].replay_execution.source_run_id,
    replay_run_id: $replay_response[0].run_orchestration.run.run_id,
    branch_fork_source_run_id: $fork_response[0].replay_execution.source_run_id,
    branch_fork_run_id: $fork_response[0].run_orchestration.run.run_id,
    replay_mode: $replay_response[0].replay_execution.execution_mode,
    branch_fork_mode: $fork_response[0].replay_execution.execution_mode,
    replay_run_label: $replay_response[0].run_orchestration.run.run_label,
    branch_fork_run_label: $fork_response[0].run_orchestration.run.run_label,
    source_branch: $fork_response[0].replay_execution.source_branch,
    source_commit: $fork_response[0].replay_execution.source_commit,
    source_dirty_state: $fork_response[0].replay_execution.source_dirty_state,
    source_source_fingerprint: $fork_response[0].replay_execution.source_source_fingerprint,
    code_diff_explicit: (($run_diff_after_fork[0].code.prior_summary | length) > 0 and ($run_diff_after_fork[0].code.current_summary | length) > 0),
    changed_categories: $run_diff_after_fork[0].changed_categories,
    branch_fork_lineage_relation: $run_diff_after_fork[0].lineage_relation,
    restart_preserved_latest_receipt: (
      $replay_execution_after_restart[0].dispatched_run_id == $fork_response[0].run_orchestration.run.run_id
    ),
    restart_preserved_latest_capsule: (
      $run_capsule_after_restart[0].run_id == $fork_response[0].run_orchestration.run.run_id
    ),
    note: "B25.7 turns the latest replay request into one bounded replay execution path plus one bounded branch fork path, both preserved inside the same Beagle-owned workspace/session identity."
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] replay / branch fork execution smoke artifacts written to ${OUT}"
