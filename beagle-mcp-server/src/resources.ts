/**
 * MCP resources.
 *
 * These expose Beagle's cluster-canonical state as readable URIs, so agents can
 * orient themselves before mutating memory or starting deeper work.
 */

import { BeagleClient } from "./beagle-client.js";
import { sanitizeOutput } from "./security.js";
import { McpTool, toolSurface } from "./tools/index.js";
import { scopePolicy } from "./auth.js";
import { computeToolManifestHash, toolManifest } from "./tool-manifest.js";
import {
    capabilityManifest,
    CapabilityLedgerState,
    MCP_MANIFEST_VERSION,
    MCP_SECURITY_PROFILE,
} from "./capability-ledger.js";

export interface McpResourceDef {
    uri: string;
    name: string;
    description: string;
    mimeType: string;
    read: () => Promise<unknown>;
}

export function defineResources(
    client: BeagleClient,
    tools: McpTool[] = [],
    ledgerState?: CapabilityLedgerState,
): McpResourceDef[] {
    return [
        {
            uri: "beagle://home",
            name: "Exocortex Home",
            description:
                "Cluster-canonical Home snapshot: today's brief, current self, memory signals, body context, truth state, and next action.",
            mimeType: "application/json",
            read: async () => client.exocortexHome(undefined, "mcp-resource"),
        },
        {
            uri: "beagle://chronoself/current",
            name: "Current Chronoself",
            description:
                "Current SelfVersion derived from the append-only Chronoself log.",
            mimeType: "application/json",
            read: async () => client.chronoselfCurrent(),
        },
        {
            uri: "beagle://chronoself/commits",
            name: "Chronoself Commits",
            description:
                "Recent immutable Chronoself commits, newest first.",
            mimeType: "application/json",
            read: async () => client.chronoselfCommits(25),
        },
        {
            uri: "beagle://memory/recent",
            name: "Recent Memory",
            description:
                "Recent memory signals retrieved through the canonical memory API.",
            mimeType: "application/json",
            read: async () =>
                client.memoryQuery("recent Beagle Exocortex memory signals", 10),
        },
        {
            uri: "beagle://memory/graph/status",
            name: "GraphRAG++ Memory Projection Status",
            description:
                "Living GraphRAG++ status: runtime hypothesis, projection freshness, MemoryWorld count, latest bake-off, and degraded retrieval status.",
            mimeType: "application/json",
            read: async () => client.memoryGraphStatus(),
        },
        {
            uri: "beagle://memory/bakeoff/status",
            name: "GraphRAG++ Runtime Bake-Off",
            description:
                "Latest FalkorDB/Memgraph/SurrealDB bake-off status and baseline comparison.",
            mimeType: "application/json",
            read: async () => client.memoryGraphBakeoffStatus(),
        },
        {
            uri: "beagle://memory/worlds/recent",
            name: "Recent MemoryWorlds",
            description:
                "Recent content-addressed MemoryWorlds generated from cluster-canonical Episode+Atom logs.",
            mimeType: "application/json",
            read: async () => client.memoryWorldsRecent(12),
        },
        {
            uri: "beagle://memory/governance/status",
            name: "Memory Governor Status",
            description:
                "Self-governing memory loop status: pending Triad items, promoted/rejected candidates, contradictions, and retrieval policy.",
            mimeType: "application/json",
            read: async () => client.memoryGovernanceStatus(),
        },
        {
            uri: "beagle://memory/bench/status",
            name: "Memory Bench Status",
            description:
                "Latest Memory Bench v1.9 truthset gate, hard gates, evaluated modes, benchmark score, and hot-path eligibility.",
            mimeType: "application/json",
            read: async () => client.memoryBenchmarkStatus(),
        },
        {
            uri: "beagle://memory/bench/latest",
            name: "Latest Memory Bench Run",
            description:
                "Latest cluster-only Memory Bench v1.9 run comparing GraphRAG++ baseline, HyperMemory, and mesh modes against private truthsets.",
            mimeType: "application/json",
            read: async () => client.memoryBenchmarkStatus(),
        },
        {
            uri: "beagle://memory/retrieval/status",
            name: "Retrieval Agent Status",
            description:
                "v2.2 Retrieval Agent status: canary mode, planner mode, semantic backbone readiness, and Private MemoryArena gate.",
            mimeType: "application/json",
            read: async () => ({
                retrieval_agent: process.env.BEAGLE_RETRIEVAL_AGENT || "canary",
                planner_mode: process.env.BEAGLE_RETRIEVAL_PLANNER || "hybrid",
                semantic_index: await client.semanticIndexStatus(),
                memoryarena: await client.memoryArenaStatus(),
            }),
        },
        {
            uri: "beagle://memory/memoryarena/status",
            name: "Private MemoryArena Status",
            description:
                "Latest private MemoryArena-style multi-session memory-action benchmark gate for v2.2 Retrieval Agent.",
            mimeType: "application/json",
            read: async () => client.memoryArenaStatus(),
        },
        {
            uri: "beagle://context/compiler/status",
            name: "Adaptive Context Compiler Status",
            description:
                "v2.3 Context Compiler and memory policy state: policy version, compiler mode, DreamCycle status, and latest Home trust fields.",
            mimeType: "application/json",
            read: async () => {
                const [home, policy, dreamcycle] = await Promise.all([
                    client.exocortexHome(undefined, "mcp-resource-context-compiler"),
                    client.coreMemoryPolicyStatus(),
                    client.coreDreamCycleStatus(),
                ]);
                return { home, policy, dreamcycle };
            },
        },
        {
            uri: "beagle://memory/policy/status",
            name: "Memory Policy Learner Status",
            description:
                "v2.3 Memory Policy Learner status and promotion gate for ContextPack effectiveness.",
            mimeType: "application/json",
            read: async () => client.memoryPolicyStatus(),
        },
        {
            uri: "beagle://memory/dreamcycle/status",
            name: "DreamCycle Status",
            description:
                "v2.3 DreamCycle consolidation status; outputs stay candidate-only until Governor/Triad.",
            mimeType: "application/json",
            read: async () => client.dreamCycleStatus(),
        },
        {
            uri: "beagle://sounio/paperrun/current",
            name: "Current Sounio PaperRun",
            description:
                "Home trust view and recent Sounio PaperRun trace for the self-writing Beagle systems paper.",
            mimeType: "application/json",
            read: async () => {
                const [home, trace] = await Promise.all([
                    client.exocortexHome(undefined, "mcp-resource-sounio-paperrun"),
                    client.sounioTraceQuery(undefined, 25),
                ]);
                return { home, trace };
            },
        },
        {
            uri: "beagle://agent/observer/status",
            name: "Agent Observer Status",
            description:
                "Home trust view for Codex/Claude Code project-file work memory and Apple capture freshness.",
            mimeType: "application/json",
            read: async () => {
                const home = await client.exocortexHome(undefined, "mcp-resource-agent-observer");
                return {
                    generated_at: (home as { generated_at?: unknown }).generated_at,
                    trust_context: (home as { trust_context?: unknown }).trust_context,
                    agent_context: (home as { agent_context?: unknown }).agent_context,
                };
            },
        },
        {
            uri: "beagle://memory/contradictions/recent",
            name: "Recent Memory Contradictions",
            description:
                "Recent contradiction candidates detected by the Memory Governor before promotion into active memory.",
            mimeType: "application/json",
            read: async () => client.memoryContradictions(25),
        },
        {
            uri: "beagle://work/current",
            name: "Current Work Memory",
            description:
                "Current Codex/Claude Code work-memory view from recent memory events, audit events, and active projects.",
            mimeType: "application/json",
            read: async () => ({
                recent_memory_events: await client.recentMemoryEvents(25),
                recent_audit_events: await client.recentAuditEvents(25),
                active_projects: await client.activeProjects(),
            }),
        },
        {
            uri: "beagle://projects/active",
            name: "Active Projects",
            description:
                "Active project reference and project-shaped signals visible in the current Home snapshot.",
            mimeType: "application/json",
            read: async () => {
                const home = await client.exocortexHome(undefined, "mcp-resource");
                return {
                    source: "exocortex_home",
                    home,
                };
            },
        },
        {
            uri: "beagle://cluster/truth",
            name: "Cluster Truth",
            description:
                "Health/readiness view of the cluster truth source used by MCP agents.",
            mimeType: "application/json",
            read: async () => ({
                core_url: client.baseUrl,
                core_health: await client.health(),
                mcp_policy: {
                    authenticated_agents: "broad read/write operational access in v1",
                    destructive_actions:
                        "reserved for explicit future scopes plus audit log",
                    scope_policy: scopePolicy(),
                    tool_surface: toolSurface(),
                },
            }),
        },
        {
            uri: "beagle://mcp/tool_manifest",
            name: "MCP Tool Manifest",
            description:
                "Stable manifest of tools, annotations, required scopes, risk levels, and manifest hash.",
            mimeType: "application/json",
            read: async () => ({
                tool_manifest_hash: computeToolManifestHash(tools),
                tools: toolManifest(tools),
            }),
        },
        {
            uri: "beagle://mcp/manifest/current",
            name: "Current MCP Capability Manifest",
            description:
                "Current capability ledger manifest: version, toolset id, security profile, client surfaces, scopes, and tools.",
            mimeType: "application/json",
            read: async () =>
                capabilityManifest(
                    tools,
                    ledgerState ?? {
                        manifest_version: MCP_MANIFEST_VERSION,
                        toolset_id: computeToolManifestHash(tools),
                        security_profile: MCP_SECURITY_PROFILE,
                        active_client_surface: "local_tailnet_full",
                        client_surfaces: [],
                    },
                ),
        },
        {
            uri: "beagle://mcp/manifest/history",
            name: "MCP Manifest History",
            description:
                "Recent append-only manifest registration events from the Beagle core audit log.",
            mimeType: "application/json",
            read: async () => ({
                filter_hint: "action == mcp/tool_manifest",
                recent_audit_events: await client.recentAuditEvents(50),
            }),
        },
        {
            uri: "beagle://mcp/audit/recent",
            name: "Recent MCP Audit Events",
            description:
                "Recent append-only audit events written by MCP tool calls.",
            mimeType: "application/json",
            read: async () => client.recentAuditEvents(25),
        },
        {
            uri: "beagle://agents/current",
            name: "Current MCP Agent Surface",
            description:
                "Current MCP principal/capability surface inferred from runtime policy.",
            mimeType: "application/json",
            read: async () => ({
                active_client_surface: ledgerState?.active_client_surface,
                scope_policy: scopePolicy(),
                tool_surface: toolSurface(),
                destructive_actions: "locked",
            }),
        },
        {
            uri: "beagle://agents/recent",
            name: "Recent MCP Agent Activity",
            description:
                "Recent agent-shaped MCP audit events and active project sessions.",
            mimeType: "application/json",
            read: async () => ({
                recent_audit_events: await client.recentAuditEvents(50),
                active_projects: await client.activeProjects(),
            }),
        },
        {
            uri: "beagle://capabilities/current",
            name: "Current MCP Capabilities",
            description:
                "Current MCP capability grants, surfaces, scopes, destructive-action policy, and tool manifest.",
            mimeType: "application/json",
            read: async () => ({
                capability_manifest: capabilityManifest(
                    tools,
                    ledgerState ?? {
                        manifest_version: MCP_MANIFEST_VERSION,
                        toolset_id: computeToolManifestHash(tools),
                        security_profile: MCP_SECURITY_PROFILE,
                        active_client_surface: "local_tailnet_full",
                        client_surfaces: [],
                    },
                ),
                scope_policy: scopePolicy(),
                tool_surface: toolSurface(),
            }),
        },
        {
            uri: "beagle://trust/current",
            name: "Current Trust Context",
            description:
                "Current trust state: MCP readiness, tool manifest hash, scopes, and destructive-action policy.",
            mimeType: "application/json",
            read: async () => {
                const home = await client.exocortexHome(undefined, "mcp-resource");
                return {
                    tool_manifest_hash: computeToolManifestHash(tools),
                    scope_policy: scopePolicy(),
                    tool_surface: toolSurface(),
                    public_base_url: process.env.MCP_PUBLIC_BASE_URL,
                    public_discovery: process.env.MCP_PUBLIC_DISCOVERY === "true",
                    home,
                };
            },
        },
        {
            uri: "beagle://sounio/workday/current",
            name: "Current Sounio Workday",
            description:
                "Current ambient Sounio workday: moments, decision seeds, Claim<T> seeds, tensions, agents, evidence, review queue, and next gesture.",
            mimeType: "application/json",
            read: async () => client.sounioWorkdayStatus("sounio", 20),
        },
        {
            uri: "beagle://sounio/moments/recent",
            name: "Recent Sounio Moments",
            description:
                "Recent append-only ambient Sounio moments derived from Beagle captures, Codex/Claude work memory, Claude iOS, Watch microintentions, and Apple captures.",
            mimeType: "application/json",
            read: async () => client.sounioMomentsRecent(25, "sounio"),
        },
    ];
}

export async function readResourceAsText(resource: McpResourceDef): Promise<string> {
    const payload = sanitizeOutput(await resource.read());
    return JSON.stringify(payload, null, 2);
}
