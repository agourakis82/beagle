import crypto from "node:crypto";
import { McpTool } from "./tools/index.js";

const FORBIDDEN_DESCRIPTION_PATTERNS = [
    /ignore\s+(all\s+)?previous\s+instructions/i,
    /system\s+prompt/i,
    /developer\s+message/i,
    /do\s+not\s+tell\s+the\s+user/i,
    /\u202a|\u202b|\u202c|\u202d|\u202e|\u2066|\u2067|\u2068|\u2069/,
];

export const BASIC_SCOPES = [
    "exocortex:read",
    "memory:write",
    "chronoself:write",
    "research:run",
    "agent:start",
];

export const DESTRUCTIVE_SCOPE = "admin:destructive";

export interface ToolManifestEntry {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>;
    annotations: NonNullable<McpTool["annotations"]>;
    requiredScopes: string[];
    riskLevel: NonNullable<McpTool["riskLevel"]>;
}

export function toolManifest(tools: McpTool[]): ToolManifestEntry[] {
    return tools
        .map((tool) => ({
            name: tool.name,
            description: tool.description,
            inputSchema: sortJson(tool.inputSchema) as Record<string, unknown>,
            annotations: tool.annotations!,
            requiredScopes: [...(tool.requiredScopes ?? [])].sort(),
            riskLevel: tool.riskLevel!,
        }))
        .sort((a, b) => a.name.localeCompare(b.name));
}

export function computeToolManifestHash(tools: McpTool[]): string {
    const canonical = JSON.stringify(toolManifest(tools));
    return `sha256:${crypto.createHash("sha256").update(canonical).digest("hex")}`;
}

export function validateToolDefinitions(tools: McpTool[]): void {
    const names = new Set<string>();
    const errors: string[] = [];

    for (const tool of tools) {
        if (names.has(tool.name)) {
            errors.push(`${tool.name}: duplicate tool name`);
        }
        names.add(tool.name);

        if (!tool.annotations) {
            errors.push(`${tool.name}: missing annotations`);
        }
        if (!tool.requiredScopes || tool.requiredScopes.length === 0) {
            errors.push(`${tool.name}: missing requiredScopes`);
        }
        if (!tool.riskLevel) {
            errors.push(`${tool.name}: missing riskLevel`);
        }
        if (tool.annotations?.destructiveHint) {
            errors.push(`${tool.name}: destructive tools are locked out of v1.1`);
        }
        if (hasHiddenControlText(tool.description)) {
            errors.push(`${tool.name}: description contains hidden control characters`);
        }
        if (FORBIDDEN_DESCRIPTION_PATTERNS.some((pattern) => pattern.test(tool.description))) {
            errors.push(`${tool.name}: description resembles tool-poisoning instructions`);
        }
    }

    if (errors.length > 0) {
        throw new Error(`Invalid MCP tool manifest:\n${errors.join("\n")}`);
    }
}

function hasHiddenControlText(value: string): boolean {
    return [...value].some((char) => {
        const code = char.charCodeAt(0);
        return code < 32 && !["\n", "\r", "\t"].includes(char);
    });
}

function sortJson(value: unknown): unknown {
    if (Array.isArray(value)) {
        return value.map(sortJson);
    }
    if (value && typeof value === "object") {
        return Object.fromEntries(
            Object.entries(value as Record<string, unknown>)
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([key, child]) => [key, sortJson(child)]),
        );
    }
    return value;
}
