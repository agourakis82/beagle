#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:?OUT is required}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq

for file in \
  source-summary.json \
  build.log \
  deploy-apply.log \
  deploy-rollout.log \
  workspace-deploy-apply.log \
  workspace-deploy-rollout.log \
  beagle-health-before.json \
  bootstrap-before.json \
  seed-pilot.json \
  physio-ingest-response.json \
  memory-ingest-response.json \
  workspace-context.json \
  workspace-habitat.json \
  workspace-context-env-api.txt \
  cockpit.json \
  tool-cursor.json \
  tool-claude-code.json \
  tool-codex.json \
  workspace-health.txt \
  code-server-healthz.txt \
  code-server-root.html \
  workspace-repo-snapshot.txt \
  workspace-context-packet-file.json \
  workspace-context-env-file.txt \
  workspace-bootstrap-file.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  workspace-context-after-restart.json \
  workspace-habitat-after-restart.json \
  workspace-health-after-restart.txt \
  code-server-healthz-after-restart.txt \
  code-server-root-after-restart.html \
  workspace-repo-snapshot-after-restart.txt \
  workspace-context-packet-file-after-restart.json \
  workspace-context-env-file-after-restart.txt \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  expected-session-id.txt \
  expected-workstream.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-ide-kind.txt \
  expected-browser-url.txt \
  expected-health-url.txt \
  expected-workspace-root.txt \
  expected-context-packet-file.txt \
  expected-context-env-file.txt \
  expected-recommended-recipe-kind.txt \
  expected-provider.txt \
  expected-model.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
EXPECTED_SESSION_ID="$(cat "${OUT}/expected-session-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_IDE_KIND="$(cat "${OUT}/expected-ide-kind.txt")"
EXPECTED_BROWSER_URL="$(cat "${OUT}/expected-browser-url.txt")"
EXPECTED_HEALTH_URL="$(cat "${OUT}/expected-health-url.txt")"
EXPECTED_WORKSPACE_ROOT="$(cat "${OUT}/expected-workspace-root.txt")"
EXPECTED_CONTEXT_PACKET_FILE="$(cat "${OUT}/expected-context-packet-file.txt")"
EXPECTED_CONTEXT_ENV_FILE="$(cat "${OUT}/expected-context-env-file.txt")"
EXPECTED_RECOMMENDED_RECIPE_KIND="$(cat "${OUT}/expected-recommended-recipe-kind.txt")"
EXPECTED_PROVIDER="$(cat "${OUT}/expected-provider.txt")"
EXPECTED_MODEL="$(cat "${OUT}/expected-model.txt")"
SEED_SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_ide_kind "${EXPECTED_IDE_KIND}" \
  --arg expected_browser_url "${EXPECTED_BROWSER_URL}" \
  --arg expected_health_url "${EXPECTED_HEALTH_URL}" \
  --arg expected_workspace_root "${EXPECTED_WORKSPACE_ROOT}" \
  --arg expected_context_packet_file "${EXPECTED_CONTEXT_PACKET_FILE}" \
  --arg expected_context_env_file "${EXPECTED_CONTEXT_ENV_FILE}" '
  .expected_workstream == $expected_workstream
  and .expected_ide_kind == $expected_ide_kind
  and .expected_browser_url == $expected_browser_url
  and .expected_health_url == $expected_health_url
  and .expected_workspace_root == $expected_workspace_root
  and .expected_context_packet_file == $expected_context_packet_file
  and .expected_context_env_file == $expected_context_env_file
  and (.habitat_source_present == true or .habitat_source_present == 1)
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.k8s_present == true or .k8s_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
' "${OUT}/bootstrap-before.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .published_result.job_id == $published_result_job_id
' "${OUT}/seed-pilot.json" >/dev/null

jq -e '.status == "ok" and .snapshot != null' "${OUT}/physio-ingest-response.json" >/dev/null
jq -e '.status == "ok" and .memory_id != null' "${OUT}/memory-ingest-response.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_ide_kind "${EXPECTED_IDE_KIND}" \
  --arg expected_browser_url "${EXPECTED_BROWSER_URL}" \
  --arg expected_health_url "${EXPECTED_HEALTH_URL}" \
  --arg expected_workspace_root "${EXPECTED_WORKSPACE_ROOT}" \
  --arg expected_context_packet_file "${EXPECTED_CONTEXT_PACKET_FILE}" \
  --arg expected_context_env_file "${EXPECTED_CONTEXT_ENV_FILE}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .phase == "B20.1"
  and .habitat.workstream_id == $expected_workstream
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
  and .habitat.repo == $expected_repo
  and .habitat.branch == $expected_branch
  and .habitat.ide_kind == $expected_ide_kind
  and .habitat.browser_url == $expected_browser_url
  and .habitat.health_url == $expected_health_url
  and .habitat.workspace_root == $expected_workspace_root
  and .habitat.context_packet_file == $expected_context_packet_file
  and .habitat.context_env_file == $expected_context_env_file
  and .context_packet.recommended_recipe.kind == $expected_recommended_recipe_kind
  and .context_packet.latest_physio.source != null
  and (
    .context_packet.experiment_flags.provider == null
    or .context_packet.experiment_flags.provider == $expected_provider
  )
  and (
    .context_packet.experiment_flags.model == null
    or .context_packet.experiment_flags.model == $expected_model
  )
  and .context_packet.last_result.summary.job_id == $published_result_job_id
' "${OUT}/workspace-context.json" >/dev/null

grep -Fq "export BEAGLE_WORKSTREAM_ID='${EXPECTED_WORKSTREAM}'" "${OUT}/workspace-context-env-api.txt"
grep -Fq "export BEAGLE_WORKSPACE_ID='${WORKSPACE_ID}'" "${OUT}/workspace-context-env-api.txt"
grep -Fq "export BEAGLE_SESSION_ID='${SEED_SESSION_ID}'" "${OUT}/workspace-context-env-api.txt"
grep -Fq "export BEAGLE_CONTEXT_PACKET_FILE='${EXPECTED_CONTEXT_PACKET_FILE}'" "${OUT}/workspace-context-env-api.txt"
grep -Fq "export BEAGLE_RECOMMENDED_RECIPE_KIND='${EXPECTED_RECOMMENDED_RECIPE_KIND}'" "${OUT}/workspace-context-env-api.txt"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .status == "ok"
  and .context_packet.workspace_id == $workspace_id
  and .context_packet.session_id == $session_id
  and (.tool_dock | length) == 3
' "${OUT}/cockpit.json" >/dev/null

for tool_file in tool-cursor.json tool-claude-code.json tool-codex.json; do
  jq -e \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SEED_SESSION_ID}" \
    --arg expected_browser_url "${EXPECTED_BROWSER_URL}" '
    .status == "ok"
    and .context_packet.workstream_id == $expected_workstream
    and .context_packet.workspace_id == $workspace_id
    and .context_packet.session_id == $session_id
    and .tool.workspace_habitat_path == ("/api/darwin/workstreams/" + $expected_workstream + "/workspace-habitat")
    and .tool.workspace_habitat_env_path == ("/api/darwin/workstreams/" + $expected_workstream + "/workspace-habitat/context.env")
    and .tool.workspace_habitat_browser_url == $expected_browser_url
  ' "${OUT}/${tool_file}" >/dev/null
done

grep -Eq '<!DOCTYPE html>|<html|OpenVSCode|openvscode|workbench' "${OUT}/workspace-health.txt"
grep -Eq '<!DOCTYPE html>|<html|OpenVSCode|openvscode|workbench' "${OUT}/code-server-root.html"
grep -Fq "${EXPECTED_WORKSPACE_ROOT}" "${OUT}/workspace-repo-snapshot.txt"
grep -Fq "cargo_toml=present" "${OUT}/workspace-repo-snapshot.txt"
grep -Fq "darwin_http=present" "${OUT}/workspace-repo-snapshot.txt"
grep -Fq "habitat_k8s=present" "${OUT}/workspace-repo-snapshot.txt"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .packet.workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and .packet.handoff.handoff_present == true
' "${OUT}/workspace-context-packet-file.json" >/dev/null

grep -Fq "export BEAGLE_WORKSPACE_ID='${WORKSPACE_ID}'" "${OUT}/workspace-context-env-file.txt"
grep -Fq "export BEAGLE_SESSION_ID='${SEED_SESSION_ID}'" "${OUT}/workspace-context-env-file.txt"
grep -Fq "export BEAGLE_CONTEXT_PACKET_FILE='${EXPECTED_CONTEXT_PACKET_FILE}'" "${OUT}/workspace-context-env-file.txt"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .workspace_id == $workspace_id
  and .session_id == $session_id
' "${OUT}/workspace-bootstrap-file.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${EXPECTED_SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .status == "ok"
  and .habitat.workspace_id == $workspace_id
  and .habitat.session_id == $session_id
' "${OUT}/workspace-context-after-restart.json" >/dev/null

grep -Eq '<!DOCTYPE html>|<html|OpenVSCode|openvscode|workbench' "${OUT}/workspace-health-after-restart.txt"
grep -Eq '<!DOCTYPE html>|<html|OpenVSCode|openvscode|workbench' "${OUT}/code-server-root-after-restart.html"
grep -Fq "${EXPECTED_WORKSPACE_ROOT}" "${OUT}/workspace-repo-snapshot-after-restart.txt"
grep -Fq "cargo_toml=present" "${OUT}/workspace-repo-snapshot-after-restart.txt"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .packet.workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
' "${OUT}/workspace-context-packet-file-after-restart.json" >/dev/null

grep -Fq "export BEAGLE_WORKSPACE_ID='${WORKSPACE_ID}'" "${OUT}/workspace-context-env-file-after-restart.txt"
grep -Fq "export BEAGLE_SESSION_ID='${SEED_SESSION_ID}'" "${OUT}/workspace-context-env-file-after-restart.txt"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SEED_SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'deployment.apps/beagle-workspace' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] cluster workspace habitat validator passed"
