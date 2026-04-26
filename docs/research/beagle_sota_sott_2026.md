# Beagle SOTA/SOTT 2026

Research-first matrix for Beagle Exocortex v1.1.

## Premise

Beagle should not compete by being another chatbot. Its frontier is an operational exocortex: persistent identity, append-only memory, audited agency, embodied Apple context, and a cluster-canonical mind state exposed through MCP.

## Source Anchors

| Area | Anchor | Product Principle |
| --- | --- | --- |
| MCP protocol | [MCP 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25) | MCP is the external nervous system, not a thin adapter. |
| MCP authorization | [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization) | Bearer v1 is acceptable only with explicit scopes, metadata, and a migration path to OAuth-compatible discovery. |
| MCP elicitation | [MCP elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation) | Sensitive confirmation and secrets must stay outside ordinary tool arguments. |
| MCP annotations | [Tool annotations](https://modelcontextprotocol.io/specification/2025-11-25/schema) | Every tool needs explicit read/write/destructive/open-world semantics. |
| Deep research | [OpenAI o3 deep research](https://developers.openai.com/api/docs/models/o3-deep-research) | Deep Research should use MCP to bring Beagle memory into external research systems. |
| Apple local models | [Foundation Models](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) | iPhone 17 Pro Max should do fast local triage, summary, redaction, and capture before cluster escalation. |
| Apple Watch/body | [Watch Connectivity](https://developer.apple.com/documentation/WatchConnectivity) | Watch Ultra 2 is a microinterface and body-context bridge, not a tiny dashboard. |
| Spatial computing | [visionOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos) | visionOS should express memory/temporal structure spatially while preserving comfort. |
| Agent memory | [Memory in AI Agents](https://www.emergentmind.com/papers/2512.13564) | Memory needs episodic, semantic, procedural, temporal, and multi-agent dynamics. |
| MCP security | [Tool-poisoning research](https://arxiv.org/abs/2512.06556) | Tool descriptors are part of the attack surface and need manifest integrity plus runtime audit. |

## SOTA/SOTT Matrix

| Dimension | Common SOTA Pattern | Beagle SOTT Target | v1.1 Implementation Rule |
| --- | --- | --- | --- |
| Personal AI | Chat history plus preference memory | Chronoself identity continuity | Home must show current self, memory signals, trust state, and next action. |
| Agent memory | Vector RAG over notes | Append-only multi-type memory | Keep JSONL event logs canonical; rebuild indexes from events. |
| Agent access | Tool list behind bearer auth | Scoped, audited nervous system | Every MCP tool has annotations, required scopes, risk level, and audit. |
| Security | Prompt-injection disclaimers | Manifest integrity and least-power tools | Block suspicious tool descriptions and hash the published manifest. |
| Research | External deep research as separate product | Research agents grounded in personal memory | MCP resources expose Home, Chronoself, memory, projects, and trust. |
| iPhone | App as mobile client | Intimate capture and local cognition surface | Foundation Models handles quick triage/summaries; cluster stays canonical. |
| Watch | Notifications and health display | Somatic microinterface | Watch captures intent/state and feeds readiness, without pretending to diagnose. |
| macOS/iPad | Larger version of phone UI | Cockpit for agents/jobs/projects | Surface audit, active projects, and agent sessions as operational state. |
| visionOS | Immersive dashboard | Spatial continuity of one mind | Timeline, graph, Go Deep, and Triad stay comfortable and anchored. |

## Risks

- **Tool poisoning:** malicious or drifting tool descriptions can manipulate agents. Mitigation: static descriptions, validation, annotations, manifest hash, audit.
- **Silent agency:** agents write memory without user-visible trace. Mitigation: Home trust context and audit resources.
- **Dashboard collapse:** health/project data appears without interpretation. Mitigation: Home should always connect state to next action.
- **Parallel minds:** each Apple platform builds separate state. Mitigation: cluster remains source of truth; SwiftData is cache only.
- **False OAuth theater:** advertising OAuth without an authorization server creates fake security. Mitigation: expose OAuth-compatible metadata only when configured.

## Acceptance Criteria

- `/.well-known/mcp` exposes tool count, resource count, prompt count, scope policy, and `tool_manifest_hash`.
- `tools/list` returns explicit annotations for every tool.
- Every successful, failed, or scope-denied MCP tool call writes an append-only audit event when the core is reachable.
- `/api/exocortex/v1/home` remains backward-compatible and adds optional `agent_context` and `trust_context`.
- Apple clients decode old and new Home snapshots and surface MCP trust without making the interface busy.
- No destructive irreversible action is available without a future explicit `admin:destructive` path.
