#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <always-on|warm|cold> <project-slug> <repo-url> [repo-branch] [namespace]" >&2
}

if [[ $# -lt 3 || $# -gt 5 ]]; then
  usage
  exit 1
fi

mode="$1"
slug="$2"
repo_url="$3"
repo_branch="${4:-main}"
namespace="${5:-beagle}"

case "${mode}" in
  always-on|warm|cold) ;;
  *)
    usage
    echo "invalid mode: ${mode}" >&2
    exit 1
    ;;
esac

if [[ ! "${slug}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "project slug must be lowercase DNS-1123-ish: ${slug}" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog_dir="${root}/catalog/${mode}"
out_file="${catalog_dir}/${slug}.env"
defaults_file="${WORKSPACE_PLATFORM_IMAGE_DEFAULTS_FILE:-${root}/image-defaults.env}"
vsix_render_script="${root}/scripts/render-vsix-pack-env.sh"

default_ide_image="localhost/sounio-workspace-ide:0406231500"
default_ssh_image="localhost/beagle-workspace-ssh:b216"

default_vsix_pack="core-sovereign"
case "${slug}" in
  sounio*) default_vsix_pack="sounio" ;;
  beagle) default_vsix_pack="beagle" ;;
  darwin-pbpk|pbpk|omics*) default_vsix_pack="pbpk-omics" ;;
esac
vsix_pack_file="${root}/vsix-packs/${default_vsix_pack}.project-vsix-pack.json"

if [[ -f "${defaults_file}" ]]; then
  # shellcheck disable=SC1090
  source "${defaults_file}"
fi

ide_image="${DEFAULT_IDE_IMAGE:-${default_ide_image}}"
ssh_image="${DEFAULT_SSH_IMAGE:-${default_ssh_image}}"

project_vsix_pack="${default_vsix_pack}"
project_vsix_pack_version="sov-v1"
project_vsix_required_extensions=""
project_vsix_recommended_extensions=""
project_vsix_experimental_extensions=""
project_ai_ide_agents="[]"

if [[ -x "${vsix_render_script}" && -f "${vsix_pack_file}" ]]; then
  # shellcheck disable=SC1090
  source <("${vsix_render_script}" "${vsix_pack_file}")
  project_vsix_pack="${PROJECT_VSIX_PACK:-${project_vsix_pack}}"
  project_vsix_pack_version="${PROJECT_VSIX_PACK_VERSION:-${project_vsix_pack_version}}"
  project_vsix_required_extensions="${PROJECT_VSIX_REQUIRED_EXTENSIONS:-}"
  project_vsix_recommended_extensions="${PROJECT_VSIX_RECOMMENDED_EXTENSIONS:-}"
  project_vsix_experimental_extensions="${PROJECT_VSIX_EXPERIMENTAL_EXTENSIONS:-}"
  project_ai_ide_agents="${PROJECT_AI_IDE_AGENTS:-${project_ai_ide_agents}}"
fi

mkdir -p "${catalog_dir}"

if [[ -e "${out_file}" ]]; then
  echo "refusing to overwrite existing file: ${out_file}" >&2
  exit 1
fi

workspace_url="http://${slug}-workspace.${namespace}.svc.cluster.local:8080"

cat >"${out_file}" <<EOF
PROJECT_SLUG=${slug}
PROJECT_NAMESPACE=${namespace}
PROJECT_MODE=${mode}
PROJECT_WORKSTREAM_ID=${slug}-main
PROJECT_REPO_URL=${repo_url}
PROJECT_REPO_BRANCH=${repo_branch}
PROJECT_STORAGE_CLASS=ceph-rbd-ssd-rwop
PROJECT_STORAGE_SIZE=50Gi
WORKSPACE_ID=${slug}-workspace
SESSION_ID=${slug}-session
WORKSPACE_BROWSER_URL=${workspace_url}
IDE_IMAGE=${ide_image}
SSH_IMAGE=${ssh_image}
PROJECT_VSIX_PACK=${project_vsix_pack}
PROJECT_VSIX_PACK_VERSION=${project_vsix_pack_version}
PROJECT_VSIX_ENABLE_RECOMMENDED=true
PROJECT_VSIX_ENABLE_EXPERIMENTAL=false
PROJECT_VSIX_REQUIRED_EXTENSIONS=${project_vsix_required_extensions}
PROJECT_VSIX_RECOMMENDED_EXTENSIONS=${project_vsix_recommended_extensions}
PROJECT_VSIX_EXPERIMENTAL_EXTENSIONS=${project_vsix_experimental_extensions}
PROJECT_AI_IDE_AGENTS='${project_ai_ide_agents}'
WORKSPACE_CONFIGMAP_NAME=sounio-workspace-config
CORE_SECRETS_SECRET_NAME=beagle-core-secrets
SSH_AUTHORIZED_KEYS_SECRET_NAME=sounio-workspace-ssh-authorized-keys
PROJECT_REPO_SECRET_NAME=
WORKSPACE_NODE_PREFERENCE=t560-proxmox
EOF

echo "created ${out_file}"
