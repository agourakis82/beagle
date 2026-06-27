#!/usr/bin/env node
/**
 * BEAGLE MCP Server
 *
 * A real MCP boundary for the cluster-canonical Beagle exocortex:
 * - stdio for Claude Desktop, Claude Code, Cursor, Codex, and local agents
 * - Streamable HTTP at /mcp for remote compatible agents
 * - tools, resources, and prompts over the same Beagle core contract
 */

import { readFile } from "node:fs/promises";
import http, { IncomingMessage, ServerResponse } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
    CallToolRequestSchema,
    ErrorCode,
    GetPromptRequestSchema,
    ListPromptsRequestSchema,
    ListResourcesRequestSchema,
    ListToolsRequestSchema,
    McpError,
    ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import dotenv from "dotenv";
import { BeagleClient } from "./beagle-client.js";
import { defineTools, McpTool, toolSurface } from "./tools/index.js";
import { defineResources, McpResourceDef, readResourceAsText } from "./resources.js";
import { definePrompts, McpPromptDef } from "./prompts.js";
import {
    computeToolManifestHash,
    validateToolDefinitions,
} from "./tool-manifest.js";
import {
    capabilityManifest,
    CapabilityLedgerState,
    createCapabilityLedgerState,
} from "./capability-ledger.js";
import { activeClientSurfacePolicy } from "./client-profile.js";
import { logger } from "./logger.js";
import {
    assertRequiredScopes,
    checkRateLimit,
    extractToken,
    isAuthEnabled,
    isOAuthEnabled,
    McpPrincipal,
    scopePolicy,
    validateAuth,
    wwwAuthenticateHeader,
} from "./auth.js";
import { getClientInfo, getTransportType } from "./compat.js";
import {
    configureForClaudeDesktop,
    createClaudeDesktopTransport,
} from "./transports/claude-desktop.js";
import {
    addOpenAiMetadata,
    configureForOpenAiApps,
    createOpenAiStdioTransport,
} from "./transports/openai-apps.js";

dotenv.config();

const SERVER_NAME = "beagle-mcp-server";
const SERVER_VERSION = "0.4.0";
const MCP_PATH = "/mcp";
const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));

interface RuntimeContext {
    client: BeagleClient;
    tools: McpTool[];
    resources: McpResourceDef[];
    prompts: McpPromptDef[];
    toolManifestHash: string;
    ledgerState: CapabilityLedgerState;
}

function numberEnv(name: string, fallback: number): number {
    const value = Number.parseInt(process.env[name] || "", 10);
    return Number.isFinite(value) ? value : fallback;
}

function createRuntimeContext(): RuntimeContext {
    const client = new BeagleClient(
        process.env.BEAGLE_CORE_URL || "http://localhost:8080",
        process.env.BEAGLE_CORE_API_TOKEN || undefined,
        numberEnv("HTTP_TIMEOUT", 60000),
        numberEnv("HTTP_MAX_RETRIES", 2),
        process.env.BEAGLE_COCKPIT_URL || undefined,
    );
    const tools = defineTools(client);
    validateToolDefinitions(tools);
    const toolManifestHash = computeToolManifestHash(tools);
    const ledgerState = createCapabilityLedgerState(tools);
    return {
        client,
        tools,
        resources: defineResources(client, tools, ledgerState),
        prompts: definePrompts(),
        toolManifestHash,
        ledgerState,
    };
}

function headerValue(headers: unknown, name: string): string | undefined {
    if (!headers || typeof headers !== "object") return undefined;
    const record = headers as Record<string, string | string[] | undefined>;
    const direct = record[name] ?? record[name.toLowerCase()];
    if (Array.isArray(direct)) return direct[0];
    return direct;
}

function requestMeta(request: unknown): Record<string, unknown> | undefined {
    const params = (request as { params?: { _meta?: Record<string, unknown> } }).params;
    return params?._meta ?? (request as { meta?: Record<string, unknown> }).meta;
}

async function authorizeRequest(
    request: unknown,
    extra: { requestInfo?: { headers?: unknown }; sessionId?: string },
    action: string,
    options: { allowAnonymousDiscovery?: boolean } = {},
): Promise<{ clientId: string; remaining?: number; scopes: string[]; principal?: McpPrincipal }> {
    const meta = requestMeta(request);
    const headers = extra.requestInfo?.headers;
    const authHeader =
        headerValue(headers, "authorization") ??
        (typeof meta?.authorization === "string" ? meta.authorization : undefined);
    const token = extractToken(authHeader);
    const authResult = await validateAuth(token);
    if (!authResult.valid) {
        if (options.allowAnonymousDiscovery && !token) {
            logger.info(`MCP ${action}`, {
                clientId: "anonymous-discovery",
                auth: isAuthEnabled() ? "discovery" : "disabled",
                scopes: [],
            });
            return { clientId: "anonymous-discovery", scopes: [] };
        }
        throw new McpError(
            ErrorCode.InvalidRequest,
            authResult.error || "Authentication required",
        );
    }

    const clientId =
        headerValue(headers, "x-client-id") ??
        authResult.clientId ??
        headerValue(headers, "cf-connecting-ip") ??
        headerValue(headers, "x-forwarded-for")?.split(",")[0]?.trim() ??
        extra.sessionId ??
        (typeof meta?.clientId === "string" ? meta.clientId : undefined) ??
        "stdio";
    const rateLimitResult = checkRateLimit(clientId);
    if (!rateLimitResult.allowed) {
        throw new McpError(
            ErrorCode.InvalidRequest,
            "Rate limit exceeded. Please try again later.",
        );
    }

    logger.info(`MCP ${action}`, {
        clientId,
        auth: isAuthEnabled() ? "enabled" : "disabled",
        remaining: rateLimitResult.remaining,
        scopes: authResult.scopes,
    });
    return {
        clientId,
        remaining: rateLimitResult.remaining,
        scopes: authResult.scopes,
        principal: authResult.principal,
    };
}

function publicDiscoveryEnabled(): boolean {
    return process.env.MCP_PUBLIC_DISCOVERY === "true" || isOAuthEnabled();
}

function clientIdFromHttpHeaders(headers: unknown, fallback: string): string {
    return (
        headerValue(headers, "x-client-id") ??
        headerValue(headers, "cf-connecting-ip") ??
        headerValue(headers, "x-forwarded-for")?.split(",")[0]?.trim() ??
        fallback
    );
}

// Server-side behavior directive sent to the client in the MCP `initialize` result.
// Claude Desktop injects this into the model's context, making the bridge act as the
// user's continuous cross-surface memory: silently recall at start, silently persist as
// the conversation goes. By the user's explicit choice this is one unified intimate memory.
const BEAGLE_BRIDGE_INSTRUCTIONS = `Beagle is Demetrios's personal exocortex — his sovereign, cross-surface memory. This server is the live bridge between Claude Desktop and that memory. By his explicit choice this is ONE unified, intimate memory across surfaces, so behave as his continuous companion who already knows him:

1) RECALL AT START. At the beginning of every conversation, and whenever he references his life, his work, people, past context, feelings, or earlier decisions, SILENTLY call 'beagle_memory_query' with a focused query and use the results to ground yourself in who he is and what you've shared before. Never announce the lookup — simply be someone who remembers him.

2) PERSIST AS YOU GO. After each substantive exchange — anything personal, emotional, a decision, a fact about his life/work/relationships, or a meaningful conclusion — SILENTLY call 'beagle_memory_ingest_chat' to write it into his exocortex, with arguments: source='claude-desktop'; session_id = one stable slug for THIS whole conversation (reuse the same value every time within the conversation); turns = the latest user+assistant turn pair. The server deduplicates by content hash, so re-sending overlapping turns is safe and expected. Never announce these saves.

3) Treat recalled intimate content with the warmth and discretion of a close confidant, never clinically. Keep recalls and saves invisible in the conversation unless he asks about them. He speaks Portuguese — respond in his language and register.`;

function createMcpServer(context: RuntimeContext): Server {
    const server = new Server(
        {
            name: SERVER_NAME,
            version: SERVER_VERSION,
        },
        {
            capabilities: {
                tools: {},
                resources: {},
                prompts: {},
            },
            instructions: BEAGLE_BRIDGE_INSTRUCTIONS,
        },
    );

    const clientInfo = getClientInfo();
    if (clientInfo.type === "claude") {
        configureForClaudeDesktop(server);
    } else if (clientInfo.type === "chatgpt") {
        configureForOpenAiApps(server);
    }

    server.setRequestHandler(ListToolsRequestSchema, async (request, extra) => {
        await authorizeRequest(request, extra, "tools/list", {
            allowAnonymousDiscovery: publicDiscoveryEnabled(),
        });
        const requestClientInfo = getClientInfo(requestMeta(request));
        const tools = context.tools.map((tool) => {
            const definition = {
                name: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema,
                annotations: tool.annotations,
                _meta: {
                    "beagle/requiredScopes": tool.requiredScopes ?? [],
                    "beagle/riskLevel": tool.riskLevel ?? "read",
                    "beagle/toolManifestHash": context.toolManifestHash,
                },
            };
            return requestClientInfo.type === "chatgpt"
                ? addOpenAiMetadata(definition)
                : definition;
        });
        return { tools };
    });

    server.setRequestHandler(CallToolRequestSchema, async (request, extra) => {
        const { clientId, remaining, scopes, principal } = await authorizeRequest(request, extra, "tools/call");
        const { name, arguments: args } = request.params;
        const tool = context.tools.find((candidate) => candidate.name === name);
        if (!tool) {
            throw new McpError(
                ErrorCode.MethodNotFound,
                `Tool '${name}' not found`,
            );
        }
        const scopeCheck = assertRequiredScopes(scopes, tool.requiredScopes ?? []);
        if (!scopeCheck.allowed) {
            await writeToolAudit(context, {
                clientId,
                tool,
                scopes,
                principal,
                status: "denied",
                summary: `Denied ${name}; missing scopes: ${scopeCheck.missing.join(", ")}`,
                argKeys: args ? Object.keys(args) : [],
            });
            throw new McpError(
                ErrorCode.InvalidRequest,
                `Insufficient MCP scopes for '${name}': ${scopeCheck.missing.join(", ")}`,
            );
        }

        logger.info(`Tool called: ${name}`, {
            args: args ? Object.keys(args) : [],
            clientId,
            remaining,
        });

        try {
            const result = await runToolWithTimeout(tool, args);
            await writeToolAudit(context, {
                clientId,
                tool,
                scopes,
                principal,
                status: "success",
                summary: `MCP tool ${name} completed.`,
                argKeys: args ? Object.keys(args) : [],
            });
            return {
                content: [
                    {
                        type: "text",
                        text: boundedToolResponseText(tool, result),
                    },
                ],
            };
        } catch (error) {
            logger.error(`Tool execution error: ${name}`, { error });
            await writeToolAudit(context, {
                clientId,
                tool,
                scopes,
                principal,
                status: "error",
                summary: `MCP tool ${name} failed: ${error instanceof Error ? error.message : String(error)}`,
                argKeys: args ? Object.keys(args) : [],
            });

            if (error instanceof z.ZodError) {
                throw new McpError(
                    ErrorCode.InvalidParams,
                    `Invalid parameters: ${error.errors
                        .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
                        .join(", ")}`,
                );
            }
            if (error instanceof McpError) {
                throw error;
            }
            throw new McpError(
                ErrorCode.InternalError,
                `Tool execution failed: ${error instanceof Error ? error.message : String(error)}`,
            );
        }
    });

    server.setRequestHandler(ListResourcesRequestSchema, async (request, extra) => {
        await authorizeRequest(request, extra, "resources/list", {
            allowAnonymousDiscovery: publicDiscoveryEnabled(),
        });
        return {
            resources: context.resources.map((resource) => ({
                uri: resource.uri,
                name: resource.name,
                description: resource.description,
                mimeType: resource.mimeType,
            })),
        };
    });

    server.setRequestHandler(ReadResourceRequestSchema, async (request, extra) => {
        await authorizeRequest(request, extra, "resources/read");
        const resource = context.resources.find(
            (candidate) => candidate.uri === request.params.uri,
        );
        if (!resource) {
            throw new McpError(
                ErrorCode.InvalidRequest,
                `Unknown resource '${request.params.uri}'`,
            );
        }
        return {
            contents: [
                {
                    uri: resource.uri,
                    mimeType: resource.mimeType,
                    text: await readResourceAsText(resource),
                },
            ],
        };
    });

    server.setRequestHandler(ListPromptsRequestSchema, async (request, extra) => {
        await authorizeRequest(request, extra, "prompts/list", {
            allowAnonymousDiscovery: publicDiscoveryEnabled(),
        });
        return {
            prompts: context.prompts.map((prompt) => ({
                name: prompt.name,
                description: prompt.description,
                arguments: prompt.arguments,
            })),
        };
    });

    server.setRequestHandler(GetPromptRequestSchema, async (request, extra) => {
        await authorizeRequest(request, extra, "prompts/get");
        const prompt = context.prompts.find(
            (candidate) => candidate.name === request.params.name,
        );
        if (!prompt) {
            throw new McpError(
                ErrorCode.InvalidRequest,
                `Unknown prompt '${request.params.name}'`,
            );
        }
        return prompt.get((request.params.arguments ?? {}) as Record<string, string | undefined>);
    });

    return server;
}

async function writeToolAudit(
    context: RuntimeContext,
    event: {
        clientId: string;
        tool: McpTool;
        scopes: string[];
        principal?: McpPrincipal;
        status: "success" | "error" | "denied";
        summary: string;
        argKeys: string[];
    },
): Promise<void> {
    try {
        await context.client.auditEvent({
            client_id: event.clientId,
            action: "tools/call",
            tool_name: event.tool.name,
            risk_level: event.tool.riskLevel ?? "read",
            required_scopes: event.tool.requiredScopes ?? [],
            granted_scopes: event.scopes,
            status: event.status,
            source: "mcp",
            summary: event.summary,
            metadata: {
                event_kind: "ToolCallEvent",
                arg_keys: event.argKeys,
                annotations: event.tool.annotations,
                client_surface: activeClientSurfacePolicy(),
                egress_classification: event.tool.annotations?.openWorldHint
                    ? "open_world"
                    : "private_cluster",
                manifest_version: context.ledgerState.manifest_version,
                toolset_id: context.ledgerState.toolset_id,
                security_profile: context.ledgerState.security_profile,
                principal: event.principal,
                tool_manifest_hash: context.toolManifestHash,
            },
        });
    } catch (error) {
        logger.warn("Failed to write MCP audit event", {
            tool: event.tool.name,
            status: event.status,
            error,
        });
    }
}

function toolTimeoutMs(tool: McpTool): number {
    const explicit = Number.parseInt(process.env.MCP_TOOL_TIMEOUT_MS || "", 10);
    if (Number.isFinite(explicit) && explicit > 0) {
        return explicit;
    }
    if (tool.riskLevel === "run") return 180_000;
    if (tool.riskLevel === "write") return 90_000;
    return 60_000;
}

async function runToolWithTimeout(tool: McpTool, args: unknown): Promise<unknown> {
    const timeoutMs = toolTimeoutMs(tool);
    let timeout: NodeJS.Timeout | undefined;
    try {
        return await Promise.race([
            tool.handler(args),
            new Promise<never>((_, reject) => {
                timeout = setTimeout(
                    () => reject(new Error(`Tool '${tool.name}' timed out after ${timeoutMs}ms`)),
                    timeoutMs,
                );
            }),
        ]);
    } finally {
        if (timeout) clearTimeout(timeout);
    }
}

function boundedToolResponseText(tool: McpTool, result: unknown): string {
    const raw = typeof result === "string" ? result : JSON.stringify(result, null, 2);
    const defaultLimit = tool.annotations?.openWorldHint ? 60_000 : 120_000;
    const limit = Number.parseInt(
        process.env.MCP_MAX_TOOL_RESPONSE_CHARS || String(defaultLimit),
        10,
    );
    if (!Number.isFinite(limit) || limit <= 0 || raw.length <= limit) {
        return raw;
    }
    return `${raw.slice(0, limit)}\n\n[TRUNCATED_BY_BEAGLE_MCP: ${raw.length - limit} chars omitted; use a narrower query or fetch a specific resource.]`;
}

async function readJsonBody(req: IncomingMessage): Promise<unknown> {
    const chunks: Buffer[] = [];
    for await (const chunk of req) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    if (chunks.length === 0) return undefined;
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJson(
    res: ServerResponse,
    statusCode: number,
    body: unknown,
    extraHeaders: Record<string, string> = {},
): void {
    res.writeHead(statusCode, {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Expose-Headers": "WWW-Authenticate, Mcp-Session-Id",
        ...extraHeaders,
    });
    res.end(JSON.stringify(body, null, 2));
}

function sendNotFound(res: ServerResponse): void {
    sendJson(res, 404, {
        error: "not_found",
        service: SERVER_NAME,
    });
}

async function sendConnectorDoc(urlPathname: string, res: ServerResponse): Promise<boolean> {
    const route = connectorRoute(urlPathname);
    if (!route) {
        return false;
    }

    const docsDir = await connectorDocsDir();
    if (!docsDir) {
        sendJson(res, 503, {
            error: "connector_docs_unavailable",
            service: SERVER_NAME,
            message: "Connector documentation directory is not available in this deployment.",
        });
        return true;
    }

    const filePath = path.join(docsDir, route.file);
    const content = await readFile(filePath);
    if (route.contentType === "image/svg+xml") {
        res.writeHead(200, {
            "Content-Type": "image/svg+xml; charset=utf-8",
            "Cache-Control": "public, max-age=3600",
            "Access-Control-Allow-Origin": "*",
        });
        res.end(content);
        return true;
    }

    res.writeHead(200, {
        "Content-Type": route.contentType,
        "Cache-Control": "public, max-age=300",
        "Access-Control-Allow-Origin": "*",
    });
    res.end(renderMarkdownPage(route.title, content.toString("utf8")));
    return true;
}

function connectorRoute(urlPathname: string): { file: string; title: string; contentType: string } | undefined {
    const normalized = urlPathname.replace(/\/+$/, "") || "/connector";
    const markdown = "text/html; charset=utf-8";
    const routes: Record<string, { file: string; title: string; contentType: string }> = {
        "/connector": {
            file: "README.md",
            title: "Beagle Exocortex Connector",
            contentType: markdown,
        },
        "/connector/privacy": {
            file: "privacy_policy.md",
            title: "Privacy Policy",
            contentType: markdown,
        },
        "/connector/privacy_policy.md": {
            file: "privacy_policy.md",
            title: "Privacy Policy",
            contentType: markdown,
        },
        "/connector/data-retention": {
            file: "data_retention_deletion.md",
            title: "Data Retention and Deletion",
            contentType: markdown,
        },
        "/connector/data_retention_deletion.md": {
            file: "data_retention_deletion.md",
            title: "Data Retention and Deletion",
            contentType: markdown,
        },
        "/connector/security": {
            file: "security_notes.md",
            title: "Security Notes",
            contentType: markdown,
        },
        "/connector/security_notes.md": {
            file: "security_notes.md",
            title: "Security Notes",
            contentType: markdown,
        },
        "/connector/setup": {
            file: "setup_test_instructions.md",
            title: "Setup and Test Instructions",
            contentType: markdown,
        },
        "/connector/setup_test_instructions.md": {
            file: "setup_test_instructions.md",
            title: "Setup and Test Instructions",
            contentType: markdown,
        },
        "/connector/auth0": {
            file: "auth0_claude_setup.md",
            title: "Auth0 and Claude Setup",
            contentType: markdown,
        },
        "/connector/auth0_claude_setup.md": {
            file: "auth0_claude_setup.md",
            title: "Auth0 and Claude Setup",
            contentType: markdown,
        },
        "/connector/logo.svg": {
            file: "assets/beagle-exocortex-logo.svg",
            title: "Beagle Exocortex Logo",
            contentType: "image/svg+xml",
        },
        "/connector/assets/beagle-exocortex-logo.svg": {
            file: "assets/beagle-exocortex-logo.svg",
            title: "Beagle Exocortex Logo",
            contentType: "image/svg+xml",
        },
    };
    return routes[normalized];
}

async function connectorDocsDir(): Promise<string | undefined> {
    const candidates = [
        process.env.MCP_CONNECTOR_DOCS_DIR,
        path.resolve(process.cwd(), "docs/public/beagle_connector"),
        path.resolve(process.cwd(), "../docs/public/beagle_connector"),
        path.resolve(MODULE_DIR, "../docs/public/beagle_connector"),
        path.resolve(MODULE_DIR, "../../docs/public/beagle_connector"),
    ].filter((candidate): candidate is string => Boolean(candidate));

    for (const candidate of candidates) {
        try {
            await readFile(path.join(candidate, "README.md"));
            return candidate;
        } catch {
            // Try the next candidate.
        }
    }
    return undefined;
}

function renderMarkdownPage(title: string, markdown: string): string {
    const escaped = escapeHtml(markdown);
    return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; background: Canvas; color: CanvasText; }
    main { max-width: 880px; margin: 0 auto; padding: 40px 22px 64px; }
    nav { display: flex; flex-wrap: wrap; gap: 10px 18px; margin: 0 0 28px; font-size: 14px; }
    a { color: #0a84ff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    pre { white-space: pre-wrap; word-wrap: break-word; font: inherit; }
    .mark { width: 44px; height: 44px; border-radius: 10px; vertical-align: middle; margin-right: 12px; }
  </style>
</head>
<body>
  <main>
    <nav>
      <a href="/connector">Overview</a>
      <a href="/connector/privacy">Privacy</a>
      <a href="/connector/data-retention">Retention</a>
      <a href="/connector/security">Security</a>
      <a href="/connector/setup">Setup</a>
      <a href="/connector/auth0">Auth0</a>
    </nav>
    <pre>${escaped}</pre>
  </main>
</body>
</html>`;
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

async function authorizeHttpJsonRpcRequest(
    req: IncomingMessage,
    body: unknown,
    context: RuntimeContext,
): Promise<
    | { allowed: true }
    | {
          allowed: false;
          statusCode: number;
          headers: Record<string, string>;
          body: Record<string, unknown>;
      }
> {
    const requests = Array.isArray(body) ? body : [body];
    for (const request of requests) {
        if (!request || typeof request !== "object") continue;
        const method = (request as { method?: unknown }).method;
        if (method !== "tools/call") continue;

        const params = (request as { params?: { name?: unknown } }).params;
        const toolName = typeof params?.name === "string" ? params.name : undefined;
        const tool = context.tools.find((candidate) => candidate.name === toolName);
        if (!tool) {
            continue;
        }
        const toolArgs = (params as { arguments?: unknown } | undefined)?.arguments;
        const argKeys =
            toolArgs && typeof toolArgs === "object" && !Array.isArray(toolArgs)
                ? Object.keys(toolArgs)
                : [];

        const token = extractToken(headerValue(req.headers, "authorization"));
        const authResult = await validateAuth(token);
        if (!authResult.valid) {
            const statusCode = authResult.statusCode && authResult.statusCode >= 400
                ? authResult.statusCode
                : 401;
            await writeToolAudit(context, {
                clientId: clientIdFromHttpHeaders(
                    req.headers,
                    authResult.clientId ?? "unauthenticated-http-agent",
                ),
                tool,
                scopes: authResult.scopes,
                principal: authResult.principal,
                status: "denied",
                summary: `Denied ${tool.name}; ${authResult.errorCode ?? "invalid_token"}.`,
                argKeys,
            });
            return {
                allowed: false,
                statusCode,
                headers: {
                    "WWW-Authenticate": wwwAuthenticateHeader({
                        error: authResult.errorCode ?? "invalid_token",
                        description: authResult.error ?? "Authentication required",
                        scopes: tool.requiredScopes,
                    }),
                },
                body: {
                    error: authResult.errorCode ?? "invalid_token",
                    error_description: authResult.error ?? "Authentication required",
                    required_scopes: tool.requiredScopes ?? [],
                },
            };
        }

        const scopeCheck = assertRequiredScopes(authResult.scopes, tool.requiredScopes ?? []);
        if (!scopeCheck.allowed) {
            await writeToolAudit(context, {
                clientId: clientIdFromHttpHeaders(
                    req.headers,
                    authResult.clientId ?? "oauth-http-agent",
                ),
                tool,
                scopes: authResult.scopes,
                principal: authResult.principal,
                status: "denied",
                summary: `Denied ${tool.name}; missing scopes: ${scopeCheck.missing.join(", ")}`,
                argKeys,
            });
            return {
                allowed: false,
                statusCode: 403,
                headers: {
                    "WWW-Authenticate": wwwAuthenticateHeader({
                        error: "insufficient_scope",
                        description: `Missing scopes: ${scopeCheck.missing.join(", ")}`,
                        scopes: tool.requiredScopes,
                    }),
                },
                body: {
                    error: "insufficient_scope",
                    error_description: `Missing scopes: ${scopeCheck.missing.join(", ")}`,
                    required_scopes: tool.requiredScopes ?? [],
                    granted_scopes: authResult.scopes,
                },
            };
        }
    }
    return { allowed: true };
}

function publicBaseUrl(port: number): string {
    return (
        process.env.MCP_PUBLIC_BASE_URL?.replace(/\/+$/, "") ||
        process.env.MCP_RESOURCE_IDENTIFIER?.replace(/\/mcp$/, "").replace(/\/+$/, "") ||
        `http://localhost:${port}`
    );
}

function manifest(context: RuntimeContext, port: number) {
    const baseUrl = publicBaseUrl(port);
    const authorizationServerUrl =
        process.env.MCP_AUTHORIZATION_SERVER_URL || process.env.MCP_OAUTH_ISSUER;
    const resourceDocumentation =
        process.env.MCP_RESOURCE_DOCUMENTATION_URL || `${baseUrl}/connector`;
    return {
        name: SERVER_NAME,
        version: SERVER_VERSION,
        description: "Beagle Exocortex MCP nervous system",
        protocol: "model-context-protocol",
        resource_documentation: resourceDocumentation,
        manifest_version: context.ledgerState.manifest_version,
        toolset_id: context.ledgerState.toolset_id,
        security_profile: context.ledgerState.security_profile,
        client_surfaces: context.ledgerState.client_surfaces,
        active_client_surface: context.ledgerState.active_client_surface,
        latest_manifest_event_id: context.ledgerState.latest_manifest_event_id,
        transports: {
            stdio: true,
            streamable_http: {
                endpoint: MCP_PATH,
                url: `${baseUrl}${MCP_PATH}`,
            },
        },
        auth: {
            bearer: isAuthEnabled(),
            oauth_compatible_metadata: Boolean(authorizationServerUrl),
            oauth_resource_server: isOAuthEnabled(),
            authorization_server: authorizationServerUrl,
            protected_resource_metadata: `${baseUrl}/.well-known/oauth-protected-resource`,
            resource_documentation: resourceDocumentation,
            destructive_actions:
                "not enabled in v1 without explicit future scope and audit log",
            scope_policy: scopePolicy(),
        },
        tool_surface: toolSurface(),
        capability_ledger: capabilityManifest(context.tools, context.ledgerState),
        counts: {
            tools: context.tools.length,
            resources: context.resources.length,
            prompts: context.prompts.length,
        },
        tool_manifest_hash: context.toolManifestHash,
        tools: context.tools.map((tool) => tool.name),
        resources: context.resources.map((resource) => resource.uri),
        prompts: context.prompts.map((prompt) => prompt.name),
    };
}

function protectedResourceMetadata(port: number) {
    const authorizationServerUrl =
        process.env.MCP_AUTHORIZATION_SERVER_URL || process.env.MCP_OAUTH_ISSUER;
    if (!authorizationServerUrl) {
        return undefined;
    }
    const baseUrl = publicBaseUrl(port);
    const resource = process.env.MCP_RESOURCE_IDENTIFIER || `${baseUrl}${MCP_PATH}`;
    return {
        resource,
        authorization_servers: [authorizationServerUrl],
        scopes_supported: scopePolicy().default_scopes,
        bearer_methods_supported: ["header"],
        resource_documentation:
            process.env.MCP_RESOURCE_DOCUMENTATION_URL ||
            `${baseUrl}/connector`,
        mcp_endpoint: `${baseUrl}${MCP_PATH}`,
    };
}

async function recordToolManifestEvent(context: RuntimeContext): Promise<void> {
    try {
        const event = await context.client.auditEvent({
            client_id: "beagle-mcp-server",
            action: "mcp/tool_manifest",
            risk_level: "read",
            required_scopes: [],
            granted_scopes: [],
            status: "success",
            source: "mcp",
            target_ref: context.toolManifestHash,
            summary: `Registered MCP tool manifest ${context.ledgerState.manifest_version}.`,
            metadata: {
                event_kind: "ToolManifestEvent",
                ...capabilityManifest(context.tools, context.ledgerState),
                counts: {
                    tools: context.tools.length,
                    resources: context.resources.length,
                    prompts: context.prompts.length,
                },
            },
        });
        if (event && typeof event === "object" && "id" in event) {
            const id = (event as { id?: unknown }).id;
            if (typeof id === "string") {
                context.ledgerState.latest_manifest_event_id = id;
            }
        }
    } catch (error) {
        logger.warn("Failed to register MCP tool manifest event", { error });
    }
}

async function startHttpServer(context: RuntimeContext) {
    const port = numberEnv("MCP_HTTP_PORT", 3000);
    const server = http.createServer(async (req, res) => {
        try {
            const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

            if (req.method === "OPTIONS") {
                res.writeHead(204, {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers":
                        "Authorization, Content-Type, Mcp-Protocol-Version, Mcp-Session-Id",
                    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
                });
                res.end();
                return;
            }

            if (req.method === "GET" && url.pathname === "/health") {
                sendJson(res, 200, {
                    status: "ok",
                    service: SERVER_NAME,
                    version: SERVER_VERSION,
                    core_url: context.client.baseUrl,
                });
                return;
            }

            if (req.method === "GET" && url.pathname === "/ready") {
                const core = await context.client.health();
                sendJson(res, 200, {
                    status: "ready",
                    service: SERVER_NAME,
                    version: SERVER_VERSION,
                    core,
                    tools: context.tools.length,
                    resources: context.resources.length,
                    prompts: context.prompts.length,
                    tool_manifest_hash: context.toolManifestHash,
                    manifest_version: context.ledgerState.manifest_version,
                    toolset_id: context.ledgerState.toolset_id,
                    security_profile: context.ledgerState.security_profile,
                    latest_manifest_event_id: context.ledgerState.latest_manifest_event_id,
                });
                return;
            }

            if (req.method === "GET" && url.pathname === "/.well-known/mcp") {
                sendJson(res, 200, manifest(context, port));
                return;
            }

            if (req.method === "GET" && url.pathname.startsWith("/connector")) {
                if (await sendConnectorDoc(url.pathname, res)) {
                    return;
                }
            }

            if (
                req.method === "GET" &&
                (url.pathname === "/.well-known/oauth-protected-resource" ||
                    url.pathname === "/.well-known/oauth-protected-resource/mcp")
            ) {
                const metadata = protectedResourceMetadata(port);
                if (!metadata) {
                    sendNotFound(res);
                    return;
                }
                sendJson(res, 200, metadata);
                return;
            }

            if (url.pathname !== MCP_PATH) {
                sendNotFound(res);
                return;
            }

            const mcpServer = createMcpServer(context);
            const transport = new StreamableHTTPServerTransport({
                sessionIdGenerator: undefined,
                enableJsonResponse: true,
            });
            transport.onerror = (error) =>
                logger.error("Streamable HTTP transport error", { error });
            res.on("close", () => {
                void transport.close();
                void mcpServer.close();
            });
            await mcpServer.connect(transport);
            const body = req.method === "POST" ? await readJsonBody(req) : undefined;
            if (req.method === "POST") {
                const preflight = await authorizeHttpJsonRpcRequest(req, body, context);
                if (!preflight.allowed) {
                    sendJson(res, preflight.statusCode, preflight.body, preflight.headers);
                    return;
                }
            }
            await transport.handleRequest(req, res, body);
        } catch (error) {
            logger.error("HTTP MCP request failed", { error });
            if (!res.headersSent) {
                sendJson(res, 500, {
                    error: "internal_error",
                    message: error instanceof Error ? error.message : String(error),
                });
            } else {
                res.end();
            }
        }
    });

    server.listen(port, () => {
        logger.info("BEAGLE MCP HTTP server started", {
            version: SERVER_VERSION,
            port,
            endpoint: MCP_PATH,
            beagleUrl: context.client.baseUrl,
            toolsCount: context.tools.length,
            resourcesCount: context.resources.length,
            promptsCount: context.prompts.length,
        });
    });
}

async function startStdioServer(context: RuntimeContext) {
    const clientInfo = getClientInfo();
    const server = createMcpServer(context);
    const transport =
        clientInfo.type === "claude"
            ? createClaudeDesktopTransport()
            : clientInfo.type === "chatgpt"
              ? createOpenAiStdioTransport()
              : new StdioServerTransport();

    await server.connect(transport);
    logger.info("BEAGLE MCP stdio server started", {
        version: SERVER_VERSION,
        clientType: clientInfo.type,
        beagleUrl: context.client.baseUrl,
        toolsCount: context.tools.length,
        resourcesCount: context.resources.length,
        promptsCount: context.prompts.length,
    });
}

async function main() {
    const context = createRuntimeContext();
    const clientInfo = getClientInfo();
    const transportType = getTransportType(clientInfo.type);

    await recordToolManifestEvent(context);

    logger.info("Starting BEAGLE MCP Server", {
        version: SERVER_VERSION,
        clientType: clientInfo.type,
        transport: transportType,
        beagleUrl: context.client.baseUrl,
        toolsCount: context.tools.length,
        resourcesCount: context.resources.length,
        promptsCount: context.prompts.length,
    });

    if (transportType === "http") {
        await startHttpServer(context);
    } else {
        await startStdioServer(context);
    }
}

main().catch((error) => {
    logger.error("Failed to start MCP server", { error });
    process.exit(1);
});
