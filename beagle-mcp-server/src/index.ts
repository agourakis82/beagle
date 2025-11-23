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
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
    ErrorCode,
    McpError,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import dotenv from "dotenv";
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

server.setRequestHandler(ListToolsRequestSchema, async (request) => {
    // Try to get client info from request (if available)
    const requestMeta = (request as any).meta as
        | Record<string, unknown>
        | undefined;
    const requestClientInfo = getClientInfo(requestMeta);

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
server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    // Auth validation (if enabled)
    const authHeader = (request as any).meta?.authorization;
    const token = extractToken(authHeader);
    const authResult = validateAuth(token);
    if (!authResult.valid) {
        throw new McpError(
            ErrorCode.InvalidRequest,
            authResult.error || "Authentication required",
        );
    }

    // Rate limiting (by client identifier, if available)
    const clientId = (request as any).meta?.clientId || "unknown";
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

    // Create appropriate transport
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

main().catch((error) => {
    logger.error("Failed to start MCP server", { error });
    process.exit(1);
});
