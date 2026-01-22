#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/systemd/install-beagle-services.sh [options]

Installs BEAGLE Core + MCP systemd services into /etc/systemd/system (by default),
optionally generating example env files under /etc/.

Options:
  --user <name>           Run services as this user (default: demetrios)
  --group <name>          Run services as this group (default: same as --user)
  --dest <dir>            Destination systemd dir (default: /etc/systemd/system)
  --workspace <path>      Write BEAGLE_WORKSPACE_ROOT into env examples (optional)
  --write-env-examples    Create /etc/beagle-*.env if missing (safe; no overwrite)
  --enable                Enable + start services after install (requires systemd)
  -h, --help              Show this help

Notes:
  - This script does NOT build/install binaries or Node deps.
    - Core: install with `cargo install --path apps/beagle-monorepo --bin core_server --locked --root /usr/local`
    - MCP: `cd beagle-mcp-server && npm install && npm run build`
  - Provider/API keys MUST be set via env files, not committed into this repo.
EOF
}

USER_NAME="demetrios"
GROUP_NAME=""
DEST_DIR="/etc/systemd/system"
WORKSPACE_ROOT=""
WRITE_ENV="0"
ENABLE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --group)
      GROUP_NAME="${2:-}"
      shift 2
      ;;
    --dest)
      DEST_DIR="${2:-}"
      shift 2
      ;;
    --workspace)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --write-env-examples)
      WRITE_ENV="1"
      shift
      ;;
    --enable)
      ENABLE="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${USER_NAME}" ]]; then
  echo "--user requires a value" >&2
  exit 2
fi
if [[ -z "${GROUP_NAME}" ]]; then
  GROUP_NAME="${USER_NAME}"
fi
if [[ -z "${DEST_DIR}" ]]; then
  echo "--dest requires a value" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

units=(
  beagle-core.service
  beagle-mcp.service
)

mkdir -p "${DEST_DIR}"

echo "Installing BEAGLE systemd services → ${DEST_DIR}"
echo "User:  ${USER_NAME}"
echo "Group: ${GROUP_NAME}"
echo

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

for unit in "${units[@]}"; do
  src="${SCRIPT_DIR}/${unit}"
  if [[ ! -f "${src}" ]]; then
    echo "Missing unit file: ${src}" >&2
    exit 1
  fi

  dst="${tmp_dir}/${unit}"
  sed \
    -e "s/^User=.*/User=${USER_NAME}/" \
    -e "s/^Group=.*/Group=${GROUP_NAME}/" \
    "${src}" > "${dst}"

  install -m 0644 "${dst}" "${DEST_DIR}/${unit}"
  echo "  ✓ ${unit}"
done

if [[ "${WRITE_ENV}" == "1" ]]; then
  echo
  echo "Writing env examples (only if missing):"

  write_env_file() {
    local path="$1"
    local content="$2"
    if [[ -f "${path}" ]]; then
      echo "  - exists: ${path} (skipping)"
      return 0
    fi
    # Secrets often live here; keep restrictive perms by default.
    install -m 0600 /dev/null "${path}"
    printf "%s\n" "${content}" > "${path}"
    echo "  ✓ wrote: ${path}"
  }

  ws="${WORKSPACE_ROOT}"
  if [[ -z "${ws}" ]]; then
    ws="/home/${USER_NAME}/beagle"
    if [[ "${USER_NAME}" == "root" ]]; then
      ws="/root/beagle"
    fi
  fi
  data_dir="/home/${USER_NAME}/beagle-data"
  if [[ "${USER_NAME}" == "root" ]]; then
    data_dir="/root/beagle-data"
  fi

  write_env_file "/etc/beagle-core.env" "# BEAGLE core env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}
BEAGLE_DATA_DIR=${data_dir}
BEAGLE_PROFILE=lab
BEAGLE_SAFE_MODE=true
BEAGLE_CORE_ADDR=0.0.0.0:8080

# Optional authentication (recommended even in dev/lab):
# BEAGLE_API_TOKEN=your-secret-token

# Darwin job runner needs darwin-* binaries:
DARWIN_BIN_DIR=/usr/local/bin

# GitHub push webhook (HMAC SHA-256):
# GITHUB_WEBHOOK_SECRET=your-github-webhook-secret

# Vector infra
QDRANT_URL=http://localhost:6333
EMBEDDING_URL=http://localhost:8001/v1
EMBEDDING_MODEL=NV-Embed-v2

# Query multiple Darwin collections in one shot (recommended for Exocortex + briefs):
# BEAGLE_QDRANT_COLLECTIONS=darwin-repos,darwin-papers,darwin-docs,darwin-books
# Or single-collection mode:
# BEAGLE_QDRANT_COLLECTION=darwin-repos

# Provider routing (do NOT paste keys in repo):
# BEAGLE_ROUTING_POLICY=minimax-grok-deepseek
# MINIMAX_API_KEY=...
# or:
# BEAGLE_ROUTING_POLICY=zai-grok-deepseek
# ZAI_API_KEY=...
# Fallbacks:
# XAI_API_KEY=...
# DEEPSEEK_API_KEY=...
"

  write_env_file "/etc/beagle-mcp.env" "# BEAGLE MCP env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}

# Connect to BEAGLE core:
BEAGLE_CORE_URL=http://localhost:8080
# Token must match BEAGLE_API_TOKEN (or leave blank in dev/lab if core has no token).
BEAGLE_CORE_API_TOKEN=

# Transport: use http for ChatGPT Apps; use stdio for Claude Desktop.
MCP_TRANSPORT=http
OPENAI_APPS_SDK_ENABLED=true

MCP_HTTP_HOST=0.0.0.0
MCP_HTTP_PORT=3000
MCP_HTTP_PATH=/mcp

# Optional MCP auth (recommended for public/remote access):
# MCP_ENABLE_AUTH=true
# MCP_AUTH_TOKEN=your-mcp-server-token

# Optional DNS rebinding protection (recommended for public/remote access):
# MCP_HTTP_DNS_REBINDING_PROTECTION=true
# MCP_HTTP_ALLOWED_HOSTS=beagle-mcp.yourdomain.com
# MCP_HTTP_ALLOWED_ORIGINS=https://chatgpt.com,https://claude.ai
"
fi

if [[ "${ENABLE}" == "1" ]]; then
  echo
  echo "Enabling services:"
  systemctl daemon-reload
  systemctl enable --now beagle-core.service
  systemctl enable --now beagle-mcp.service
  echo
  echo "Status:"
  systemctl status --no-pager beagle-core.service || true
  systemctl status --no-pager beagle-mcp.service || true
fi

echo
echo "Done."
echo "Debug:"
echo "  journalctl -u beagle-core.service -n 200 --no-pager"
echo "  journalctl -u beagle-mcp.service -n 200 --no-pager"
