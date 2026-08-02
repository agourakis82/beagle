#!/usr/bin/env bash
set -euo pipefail

CATALOG_DIR="${1:-}"
OUT_FILE="${2:-}"

if [[ -z "${CATALOG_DIR}" || -z "${OUT_FILE}" ]]; then
  echo "usage: $0 <catalog-dir> <out-file>" >&2
  exit 1
fi

if [[ ! -d "${CATALOG_DIR}" ]]; then
  echo "catalog directory not found: ${CATALOG_DIR}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_FILE}")"

tmp_json="$(mktemp)"
trap 'rm -f "${tmp_json}"' EXIT

printf '[]\n' > "${tmp_json}"

find "${CATALOG_DIR}" -mindepth 2 -maxdepth 2 -type f -name '*.env' | sort | while read -r env_file; do
  mode="$(basename "$(dirname "${env_file}")")"
  (
    set -a
    # shellcheck disable=SC1090
    . "${env_file}"
    set +a

    project_slug="${PROJECT_SLUG:-unknown}"
    workspace_id="${WORKSPACE_ID:-${PROJECT_SLUG:-unknown}-workspace}"
    session_id="${SESSION_ID:-${PROJECT_SLUG:-unknown}-session}"
    repo_url="${PROJECT_REPO_URL:-}"
    branch="${PROJECT_SOURCE_OF_TRUTH_BRANCH:-${PROJECT_PREFERRED_PR_BASE:-${PROJECT_REPO_BRANCH:-main}}}"
    workspace_bootstrap_branch="${PROJECT_REPO_BRANCH:-main}"
    namespace="${PROJECT_NAMESPACE:-beagle}"
    workspace_browser_url="${WORKSPACE_BROWSER_URL:-http://${workspace_id}.${namespace}.svc.cluster.local:8080}"
    workspace_public_url="${PROJECT_WORKSPACE_PUBLIC_URL:-${WORKSPACE_PUBLIC_URL:-}}"
    ssh_host="${PROJECT_SSH_HOST:-${workspace_id}}"
    tmux_session="${PROJECT_TMUX_SESSION:-${project_slug}-dev}"
    workspace_root="${PROJECT_WORKSPACE_ROOT:-/workspace/${project_slug}}"
    workspace_pod="${PROJECT_WORKSPACE_POD:-${workspace_id}-habitat-0}"
    workspace_container="${PROJECT_WORKSPACE_CONTAINER:-workspace-ide}"
    preferred_pr_base="${PROJECT_PREFERRED_PR_BASE:-main}"
    workstream_id="${PROJECT_WORKSTREAM_ID:-${project_slug}}"
    doctor_command="${PROJECT_DOCTOR_COMMAND:-./ops/workspace-platform-doctor.sh}"
    browser_automation_command="${PROJECT_BROWSER_AUTOMATION_COMMAND:-agent-browser}"
    browser_automation_url="${PROJECT_BROWSER_AUTOMATION_URL:-}"
    browser_automation_public_url="${PROJECT_BROWSER_AUTOMATION_PUBLIC_URL:-}"

    jq \
      --arg mode "${mode}" \
      --arg project_slug "${project_slug}" \
      --arg workspace_id "${workspace_id}" \
      --arg session_id "${session_id}" \
      --arg namespace "${namespace}" \
      --arg repo_url "${repo_url}" \
      --arg branch "${branch}" \
      --arg workspace_bootstrap_branch "${workspace_bootstrap_branch}" \
      --arg workspace_browser_url "${workspace_browser_url}" \
      --arg workspace_public_url "${workspace_public_url}" \
      --arg ssh_host "${ssh_host}" \
      --arg tmux_session "${tmux_session}" \
      --arg workspace_root "${workspace_root}" \
      --arg workspace_pod "${workspace_pod}" \
      --arg workspace_container "${workspace_container}" \
      --arg preferred_pr_base "${preferred_pr_base}" \
      --arg workstream_id "${workstream_id}" \
      --arg env_file "${env_file}" \
      --arg doctor_command "${doctor_command}" \
      --arg browser_automation_command "${browser_automation_command}" \
      --arg browser_automation_url "${browser_automation_url}" \
      --arg browser_automation_public_url "${browser_automation_public_url}" \
      '. += [{
        mode: $mode,
        projectSlug: $project_slug,
        workspaceId: $workspace_id,
        sessionId: $session_id,
        namespace: $namespace,
        repoUrl: $repo_url,
        branch: $branch,
        workspaceBootstrapBranch: $workspace_bootstrap_branch,
        workspaceBrowserUrl: $workspace_browser_url,
        workspacePublicUrl: $workspace_public_url,
        sshHost: $ssh_host,
        tmuxSession: $tmux_session,
        workspaceRoot: $workspace_root,
        workspacePod: $workspace_pod,
        workspaceContainer: $workspace_container,
        preferredPrBase: $preferred_pr_base,
        workstreamId: $workstream_id,
        envFile: $env_file,
        doctorCommand: $doctor_command,
        browserAutomationCommand: $browser_automation_command,
        browserAutomationUrl: $browser_automation_url,
        browserAutomationPublicUrl: $browser_automation_public_url
      }]' \
      "${tmp_json}" > "${tmp_json}.next"
    mv "${tmp_json}.next" "${tmp_json}"
  )
done

jq '{ generatedAt: now | todate, projects: . }' "${tmp_json}" > "${OUT_FILE}"
