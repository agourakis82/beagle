#!/usr/bin/env bash
# Unified agent entrypoint — keeps pod alive for interactive attach.
#
# Required env:
#   AGENT_KIND         — claude-code | codex | local-sglang | custom
#   PROJECT_SLUG       — project identifier (for logging)
#   WORKSPACE_DIR      — mounted PVC path
#
# Design: the pod runs a long-lived idle process. Clients (cockpit server,
# iOS apps, human via kubectl) attach interactively via `kubectl exec -it`.
# No tmux needed — kubectl exec already provides a PTY, and the PVC preserves
# state across pod restarts. This simplifies the container model significantly.

set -euo pipefail

: "${AGENT_KIND:=claude-code}"
: "${PROJECT_SLUG:=unknown}"
: "${WORKSPACE_DIR:=/workspace}"

echo "[entrypoint] ========================================"
echo "[entrypoint] Beagle Agent Pod starting"
echo "[entrypoint] AGENT_KIND=${AGENT_KIND}"
echo "[entrypoint] PROJECT=${PROJECT_SLUG}"
echo "[entrypoint] WORKSPACE=${WORKSPACE_DIR}"
echo "[entrypoint] UID=$(id -u) GID=$(id -g)"
echo "[entrypoint] ========================================"

# Claude Code OAuth auth — materialize from read-only Secret mount into
# writable home location. Claude CLI refreshes tokens in place, so files
# must be writable. We copy (not symlink) to break the read-only link.
CLAUDE_AUTH_SRC="/etc/claude-auth"
if [[ -d "${CLAUDE_AUTH_SRC}" && -f "${CLAUDE_AUTH_SRC}/credentials.json" ]]; then
  mkdir -p /home/agent/.claude
  cp "${CLAUDE_AUTH_SRC}/credentials.json" /home/agent/.claude/.credentials.json
  chmod 600 /home/agent/.claude/.credentials.json
  if [[ -f "${CLAUDE_AUTH_SRC}/claude-config.json" ]]; then
    cp "${CLAUDE_AUTH_SRC}/claude-config.json" /home/agent/.claude.json
    chmod 600 /home/agent/.claude.json
  fi
  echo "[entrypoint] Claude auth materialized from cluster Secret"
  if command -v jq >/dev/null 2>&1; then
    SUB=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' /home/agent/.claude/.credentials.json 2>/dev/null)
    TIER=$(jq -r '.claudeAiOauth.rateLimitTier // "unknown"' /home/agent/.claude/.credentials.json 2>/dev/null)
    echo "[entrypoint] Claude auth: subscription=${SUB}, tier=${TIER}"
  fi
else
  echo "[entrypoint] ⚠ no Claude auth secret mounted — agent will need manual 'claude login'"
fi

# MCP config injection validation
MCP_CONFIG="/home/agent/.config/claude-code/mcp.json"
if [[ -f "${MCP_CONFIG}" ]]; then
  echo "[entrypoint] MCP config injected: ${MCP_CONFIG}"
  grep -E '"command"|"COCKPIT_API"|"COCKPIT_PROJECT"' "${MCP_CONFIG}" || true
else
  echo "[entrypoint] ⚠ no MCP config (cockpit tools unavailable)"
fi

# Ensure workspace is accessible
if [[ -d "${WORKSPACE_DIR}" && -w "${WORKSPACE_DIR}" ]]; then
  echo "[entrypoint] workspace OK: ${WORKSPACE_DIR}"
else
  echo "[entrypoint] ⚠ workspace not writable: ${WORKSPACE_DIR}"
fi

# Agent kind detection (just for logging — actual invocation happens on exec)
case "${AGENT_KIND}" in
  claude-code)
    AGENT_BIN=$(command -v claude || echo "not-installed")
    echo "[entrypoint] claude binary: ${AGENT_BIN}"
    ;;
  codex)
    AGENT_BIN=$(command -v codex || echo "not-installed")
    echo "[entrypoint] codex binary: ${AGENT_BIN}"
    ;;
  local-sglang|custom)
    echo "[entrypoint] kind=${AGENT_KIND} — invocation via exec"
    ;;
esac

# Write a helper script clients can invoke:
#   kubectl exec -it <pod> -- /home/agent/start-agent.sh
cat > /home/agent/start-agent.sh <<'SCRIPT'
#!/usr/bin/env bash
# Invoked by kubectl exec to launch the agent interactively.
cd "${WORKSPACE_DIR:-/workspace}"
case "${AGENT_KIND:-claude-code}" in
  claude-code) exec claude "$@" ;;
  codex)       exec codex "$@" ;;
  *)           exec bash ;;
esac
SCRIPT
chmod +x /home/agent/start-agent.sh

echo "[entrypoint] ready. Attach with:"
echo "    kubectl -n beagle exec -it <pod> -- /home/agent/start-agent.sh"
echo ""

# Hold the pod alive. Session state (history, auth, workspace) persists
# in the PVC across restarts.
exec sleep infinity
