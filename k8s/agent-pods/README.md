# Persistent Agent Pods

Unified StatefulSet pattern for persistent AI agents (Claude Code, Codex, local
SGLang agents, custom Beagle agents). One pod per (project, agent-kind) pair.

Agents run in the cluster — not on your laptop — so sessions survive:
- Laptop closing
- Device switching (iPhone → Mac → Vision Pro)
- Network interruptions
- Sleep / wake
- Cluster reboots (PVC preserves state)

## Pattern

Every agent follows the same contract:
1. **StatefulSet** with `replicas: 1`, one pod per (project, kind)
2. **PVC** mounted at `/workspace` — preserves session history, agent state, MCP config
3. **Tmux wrapper** so the agent process can be re-attached
4. **Agent binary** (claude, codex, etc.) runs inside tmux
5. **Cockpit exposes** WebSocket PTY to tmux — any client (web, iOS, Vision Pro) can attach

## Supported agent kinds

| Kind | Binary | Auth | Notes |
|------|--------|------|-------|
| `claude-code` | `claude` | ANTHROPIC_API_KEY or subscription OAuth | Anthropic Claude Code CLI |
| `codex` | `codex` | OPENAI_API_KEY | OpenAI Codex CLI |
| `local-sglang` | custom Rust | none | beagle-agents crate backed by cluster SGLang |
| `custom` | user-defined | depends | Any Beagle agent via manifest |

## Manifest files

- `statefulset.yaml` — templated StatefulSet (use `AGENT_KIND`, `PROJECT_SLUG` substitutions)
- `service.yaml` — ClusterIP service per pod
- `pvc.yaml` — PersistentVolumeClaim for session state
- `entrypoint.sh` — tmux wrapper that starts the correct agent based on AGENT_KIND env var
- `Dockerfile` — multi-stage: Node base + agent binaries + entrypoint

## Lifecycle

1. User clicks "Start Agent Session" in BeagleCockpit
2. Cockpit server POST `/api/projects/:slug/agent/session/start` with `{ kind }`
3. Server applies StatefulSet with rendered manifest
4. Pod starts, entrypoint launches tmux + agent
5. WebSocket gateway (in cockpit server) attaches to tmux via `kubectl exec`
6. Client (iOS, Mac, Vision Pro, web) receives stream via `/ws/projects/:slug/agent/:sessionId`
7. Client disconnects → pod keeps running, state preserved in PVC
8. Any client reconnects → same session resumes (tmux attach)

## Pause / Stop semantics

- **Pause**: scale StatefulSet to 0 replicas. PVC preserved. State intact. Can resume.
- **Stop**: delete StatefulSet + PVC. Session is gone.
- **Restart**: scale back to 1. tmux restores. Agent resumes from where it left off.

## Future: multi-agent debate

With multiple agent pods running in parallel for the same project, the cockpit
can orchestrate Triad-style debates (ATHENA + HERMES + ARGOS + Judge from
beagle-triad) where each participant is a different agent kind.
