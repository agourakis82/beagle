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
: "${COCKPIT_API:=http://project-cockpit.beagle.svc.cluster.local}"
: "${COCKPIT_PROJECT:=${PROJECT_SLUG}}"
export COCKPIT_API COCKPIT_PROJECT

echo "[entrypoint] ========================================"
echo "[entrypoint] Beagle Agent Pod starting"
echo "[entrypoint] AGENT_KIND=${AGENT_KIND}"
echo "[entrypoint] PROJECT=${PROJECT_SLUG}"
echo "[entrypoint] WORKSPACE=${WORKSPACE_DIR}"
echo "[entrypoint] COCKPIT_API=${COCKPIT_API}"
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

cat > "${WORKSPACE_DIR}/AGENT_CONTEXT.md" <<'EOF'
# Cockpit Agent Context

This pod uses an isolated agent PVC mounted at `/workspace`.

It is not the live Sounio WIP checkout unless `/workspace/sounio` exists.
For live Sounio development, attach to the promoted workspace service and the
`sounio-dev` Zellij session. Use this pod for MCP, orchestration, reports, and
explicitly submitted jobs.

First command:

```bash
/workspace/whereami
```

Inside Claude Code, call the `cockpit_whereami` MCP tool for cluster truth.
Then call `cockpit_model_registry` before choosing or trusting any local model
lane. The bootstrap guard also materializes a live registry snapshot at:

```bash
/workspace/MODEL_REGISTRY_LIVE.json
/workspace/MODEL_REGISTRY_BOOTSTRAP.md
```
EOF

cat > "${WORKSPACE_DIR}/bootstrap-model-registry" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE_DIR:-/workspace}"
api="${COCKPIT_API:-http://project-cockpit.beagle.svc.cluster.local}"
project="${COCKPIT_PROJECT:-${PROJECT_SLUG:-sounio}}"
json_out="${workspace}/MODEL_REGISTRY_LIVE.json"
summary_out="${workspace}/MODEL_REGISTRY_BOOTSTRAP.md"

if ! command -v node >/dev/null 2>&1; then
  echo "model-registry-bootstrap: node is unavailable; call MCP cockpit_model_registry manually" >&2
  exit 0
fi

node - "${api}" "${project}" "${json_out}" "${summary_out}" <<'NODE'
const fs = require("node:fs");

const [api, project, jsonOut, summaryOut] = process.argv.slice(2);

async function main() {
  const url = `${api.replace(/\/$/, "")}/api/projects/${encodeURIComponent(project)}/inference/model-registry`;
  const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`);
  const packet = await res.json();
  fs.writeFileSync(jsonOut, `${JSON.stringify(packet, null, 2)}\n`);

  const registry = packet.modelRegistry || packet;
  const lanes = Array.isArray(registry.lanes) ? registry.lanes : [];
  const lines = [
    "# Live Model Registry Bootstrap",
    "",
    `generated_at: ${new Date().toISOString()}`,
    `project: ${project}`,
    `truth_mode: ${registry.truthMode || packet.truthMode || "unknown"}`,
    `runtime_status: ${registry.runtimeStatus || "unknown"}`,
    "",
    "Required agent contract:",
    "- Call MCP `cockpit_whereami` for cluster truth.",
    "- Call MCP `cockpit_model_registry` before choosing or trusting local model lanes.",
    "- No model is approved for raw cluster mutation; use `cockpit_action_ledger` and human review.",
    "",
    "Observed lanes:"
  ];

  for (const lane of lanes) {
    const model = lane.model || lane.servedModel || lane.name || "unknown-model";
    const endpoint = lane.endpoint || lane.url || lane.service || "unknown-endpoint";
    const status = lane.status || lane.runtimeStatus || lane.truthMode || "unknown";
    lines.push(`- ${lane.id || "lane"}: ${model} @ ${endpoint} (${status})`);
  }

  fs.writeFileSync(summaryOut, `${lines.join("\n")}\n`);
  console.error(`model-registry-bootstrap: wrote ${jsonOut}`);
}

main().catch((err) => {
  console.error(`model-registry-bootstrap: ${err.message}`);
  process.exit(1);
});
NODE
SCRIPT
chmod +x "${WORKSPACE_DIR}/bootstrap-model-registry"

cat > "${WORKSPACE_DIR}/whereami" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "surface: Cockpit isolated agent pod"
echo "project: ${PROJECT_SLUG:-unknown}"
echo "agent: ${AGENT_KIND:-unknown}"
echo "workspace: ${WORKSPACE_DIR:-/workspace}"
if [[ -d "${WORKSPACE_DIR:-/workspace}/sounio" ]]; then
  echo "repo: ${WORKSPACE_DIR:-/workspace}/sounio"
else
  echo "repo: none mounted here"
  echo "live Sounio WIP: /workspace/sounio inside sounio-workspace-control-0"
fi
if [[ -x "${WORKSPACE_DIR:-/workspace}/bootstrap-model-registry" ]]; then
  "${WORKSPACE_DIR:-/workspace}/bootstrap-model-registry" || true
fi
echo "next: call MCP cockpit_whereami, then cockpit_model_registry, before model decisions"
echo "wip: attach to sounio-dev for live WIP work"
SCRIPT
chmod +x "${WORKSPACE_DIR}/whereami"

"${WORKSPACE_DIR}/bootstrap-model-registry" || true

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
if [[ -x "${WORKSPACE_DIR:-/workspace}/bootstrap-model-registry" ]]; then
  "${WORKSPACE_DIR:-/workspace}/bootstrap-model-registry" || true
fi
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
