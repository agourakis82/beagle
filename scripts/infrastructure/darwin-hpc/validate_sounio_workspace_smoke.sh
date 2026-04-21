#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-}"
if [[ -z "${OUT}" ]]; then
  echo "[FAIL] OUT is required" >&2
  exit 1
fi

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq

for file in \
  beagle-health.json \
  workspace-root.html \
  workspace-habitat.json \
  workspace-launch-resume.json \
  launch-summary.json \
  workspace-context.env \
  workspace-context-packet.json \
  remote-command.txt \
  make-check.log \
  workspace-hydration.json \
  workspace-template.json \
  workspace-registration.json \
  workspace-root-after-restart.html \
  workspace-habitat-after-restart.json \
  launch-summary-after-restart.json \
  workspace-context-after-restart.env \
  workspace-context-after-restart.json \
  remote-command-after-restart.txt \
  smoke.json \
  final-cluster-health.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSTREAM_ID="$(jq -r '.workstream_id' "${OUT}/smoke.json")"
WORKSPACE_ID="$(jq -r '.workspace_id' "${OUT}/smoke.json")"
SESSION_ID="$(jq -r '.session_id' "${OUT}/smoke.json")"
EXPECTED_REPO_URL="$(jq -r '.expected_repo_url' "${OUT}/smoke.json")"
EXPECTED_BRANCH="$(jq -r '.expected_branch' "${OUT}/smoke.json")"
EXPECTED_ROOT="$(jq -r '.expected_root' "${OUT}/smoke.json")"
EXPECTED_ATTACH_ALIAS="$(jq -r '.expected_attach_alias' "${OUT}/smoke.json")"

jq -e '.status == "ok" and .phase == "B26.7"' "${OUT}/smoke.json" >/dev/null
jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_root "${EXPECTED_ROOT}" '
  .status == "ok"
  and .habitat.workstream_id == $workstream_id
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
  and .habitat.workspace_root == $expected_root
' "${OUT}/workspace-habitat.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .launch.workstream_id == $workstream_id
  and .launch.workspace_id == $workspace_id
  and .launch.session_id == $session_id
  and .launch.launch_metadata.cursor_managed_attach_ready == true
' "${OUT}/workspace-launch-resume.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_attach_alias "${EXPECTED_ATTACH_ALIAS}" '
  .status == "ok"
  and .workstream_id == $workstream_id
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .attach_host_alias == $expected_attach_alias
  and .managed_attach_state == "coder-compatible-ready"
' "${OUT}/launch-summary.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_branch "${EXPECTED_BRANCH}" '
  .status == "ok"
  and .packet.workstream_id == $workstream_id
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and .packet.branch == $expected_branch
' "${OUT}/workspace-context-packet.json" >/dev/null

grep -Fq "${EXPECTED_ROOT}" "${OUT}/remote-command.txt"
grep -Fq "true" "${OUT}/remote-command.txt"
grep -Fq "${EXPECTED_REPO_URL}" "${OUT}/remote-command.txt"
grep -Fq "${EXPECTED_BRANCH}" "${OUT}/remote-command.txt"
grep -Fq "SOUC_OK" "${OUT}/remote-command.txt"
grep -Fq "souc native-wrapper" "${OUT}/remote-command.txt"

grep -Fq "Type-checking self-hosted/compiler/lean_single.sio" "${OUT}/make-check.log"
grep -Eq "Running lint gates|OK|PASS" "${OUT}/make-check.log"

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workstream_id == $workstream_id
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .startup_mode != "prehydrated-snapshot"
' "${OUT}/workspace-hydration.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" '
  .status == "ok"
  and .workstream_id == $workstream_id
  and .workspace_id == $workspace_id
  and .stable_workspace_alias == ($workspace_id + ".coder")
' "${OUT}/workspace-registration.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .habitat.workstream_id == $workstream_id
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
' "${OUT}/workspace-habitat-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workstream_id == $workstream_id
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .managed_attach_state == "coder-compatible-ready"
' "${OUT}/launch-summary-after-restart.json" >/dev/null

jq -e \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .packet.workstream_id == $workstream_id
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
' "${OUT}/workspace-context-after-restart.json" >/dev/null

grep -Fq "${EXPECTED_REPO_URL}" "${OUT}/remote-command-after-restart.txt"
grep -Fq "${EXPECTED_BRANCH}" "${OUT}/remote-command-after-restart.txt"
grep -Fq "souc native-wrapper" "${OUT}/remote-command-after-restart.txt"

grep -Eq 'sounio-workspace|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'cpu|gpu' "${OUT}/final-cluster-health.txt"

echo "[OK] sounio workspace smoke validated"
