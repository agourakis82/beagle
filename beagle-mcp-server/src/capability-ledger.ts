import { BASIC_SCOPES, computeToolManifestHash, toolManifest } from "./tool-manifest.js";
import { activeClientSurface, clientSurfaceSummary } from "./client-profile.js";
import { McpTool } from "./tools/index.js";

export const MCP_MANIFEST_VERSION = "beagle-mcp-v1.4-graphrag-runtime";
export const MCP_SECURITY_PROFILE = "sott-non-destructive-oauth-audited";

export interface CapabilityLedgerState {
    manifest_version: string;
    toolset_id: string;
    security_profile: string;
    client_surfaces: ReturnType<typeof clientSurfaceSummary>;
    active_client_surface: ReturnType<typeof activeClientSurface>;
    latest_manifest_event_id?: string;
}

export function createCapabilityLedgerState(tools: McpTool[]): CapabilityLedgerState {
    return {
        manifest_version: MCP_MANIFEST_VERSION,
        toolset_id: computeToolManifestHash(tools),
        security_profile: MCP_SECURITY_PROFILE,
        client_surfaces: clientSurfaceSummary(),
        active_client_surface: activeClientSurface(),
    };
}

export function capabilityManifest(tools: McpTool[], state: CapabilityLedgerState) {
    return {
        manifest_version: state.manifest_version,
        toolset_id: state.toolset_id,
        security_profile: state.security_profile,
        active_client_surface: state.active_client_surface,
        client_surfaces: state.client_surfaces,
        latest_manifest_event_id: state.latest_manifest_event_id,
        scope_baseline: [...BASIC_SCOPES],
        destructive_scope_reserved: "admin:destructive",
        destructive_actions: "locked",
        tool_manifest_hash: computeToolManifestHash(tools),
        tools: toolManifest(tools),
    };
}
