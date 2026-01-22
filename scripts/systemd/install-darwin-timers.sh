#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/systemd/install-darwin-timers.sh [options]

Installs DARWIN systemd services + timers into /etc/systemd/system (by default),
optionally generating example env files under /etc/.

Options:
  --user <name>           Run services as this user (default: demetrios)
  --group <name>          Run services as this group (default: same as --user)
  --dest <dir>            Destination systemd dir (default: /etc/systemd/system)
  --workspace <path>      Write BEAGLE_WORKSPACE_ROOT into env examples (optional)
  --write-env-examples    Create /etc/darwin-*.env if missing (safe; no overwrite)
  --enable                Enable + start timers after install (requires systemd)
  -h, --help              Show this help

Notes:
  - This script does NOT install darwin-* binaries. Use:
      sudo bash scripts/systemd/install-darwin-bins.sh --root /usr/local
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
  darwin-indexer.service
  darwin-indexer.timer
  darwin-research-harvester.service
  darwin-research-harvester.timer
  darwin-web-harvester.service
  darwin-web-harvester.timer
  darwin-knowledge-manager.service
  darwin-knowledge-manager.timer
  darwin-nightly.service
  darwin-nightly.timer
)

mkdir -p "${DEST_DIR}"

echo "Installing DARWIN systemd units → ${DEST_DIR}"
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
  # Replace User/Group defaults safely.
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
  knowledge_dir="/home/${USER_NAME}/knowledge"
  if [[ "${USER_NAME}" == "root" ]]; then
    knowledge_dir="/root/knowledge"
  fi

  write_env_file "/etc/darwin-indexer.env" "# DARWIN indexer env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}
DARWIN_BIN_DIR=/usr/local/bin

QDRANT_URL=http://localhost:6333
EMBEDDING_URL=http://localhost:8001/v1
EMBEDDING_MODEL=NV-Embed-v2

DARWIN_REPOS_DIR=/home/${USER_NAME}/repos
DARWIN_INDEX_STATE_FILE=/home/${USER_NAME}/.darwin_index_state.json
DARWIN_INDEX_ARGS=\"--repo-path ${ws}\"

# Optional repo registry (YAML/TOML/JSON):
# DARWIN_REPOS_FILE=${ws}/scripts/darwin-repos.example.yaml
#
# Optional GitHub discovery (public repos):
# DARWIN_GITHUB_USER=agourakis82
# DARWIN_GITHUB_ORG=darwin-cluster
# DARWIN_GITHUB_ME=true
# DARWIN_GITHUB_INCLUDE_FORKS=false
# DARWIN_GITHUB_API_BASE=https://api.github.com
# DARWIN_GITHUB_TOKEN=...  # or GITHUB_TOKEN / GH_TOKEN
# DARWIN_GITHUB_CLONE_SSH=true

# Optional notifications:
# DARWIN_INDEX_ERROR_WEBHOOK_URL=https://your.webhook/endpoint
# DARWIN_INDEX_SUCCESS_WEBHOOK_URL=https://your.webhook/endpoint

# Optional ingestion ledger:
# DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle
"

  write_env_file "/etc/darwin-harvester.env" "# DARWIN research harvester env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}
DARWIN_BIN_DIR=/usr/local/bin

QDRANT_URL=http://localhost:6333
EMBEDDING_URL=http://localhost:8001/v1
EMBEDDING_MODEL=NV-Embed-v2

# Recommended: topic registry runs
DARWIN_HARVEST_TOPICS_FILE=${ws}/scripts/darwin-research-topics.yaml
DARWIN_HARVEST_ARGS=\"--topics-file ${ws}/scripts/darwin-research-topics.yaml --backend all\"

# Optional ingestion ledger:
# DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle
"

  write_env_file "/etc/darwin-web.env" "# DARWIN web harvester env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}
DARWIN_BIN_DIR=/usr/local/bin

QDRANT_URL=http://localhost:6333
EMBEDDING_URL=http://localhost:8001/v1
EMBEDDING_MODEL=NV-Embed-v2

# Example: seed a sources file (URLs only; crawl disabled by default)
DARWIN_WEB_SOURCES_FILE=${ws}/scripts/darwin-web-sources.example.yaml
DARWIN_WEB_HARVEST_ARGS=\"--sources-file ${ws}/scripts/darwin-web-sources.example.yaml --max-urls 50 --crawl-depth 0\"

# Alternative (curated SOTA-ish seeds):
# DARWIN_WEB_SOURCES_FILE=${ws}/scripts/darwin-web-sources.sota.yaml
# DARWIN_WEB_HARVEST_ARGS=\"--sources-file ${ws}/scripts/darwin-web-sources.sota.yaml --max-urls 100 --crawl-depth 0\"

# Optional ingestion ledger:
# DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle
"

  write_env_file "/etc/darwin-nightly.env" "# DARWIN nightly workflow env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}
DARWIN_BIN_DIR=/usr/local/bin

# Toggle steps
DARWIN_NIGHTLY_RUN_INDEXER=0
DARWIN_NIGHTLY_RUN_RESEARCH=1
DARWIN_NIGHTLY_RUN_WEB=0
DARWIN_NIGHTLY_RUN_BRIEF=1
DARWIN_NIGHTLY_RUN_EVAL=1

# Optional: provider routing (do NOT paste keys in repo)
# BEAGLE_ROUTING_POLICY=minimax-grok-deepseek
# MINIMAX_API_KEY=...
# or:
# BEAGLE_ROUTING_POLICY=zai-grok-deepseek
# ZAI_API_KEY=...

# Briefs
DARWIN_BRIEF_ARGS=\"--topics-file ${ws}/scripts/darwin-research-topics.yaml --delta-days 7\"

# Eval
DARWIN_EVAL_FILE=${ws}/scripts/darwin-eval.yaml
DARWIN_EVAL_ARGS=\"--eval-file ${ws}/scripts/darwin-eval.yaml --k 10 --max-mrr-drop 0.05\"

# Optional notifications:
# DARWIN_NIGHTLY_ERROR_WEBHOOK_URL=https://your.webhook/endpoint
# DARWIN_NIGHTLY_SUCCESS_WEBHOOK_URL=https://your.webhook/endpoint
"

  write_env_file "/etc/darwin-knowledge.env" "# DARWIN knowledge manager env (edit values)
BEAGLE_WORKSPACE_ROOT=${ws}
DARWIN_BIN_DIR=/usr/local/bin

QDRANT_URL=http://localhost:6333
EMBEDDING_URL=http://localhost:8001/v1
EMBEDDING_MODEL=NV-Embed-v2

# Base directory with papers/, docs/, books/ (create with scripts/setup_knowledge_dirs.sh)
DARWIN_KNOWLEDGE_DIR=${knowledge_dir}
DARWIN_KNOWLEDGE_ARGS=\"scan ${knowledge_dir}\"

# Optional ingestion ledger:
# DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle

# Notes:
# - PDFs require: pdftotext (Ubuntu: sudo apt-get install -y poppler-utils)
"
fi

echo
echo "Reloading systemd daemon..."
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl daemon-reload; then
    echo "warning: systemctl daemon-reload failed (is systemd running?): continuing" >&2
  fi
else
  echo "systemctl not found; skipping daemon-reload" >&2
fi

if [[ "${ENABLE}" == "1" ]]; then
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found; cannot enable timers" >&2
    exit 1
  fi

  echo
  echo "Enabling timers..."
  systemctl enable --now darwin-indexer.timer
  systemctl enable --now darwin-research-harvester.timer
  systemctl enable --now darwin-web-harvester.timer
  systemctl enable --now darwin-knowledge-manager.timer
  systemctl enable --now darwin-nightly.timer
  systemctl list-timers | grep -E 'darwin-(indexer|research-harvester|web-harvester|knowledge-manager|nightly)' || true
fi

echo
echo "Done."
echo "Next:"
echo "  - Ensure darwin-* binaries exist (install-darwin-bins.sh)"
echo "  - Edit /etc/darwin-*.env to set Qdrant/Embedding URLs and provider keys"
echo "  - Debug: journalctl -u darwin-nightly.service -n 200 --no-pager"
