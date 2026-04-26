export type McpClientSurface =
    | "claude_trusted_full"
    | "chatgpt_review_safe"
    | "local_tailnet_full";

export interface McpClientSurfacePolicy {
    id: McpClientSurface;
    title: string;
    toolSurface: "trusted_full" | "review_safe";
    publicEndpoint: boolean;
    legacyBearerAllowed: boolean;
    destructiveActions: "locked";
    notes: string;
}

export const CLIENT_SURFACES: Record<McpClientSurface, McpClientSurfacePolicy> = {
    claude_trusted_full: {
        id: "claude_trusted_full",
        title: "Claude trusted-full remote connector",
        toolSurface: "trusted_full",
        publicEndpoint: true,
        legacyBearerAllowed: false,
        destructiveActions: "locked",
        notes:
            "Claude web/Desktop/iOS over OAuth. Broad non-destructive read/write/run access with append-only audit.",
    },
    chatgpt_review_safe: {
        id: "chatgpt_review_safe",
        title: "ChatGPT review-safe connector",
        toolSurface: "review_safe",
        publicEndpoint: true,
        legacyBearerAllowed: false,
        destructiveActions: "locked",
        notes:
            "ChatGPT web review surface focused on search, fetch, Home, memory query, audit, and trust context.",
    },
    local_tailnet_full: {
        id: "local_tailnet_full",
        title: "Local/tailnet full connector",
        toolSurface: "trusted_full",
        publicEndpoint: false,
        legacyBearerAllowed: true,
        destructiveActions: "locked",
        notes:
            "Local agents, Claude Code, Codex, Cursor, and stdio/tailnet launchers. Not a public connector URL.",
    },
};

export function activeClientSurface(): McpClientSurface {
    const explicit = process.env.MCP_CLIENT_SURFACE as McpClientSurface | undefined;
    if (explicit && CLIENT_SURFACES[explicit]) {
        return explicit;
    }
    if (process.env.MCP_TOOL_SURFACE === "review_safe") {
        return "chatgpt_review_safe";
    }
    if (process.env.MCP_ALLOW_LEGACY_BEARER === "false") {
        return "claude_trusted_full";
    }
    return "local_tailnet_full";
}

export function activeClientSurfacePolicy(): McpClientSurfacePolicy {
    return CLIENT_SURFACES[activeClientSurface()];
}

export function clientSurfaceSummary(): McpClientSurfacePolicy[] {
    return Object.values(CLIENT_SURFACES);
}
