#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/code-provenance-capture}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18496}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"
B255_BASE_OUT="${B255_BASE_OUT:-${ROOT}/.artifacts/darwin-hpc/reproducibility-capsule}"

CODE_PROVENANCE_SOURCE_FILE="${CODE_PROVENANCE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/code_provenance.rs}"
WORKSPACE_SNAPSHOT_SOURCE_FILE="${WORKSPACE_SNAPSHOT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_snapshot.rs}"
SOURCE_FINGERPRINT_SOURCE_FILE="${SOURCE_FINGERPRINT_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/source_fingerprint.rs}"
RUN_CAPSULE_SOURCE_FILE="${RUN_CAPSULE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/run_capsule.rs}"
RUN_DIFF_SOURCE_FILE="${RUN_DIFF_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/run_diff.rs}"
WORKBENCH_RUN_SOURCE_FILE="${WORKBENCH_RUN_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workbench_run.rs}"
WORKSPACE_PLANE_SOURCE_FILE="${WORKSPACE_PLANE_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
LIB_SOURCE_FILE="${LIB_SOURCE_FILE:-${ROOT}/crates/beagle-darwin/src/lib.rs}"
HTTP_SOURCE_FILE="${HTTP_SOURCE_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B256_GIT_AWARE_WORKSPACE_SNAPSHOT_AND_CODE_PROVENANCE_CAPTURE.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B256_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B256_KNOWN_LIMITS.md}"
CODE_PROVENANCE_SCHEMA_FILE="${CODE_PROVENANCE_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/code-provenance-schema.yaml}"
WORKSPACE_SNAPSHOT_SCHEMA_FILE="${WORKSPACE_SNAPSHOT_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/workspace-snapshot-schema.yaml}"
SOURCE_FINGERPRINT_SCHEMA_FILE="${SOURCE_FINGERPRINT_SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/source-fingerprint-schema.yaml}"

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

CODE_PROVENANCE_SOURCE_PRESENT=0
WORKSPACE_SNAPSHOT_SOURCE_PRESENT=0
SOURCE_FINGERPRINT_SOURCE_PRESENT=0
RUN_CAPSULE_SOURCE_PRESENT=0
RUN_DIFF_SOURCE_PRESENT=0
WORKBENCH_RUN_SOURCE_PRESENT=0
WORKSPACE_PLANE_SOURCE_PRESENT=0
LIB_SOURCE_PRESENT=0
HTTP_SOURCE_PRESENT=0
DOC_PRESENT=0
GO_NO_GO_PRESENT=0
KNOWN_LIMITS_PRESENT=0
CODE_PROVENANCE_SCHEMA_PRESENT=0
WORKSPACE_SNAPSHOT_SCHEMA_PRESENT=0
SOURCE_FINGERPRINT_SCHEMA_PRESENT=0
B255_BASE_PRESENT=0

if rg -q "CodeProvenance|capture_code_provenance|CodeProvenanceCaptureRequest" "${CODE_PROVENANCE_SOURCE_FILE}"; then
  CODE_PROVENANCE_SOURCE_PRESENT=1
fi
if rg -q "WorkspaceSnapshot|capture_workspace_snapshot|detect_local_git_snapshot" "${WORKSPACE_SNAPSHOT_SOURCE_FILE}"; then
  WORKSPACE_SNAPSHOT_SOURCE_PRESENT=1
fi
if rg -q "SourceFingerprint|build_source_fingerprint|LockfileFingerprint" "${SOURCE_FINGERPRINT_SOURCE_FILE}"; then
  SOURCE_FINGERPRINT_SOURCE_PRESENT=1
fi
if rg -q "code_provenance|workspace_snapshot|source_fingerprint|read_code_provenance" "${RUN_CAPSULE_SOURCE_FILE}"; then
  RUN_CAPSULE_SOURCE_PRESENT=1
fi
if rg -q "code_state_view|source_fingerprint|lockfile_fingerprints" "${RUN_DIFF_SOURCE_FILE}"; then
  RUN_DIFF_SOURCE_PRESENT=1
fi
if rg -q "code_provenance_capture|record_run_capsule|WorkbenchRunDispatchRequest" "${WORKBENCH_RUN_SOURCE_FILE}"; then
  WORKBENCH_RUN_SOURCE_PRESENT=1
fi
if rg -q "WorkspacePilotResponse|published_result_manifest|requested_run_label" "${WORKSPACE_PLANE_SOURCE_FILE}"; then
  WORKSPACE_PLANE_SOURCE_PRESENT=1
fi
if rg -q "pub mod code_provenance|pub mod source_fingerprint|pub mod workspace_snapshot" "${LIB_SOURCE_FILE}"; then
  LIB_SOURCE_PRESENT=1
fi
if rg -q "/code-provenance|/workspace-snapshot|/source-fingerprint|code_provenance_capture" "${HTTP_SOURCE_FILE}"; then
  HTTP_SOURCE_PRESENT=1
fi
[[ -f "${DOC_FILE}" ]] && DOC_PRESENT=1
[[ -f "${GO_NO_GO_FILE}" ]] && GO_NO_GO_PRESENT=1
[[ -f "${KNOWN_LIMITS_FILE}" ]] && KNOWN_LIMITS_PRESENT=1
[[ -f "${CODE_PROVENANCE_SCHEMA_FILE}" ]] && CODE_PROVENANCE_SCHEMA_PRESENT=1
[[ -f "${WORKSPACE_SNAPSHOT_SCHEMA_FILE}" ]] && WORKSPACE_SNAPSHOT_SCHEMA_PRESENT=1
[[ -f "${SOURCE_FINGERPRINT_SCHEMA_FILE}" ]] && SOURCE_FINGERPRINT_SCHEMA_PRESENT=1
[[ -f "${B255_BASE_OUT}/smoke.json" ]] && B255_BASE_PRESENT=1

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

WORKSPACE_ID="$(jq -r '.workspace_id' "${OUT}/workbench-before.json")"
SESSION_ID="$(jq -r '.session_id' "${OUT}/workbench-before.json")"
WORKSPACE_ROOT="$(jq -r '.workbench_session.workspace_root // .workspace_root // empty' "${OUT}/workbench-before.json")"
PROBE_REPO_ROOT="${PROBE_REPO_ROOT:-${ROOT}}"
ATTESTED_REPO_ROOT="${ATTESTED_REPO_ROOT:-${WORKSPACE_ROOT:-${PROBE_REPO_ROOT}}}"
RUN_LABEL="${RUN_LABEL:-b256-$(date +%m%d%H%M%S)-code-provenance}"

echo "${WORKSPACE_ID}" > "${OUT}/workspace-id.txt"
echo "${SESSION_ID}" > "${OUT}/session-id.txt"
echo "${RUN_LABEL}" > "${OUT}/run-label.txt"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-before.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/session-before.json"

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
  --argjson code_provenance_source_present "${CODE_PROVENANCE_SOURCE_PRESENT}" \
  --argjson workspace_snapshot_source_present "${WORKSPACE_SNAPSHOT_SOURCE_PRESENT}" \
  --argjson source_fingerprint_source_present "${SOURCE_FINGERPRINT_SOURCE_PRESENT}" \
  --argjson run_capsule_source_present "${RUN_CAPSULE_SOURCE_PRESENT}" \
  --argjson run_diff_source_present "${RUN_DIFF_SOURCE_PRESENT}" \
  --argjson workbench_run_source_present "${WORKBENCH_RUN_SOURCE_PRESENT}" \
  --argjson workspace_plane_source_present "${WORKSPACE_PLANE_SOURCE_PRESENT}" \
  --argjson lib_source_present "${LIB_SOURCE_PRESENT}" \
  --argjson http_source_present "${HTTP_SOURCE_PRESENT}" \
  --argjson doc_present "${DOC_PRESENT}" \
  --argjson go_no_go_present "${GO_NO_GO_PRESENT}" \
  --argjson known_limits_present "${KNOWN_LIMITS_PRESENT}" \
  --argjson code_provenance_schema_present "${CODE_PROVENANCE_SCHEMA_PRESENT}" \
  --argjson workspace_snapshot_schema_present "${WORKSPACE_SNAPSHOT_SCHEMA_PRESENT}" \
  --argjson source_fingerprint_schema_present "${SOURCE_FINGERPRINT_SCHEMA_PRESENT}" \
  --argjson b255_base_present "${B255_BASE_PRESENT}" \
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
    code_provenance_source_present: $code_provenance_source_present,
    workspace_snapshot_source_present: $workspace_snapshot_source_present,
    source_fingerprint_source_present: $source_fingerprint_source_present,
    run_capsule_source_present: $run_capsule_source_present,
    run_diff_source_present: $run_diff_source_present,
    workbench_run_source_present: $workbench_run_source_present,
    workspace_plane_source_present: $workspace_plane_source_present,
    lib_source_present: $lib_source_present,
    http_source_present: $http_source_present,
    doc_present: $doc_present,
    go_no_go_present: $go_no_go_present,
    known_limits_present: $known_limits_present,
    code_provenance_schema_present: $code_provenance_schema_present,
    workspace_snapshot_schema_present: $workspace_snapshot_schema_present,
    source_fingerprint_schema_present: $source_fingerprint_schema_present,
    b255_base_present: $b255_base_present,
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
  --arg run_label "${RUN_LABEL}" \
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
    selected_subagent_id: "experiments",
    task_family: "analysis",
    intent_text: "Capture a canonical Git-aware workspace snapshot and bind it to one deterministic workbench run for the B25.6 smoke.",
    compute_profile_id: "cpu-short-v1",
    run_label: $run_label,
    recipe_kind: "code-provenance-capture",
    experiment_id: "b256-code-provenance",
    reservation_note: "Reserve the bounded partner-dev cpu-short lane for the canonical B25.6 code provenance capture run.",
    dispatch_note: "Dispatch one bounded analysis run so the workbench can bind deterministic results to a Git-aware workspace snapshot.",
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
        note: "B25.6 workspace attestation anchored to the canonical Beagle checkout while the runtime captures the same workstream/workspace/session identity."
      },
      source_fingerprint: {
        source_fingerprint: $source_fingerprint,
        lockfile_fingerprints: $lockfile_fingerprints,
        note: "B25.6 workspace attestation carries a stable source fingerprint and lockfile digests for replay-grade provenance."
      }
    }
  }' > "${OUT}/workbench-run-request.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" -H 'Content-Type: application/json' \
  --data @"${OUT}/workbench-run-request.json" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workbench-run" \
  > "${OUT}/workbench-run-dispatch-response.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/code-provenance" \
  > "${OUT}/code-provenance.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-snapshot" \
  > "${OUT}/workspace-snapshot.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/source-fingerprint" \
  > "${OUT}/source-fingerprint.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule-with-code.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-diff" \
  > "${OUT}/run-diff-with-code.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/session?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/workbench-context-after-run.json"

stop_port_forward

${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${SERVICE_NAME}" > "${OUT}/restart.txt"
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${SERVICE_NAME}" --timeout=600s > "${OUT}/rollout-after.txt"

start_port_forward "${LOCAL_PORT}" "${OUT}/port-forward-after.log"
wait_for_health "${LOCAL_PORT}" "${OUT}/health-after.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workspace/bootstrap?workspace_id=${WORKSPACE_ID}" \
  > "${OUT}/bootstrap-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/run-capsule" \
  > "${OUT}/run-capsule-after-restart.json"

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/code-provenance" \
  > "${OUT}/code-provenance-after-restart.json"

jq -n \
  --slurpfile source_summary "${OUT}/source-summary.json" \
  --slurpfile code_provenance "${OUT}/code-provenance.json" \
  --slurpfile workspace_snapshot "${OUT}/workspace-snapshot.json" \
  --slurpfile source_fingerprint "${OUT}/source-fingerprint.json" \
  --slurpfile run_capsule "${OUT}/run-capsule-with-code.json" \
  --slurpfile run_diff "${OUT}/run-diff-with-code.json" \
  --slurpfile dispatch "${OUT}/workbench-run-dispatch-response.json" \
  --slurpfile bootstrap_before "${OUT}/bootstrap-before.json" \
  --slurpfile bootstrap_after "${OUT}/bootstrap-after-restart.json" \
  '{
    status: "ok",
    phase: "B25.6",
    workstream_id: $run_capsule[0].workstream_id,
    workspace_id: $run_capsule[0].workspace_id,
    session_id: $run_capsule[0].session_id,
    same_beagle_owned_identity: (
      $run_capsule[0].same_beagle_owned_identity and
      $code_provenance[0].same_beagle_owned_identity and
      $workspace_snapshot[0].same_beagle_owned_identity and
      $source_fingerprint[0].same_beagle_owned_identity and
      $run_diff[0].same_beagle_owned_identity
    ),
    run_id: $run_capsule[0].run_id,
    parent_run_id: $run_capsule[0].parent_run_id,
    submitted_job_id: $run_capsule[0].submitted_job_id,
    published_result_job_id: $run_capsule[0].published_result_job_id,
    run_label: $run_capsule[0].run_label,
    requester_role_id: $dispatch[0].reservation.requester_role_id,
    selected_subagent_id: $run_capsule[0].selected_subagent_id,
    task_family: $run_capsule[0].task_family,
    compute_profile_id: $run_capsule[0].compute_profile_id,
    branch: $code_provenance[0].branch,
    commit: $code_provenance[0].commit,
    tree_ish: $code_provenance[0].tree_ish,
    dirty_state: $code_provenance[0].dirty_state,
    patch_ref_present: ($code_provenance[0].patch_ref != null),
    source_fingerprint: $source_fingerprint[0].source_fingerprint,
    lockfile_fingerprint_count: ($source_fingerprint[0].lockfile_fingerprints | length),
    code_diff_explicit: (($run_diff[0].code.prior_summary | length) > 0 and ($run_diff[0].code.current_summary | length) > 0),
    code_changed: $run_diff[0].code.changed,
    changed_categories: $run_diff[0].changed_categories,
    deterministic_identity_confirmed: $run_capsule[0].deterministic_identity_confirmed,
    deterministic_result_lookup_scope: $run_capsule[0].deterministic_result_lookup_scope,
    bounded_partner_access: $dispatch[0].run.bounded_partner_access,
    bootstrap_recovered_before: $bootstrap_before[0].recovered_session,
    restart_recovered_session: $bootstrap_after[0].recovered_session,
    note: "B25.6 captures one Git-aware workspace snapshot per deterministic run, binds it into the run capsule, and preserves the same run/code linkage after restart."
  }' > "${OUT}/smoke.json"

capture_cluster_health

echo "[OK] code provenance capture smoke artifacts written to ${OUT}"
