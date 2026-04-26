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
import { capabilityManifest, CapabilityLedgerState } from "./capability-ledger.js";

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
                        manifest_version: "beagle-mcp-v1.2",
                        toolset_id: computeToolManifestHash(tools),
                        security_profile: "sott-non-destructive-oauth-audited",
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
                        manifest_version: "beagle-mcp-v1.2",
                        toolset_id: computeToolManifestHash(tools),
                        security_profile: "sott-non-destructive-oauth-audited",
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
    ];
}

export async function readResourceAsText(resource: McpResourceDef): Promise<string> {
    const payload = sanitizeOutput(await resource.read());
    return JSON.stringify(payload, null, 2);
}
