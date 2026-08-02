#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: render-project-workspace.sh [--validate-live] <env-file>

  --validate-live   validate namespace/shared resources against the current cluster
EOF
}

validate_live=false

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
esac

if [[ "${1:-}" == "--validate-live" ]]; then
  validate_live=true
  shift
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

env_file="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${root}/templates/project-workspace.yaml.tmpl"

if [[ ! -f "$env_file" ]]; then
  echo "env file not found: $env_file" >&2
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst is required but not installed" >&2
  exit 1
fi

set -a
if [[ -f "${root}/image-defaults.env" ]]; then
  source "${root}/image-defaults.env"
fi
source "$env_file"
set +a

IDE_IMAGE="${IDE_IMAGE:-${DEFAULT_IDE_IMAGE:-}}"
SSH_IMAGE="${SSH_IMAGE:-${DEFAULT_SSH_IMAGE:-}}"
WORKSPACE_AGENT_IMAGE="${WORKSPACE_AGENT_IMAGE:-${DEFAULT_WORKSPACE_AGENT_IMAGE:-}}"

: "${PROJECT_SLUG:?missing PROJECT_SLUG}"
: "${PROJECT_NAMESPACE:?missing PROJECT_NAMESPACE}"
: "${PROJECT_WORKSTREAM_ID:?missing PROJECT_WORKSTREAM_ID}"
: "${PROJECT_REPO_URL:?missing PROJECT_REPO_URL}"
: "${PROJECT_REPO_BRANCH:?missing PROJECT_REPO_BRANCH}"
: "${PROJECT_STORAGE_CLASS:?missing PROJECT_STORAGE_CLASS}"
: "${PROJECT_STORAGE_SIZE:?missing PROJECT_STORAGE_SIZE}"
: "${WORKSPACE_ID:?missing WORKSPACE_ID}"
: "${SESSION_ID:?missing SESSION_ID}"
: "${WORKSPACE_BROWSER_URL:?missing WORKSPACE_BROWSER_URL}"
: "${IDE_IMAGE:?missing IDE_IMAGE}"
: "${SSH_IMAGE:?missing SSH_IMAGE}"
: "${WORKSPACE_AGENT_IMAGE:?missing WORKSPACE_AGENT_IMAGE}"

PROJECT_MODE="${PROJECT_MODE:-always-on}"
case "$PROJECT_MODE" in
  always-on) PROJECT_REPLICAS=1 ;;
  warm|cold) PROJECT_REPLICAS=0 ;;
  *)
    echo "PROJECT_MODE must be one of: always-on, warm, cold" >&2
    exit 1
    ;;
esac

WORKSPACE_CONFIGMAP_NAME="${WORKSPACE_CONFIGMAP_NAME:-sounio-workspace-config}"
CORE_SECRETS_SECRET_NAME="${CORE_SECRETS_SECRET_NAME:-beagle-core-secrets}"
SSH_AUTHORIZED_KEYS_SECRET_NAME="${SSH_AUTHORIZED_KEYS_SECRET_NAME:-sounio-workspace-ssh-authorized-keys}"
PROJECT_REPO_SECRET_NAME="${PROJECT_REPO_SECRET_NAME:-${PROJECT_SLUG}-repo-auth}"
PROJECT_REPO_SEED_MODE="${PROJECT_REPO_SEED_MODE:-init}"
PROJECT_WORKSPACE_ROOT="${PROJECT_WORKSPACE_ROOT:-/workspace/${PROJECT_SLUG}}"
PROJECT_TMUX_SESSION="${PROJECT_TMUX_SESSION:-${PROJECT_SLUG}-dev}"
PROJECT_AUTO_TMUX_ATTACH="${PROJECT_AUTO_TMUX_ATTACH:-false}"
WORKSPACE_NODE_PREFERENCE="${WORKSPACE_NODE_PREFERENCE:-t560-proxmox}"
WORKSPACE_NODE_SELECTOR="${WORKSPACE_NODE_SELECTOR:-}"
WORKSPACE_EXTRA_TOLERATIONS="${WORKSPACE_EXTRA_TOLERATIONS:-}"
REPO_SEED_IMAGE="${REPO_SEED_IMAGE:-${IDE_IMAGE}}"
DOLLAR='$'
export PROJECT_MODE PROJECT_REPLICAS WORKSPACE_CONFIGMAP_NAME CORE_SECRETS_SECRET_NAME
export SSH_AUTHORIZED_KEYS_SECRET_NAME PROJECT_REPO_SECRET_NAME PROJECT_REPO_SEED_MODE PROJECT_WORKSPACE_ROOT PROJECT_TMUX_SESSION PROJECT_AUTO_TMUX_ATTACH WORKSPACE_NODE_PREFERENCE WORKSPACE_NODE_SELECTOR WORKSPACE_EXTRA_TOLERATIONS REPO_SEED_IMAGE WORKSPACE_AGENT_IMAGE DOLLAR

if [[ -n "$WORKSPACE_NODE_SELECTOR" ]]; then
  WORKSPACE_NODE_BINDING="$(cat <<EOF
      nodeSelector:
        kubernetes.io/hostname: ${WORKSPACE_NODE_SELECTOR}
EOF
)"
else
  WORKSPACE_NODE_BINDING="$(cat <<EOF
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - ${WORKSPACE_NODE_PREFERENCE}
EOF
)"
fi
export WORKSPACE_NODE_BINDING

if [[ -n "$WORKSPACE_EXTRA_TOLERATIONS" ]]; then
  WORKSPACE_TOLERATIONS_BLOCK="$(cat <<EOF
${WORKSPACE_EXTRA_TOLERATIONS}
EOF
)"
else
  WORKSPACE_TOLERATIONS_BLOCK=""
fi
export WORKSPACE_TOLERATIONS_BLOCK

dns1123_re='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'

if [[ ! "$PROJECT_SLUG" =~ $dns1123_re ]]; then
  echo "PROJECT_SLUG must be a DNS-1123 label: $PROJECT_SLUG" >&2
  exit 1
fi

if [[ ! "$PROJECT_NAMESPACE" =~ $dns1123_re ]]; then
  echo "PROJECT_NAMESPACE must be a DNS-1123 label: $PROJECT_NAMESPACE" >&2
  exit 1
fi

if [[ ! "$WORKSPACE_ID" =~ $dns1123_re ]]; then
  echo "WORKSPACE_ID must be a DNS-1123 label: $WORKSPACE_ID" >&2
  exit 1
fi

if [[ ! "$WORKSPACE_BROWSER_URL" =~ ^https?:// ]]; then
  echo "WORKSPACE_BROWSER_URL must start with http:// or https://" >&2
  exit 1
fi

if [[ "$PROJECT_NAMESPACE" != "beagle" ]]; then
  echo "[WARN] current template depends on namespace-local shared resources; non-beagle namespaces need mirrored resources:" >&2
  echo "       configmap/${WORKSPACE_CONFIGMAP_NAME} secret/${CORE_SECRETS_SECRET_NAME} secret/${SSH_AUTHORIZED_KEYS_SECRET_NAME}" >&2
fi

if $validate_live; then
  if ! command -v kubectl >/dev/null 2>&1 && ! command -v sudo >/dev/null 2>&1; then
    echo "kubectl validation requested, but kubectl is not available" >&2
    exit 1
  fi

  kubectl_cmd=(kubectl)
  if ! kubectl version >/dev/null 2>&1; then
    kubectl_cmd=(sudo kubectl)
  fi

  if ! "${kubectl_cmd[@]}" get namespace "$PROJECT_NAMESPACE" >/dev/null 2>&1; then
    echo "namespace does not exist: $PROJECT_NAMESPACE" >&2
    exit 1
  fi

  if ! "${kubectl_cmd[@]}" -n "$PROJECT_NAMESPACE" get configmap "$WORKSPACE_CONFIGMAP_NAME" >/dev/null 2>&1; then
    echo "required configmap missing: ${PROJECT_NAMESPACE}/${WORKSPACE_CONFIGMAP_NAME}" >&2
    exit 1
  fi
fi

tmp_render="$(mktemp)"
trap 'rm -f "$tmp_render"' EXIT
envsubst < "$template" >"$tmp_render"

if $validate_live; then
  "${kubectl_cmd[@]}" apply --dry-run=server -f "$tmp_render" >/dev/null
fi

cat "$tmp_render"
