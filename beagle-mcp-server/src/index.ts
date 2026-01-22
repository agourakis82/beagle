#!/usr/bin/env node
/**
 * BEAGLE MCP Server
 *
 * Memory & Control Plane (MCP) server exposing BEAGLE functionality
 * to ChatGPT (custom connector) and Claude (MCP client).
 *
 * Implements MCP protocol specification:
 * https://platform.openai.com/docs/mcp
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
    ErrorCode,
    McpError,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import dotenv from "dotenv";
import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { BeagleClient } from "./beagle-client.js";
import { defineTools } from "./tools/index.js";
import { logger } from "./logger.js";
import { validateAuth, extractToken, checkRateLimit } from "./auth.js";
import { getClientInfo, getTransportType } from "./compat.js";
import {
    configureForClaudeDesktop,
    createClaudeDesktopTransport,
} from "./transports/claude-desktop.js";
import {
    configureForOpenAiApps,
    createOpenAiStdioTransport,
    addOpenAiMetadata,
} from "./transports/openai-apps.js";

// Load environment variables
dotenv.config();

// Initialize BEAGLE HTTP client
const beagleClient = new BeagleClient(
    process.env.BEAGLE_CORE_URL || "http://localhost:8080",
    process.env.BEAGLE_CORE_API_TOKEN || undefined,
);

// Create MCP server
const server = new Server(
    {
        name: "beagle-mcp-server",
        version: "0.1.0",
    },
    {
        capabilities: {
            tools: {},
        },
    },
);

// Register tools
const tools = defineTools(beagleClient);

// Detect client type and configure accordingly
const clientInfo = getClientInfo();
if (clientInfo.type === "claude") {
    configureForClaudeDesktop(server);
} else if (clientInfo.type === "chatgpt") {
    configureForOpenAiApps(server);
}

server.setRequestHandler(ListToolsRequestSchema, async (request, extra) => {
    // Try to get client info from request (if available)
    const requestMeta = (request as any).meta as
        | Record<string, unknown>
        | undefined;
    const headerUserAgent = (extra as any)?.requestInfo?.headers?.["user-agent"];
    const headerMeta =
        typeof headerUserAgent === "string" && headerUserAgent.trim()
            ? { userAgent: headerUserAgent }
            : undefined;
    const requestClientInfo = getClientInfo(requestMeta ?? headerMeta);

    // Add OpenAI-specific metadata if using ChatGPT
    const toolsList = tools.map((t) => {
        const toolDef = {
            name: t.name,
            description: t.description,
            inputSchema: t.inputSchema as Record<string, unknown>,
        };

        if (requestClientInfo.type === "chatgpt") {
            return addOpenAiMetadata(toolDef);
        }

        return toolDef;
    });

    return { tools: toolsList };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request, extra) => {
    const { name, arguments: args } = request.params;

    // Auth validation (if enabled)
    const authHeaderFromMeta = (request as any).meta?.authorization as
        | string
        | undefined;
    const headerAuth = (extra as any)?.requestInfo?.headers?.authorization as
        | string
        | string[]
        | undefined;
    const authHeader =
        authHeaderFromMeta ??
        (Array.isArray(headerAuth) ? headerAuth[0] : headerAuth);
    const token = extractToken(authHeader);
    const authResult = validateAuth(token);
    if (!authResult.valid) {
        throw new McpError(
            ErrorCode.InvalidRequest,
            authResult.error || "Authentication required",
        );
    }

    // Rate limiting (by client identifier, if available)
    const headerClientId =
        (extra as any)?.requestInfo?.headers?.["x-forwarded-for"] ||
        (extra as any)?.requestInfo?.headers?.["x-real-ip"];
    const clientId =
        (request as any).meta?.clientId ||
        (typeof headerClientId === "string" ? headerClientId : "unknown");
    const rateLimitResult = checkRateLimit(clientId);
    if (!rateLimitResult.allowed) {
        throw new McpError(
            ErrorCode.InvalidRequest,
            "Rate limit exceeded. Please try again later.",
        );
    }

    logger.info(`Tool called: ${name}`, {
        args: args ? Object.keys(args) : [],
        clientId,
        remaining: rateLimitResult.remaining,
    });

    const tool = tools.find((t) => t.name === name);
    if (!tool) {
        throw new McpError(
            ErrorCode.MethodNotFound,
            `Tool '${name}' not found`,
        );
    }

    try {
        // Execute tool (validation happens inside tool handler via Zod)
        const result = await tool.handler(args);

        return {
            content: [
                {
                    type: "text",
                    text:
                        typeof result === "string"
                            ? result
                            : JSON.stringify(result, null, 2),
                },
            ],
        };
    } catch (error) {
        logger.error(`Tool execution error: ${name}`, { error });

        if (error instanceof z.ZodError) {
            throw new McpError(
                ErrorCode.InvalidParams,
                `Invalid parameters: ${error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join(", ")}`,
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

// Start server
async function main() {
    const clientInfo = getClientInfo();
    const transportType = getTransportType(clientInfo.type);

    logger.info("Starting BEAGLE MCP Server", {
        version: "0.3.0",
        clientType: clientInfo.type,
        transport: transportType,
        toolsCount: tools.length,
        beagleUrl: beagleClient.baseUrl,
    });

    if (transportType === "http") {
        const host = process.env.MCP_HTTP_HOST || "0.0.0.0";
        const port = Number(process.env.MCP_HTTP_PORT || "3000");
        const path = process.env.MCP_HTTP_PATH || "/mcp";
        const githubWebhookProxyEnabled =
            process.env.MCP_GITHUB_WEBHOOK_PROXY_ENABLED === "true";
        const githubWebhookPath =
            process.env.MCP_GITHUB_WEBHOOK_PATH || "/webhooks/github/push";

        const enableJsonResponse = process.env.MCP_HTTP_JSON_RESPONSE === "true";

        const allowedHosts =
            process.env.MCP_HTTP_ALLOWED_HOSTS?.split(",")
                .map((s) => s.trim())
                .filter(Boolean) ?? [];
        const allowedOrigins =
            process.env.MCP_HTTP_ALLOWED_ORIGINS?.split(",")
                .map((s) => s.trim())
                .filter(Boolean) ?? [];
        const enableDnsRebindingProtection =
            process.env.MCP_HTTP_DNS_REBINDING_PROTECTION === "true";

        const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: () => randomUUID(),
            enableJsonResponse,
            allowedHosts: allowedHosts.length ? allowedHosts : undefined,
            allowedOrigins: allowedOrigins.length ? allowedOrigins : undefined,
            enableDnsRebindingProtection,
        });

        await server.connect(transport);

        async function readRequestBody(
            req: IncomingMessage,
            maxBytes: number,
        ): Promise<Buffer> {
            return new Promise((resolve, reject) => {
                const chunks: Buffer[] = [];
                let total = 0;
                req.on("data", (chunk: Buffer) => {
                    total += chunk.length;
                    if (total > maxBytes) {
                        reject(new Error(`payload too large (${total} bytes > ${maxBytes})`));
                        req.destroy();
                        return;
                    }
                    chunks.push(chunk);
                });
                req.on("end", () => resolve(Buffer.concat(chunks)));
                req.on("error", reject);
            });
        }

        async function handleGitHubWebhookProxy(
            req: IncomingMessage,
            res: ServerResponse,
        ): Promise<void> {
            if (!githubWebhookProxyEnabled) {
                res.writeHead(404, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ error: "not_found" }));
                return;
            }
            if (req.method !== "POST") {
                res.writeHead(405, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ error: "method_not_allowed" }));
                return;
            }

            const body = await readRequestBody(req, 5_000_000);

            const coreWebhookUrl = new URL(
                "/webhooks/github/push",
                beagleClient.baseUrl,
            ).toString();

            const headers: Record<string, string> = {};
            const contentType = req.headers["content-type"];
            if (typeof contentType === "string" && contentType.trim()) {
                headers["content-type"] = contentType;
            } else {
                headers["content-type"] = "application/json";
            }

            const sig = req.headers["x-hub-signature-256"];
            if (typeof sig === "string" && sig.trim()) {
                headers["x-hub-signature-256"] = sig;
            }

            const ghEvent = req.headers["x-github-event"];
            if (typeof ghEvent === "string" && ghEvent.trim()) {
                headers["x-github-event"] = ghEvent;
            }

            const resp = await fetch(coreWebhookUrl, {
                method: "POST",
                headers,
                body,
            });

            const respText = await resp.text();
            const respContentType =
                resp.headers.get("content-type") || "application/json";
            res.writeHead(resp.status, { "Content-Type": respContentType });
            res.end(respText);
        }

        const httpServer = createServer(async (req, res) => {
            try {
                const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
                if (url.pathname === "/health") {
                    res.writeHead(200, { "Content-Type": "application/json" });
                    res.end(JSON.stringify({ status: "ok" }));
                    return;
                }

                if (url.pathname === githubWebhookPath) {
                    await handleGitHubWebhookProxy(req, res);
                    return;
                }

                if (url.pathname !== path) {
                    res.writeHead(404, { "Content-Type": "application/json" });
                    res.end(JSON.stringify({ error: "not_found" }));
                    return;
                }

                await transport.handleRequest(req as any, res);
            } catch (error) {
                logger.error("HTTP transport error", { error });
                if (!res.headersSent) {
                    res.writeHead(500, { "Content-Type": "application/json" });
                }
                res.end(
                    JSON.stringify({
                        error: "internal_error",
                        message: error instanceof Error ? error.message : String(error),
                    }),
                );
            }
        });

        httpServer.listen(port, host, () => {
            logger.info("BEAGLE MCP Server listening (HTTP)", {
                host,
                port,
                path,
                enableJsonResponse,
                githubWebhookProxyEnabled,
                githubWebhookPath,
            });
        });
    } else {
        // Create appropriate stdio transport
        let transport: StdioServerTransport;
        if (clientInfo.type === "claude") {
            transport = createClaudeDesktopTransport();
        } else if (clientInfo.type === "chatgpt") {
            transport = createOpenAiStdioTransport();
        } else {
            // Default: stdio transport
            transport = new StdioServerTransport();
        }

        await server.connect(transport);

        logger.info("BEAGLE MCP Server started successfully", {
            version: "0.3.0",
            clientType: clientInfo.type,
            transport: transportType,
            toolsCount: tools.length,
            beagleUrl: beagleClient.baseUrl,
        });
    }
}

main().catch((error) => {
    logger.error("Failed to start MCP server", { error });
    process.exit(1);
});
