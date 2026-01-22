/**
 * Exocortex Tools (Unified Cognitive Orchestration)
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { sanitizeOutput } from "../security.js";
import { McpTool } from "./index.js";

const ExocortexProcessSchema = z.object({
    user_id: z.string().describe("Stable user ID for identity persistence"),
    query: z.string().describe("User query to process through the Exocortex"),
    intent: z.string().optional().describe("Optional explicit intent"),
    context: z
        .string()
        .optional()
        .describe("Optional additional context to attach to the query"),
    urgency: z
        .number()
        .min(0)
        .max(1)
        .optional()
        .describe("Urgency level (0.0-1.0)"),
    modality: z
        .enum(["text", "voice", "multimodal"])
        .optional()
        .default("text")
        .describe("Input modality"),
    identity_persistence: z
        .enum(["memory", "file", "postgres"])
        .optional()
        .describe("Identity persistence backend"),
    identity_path: z
        .string()
        .optional()
        .describe("Base directory for file-based identity persistence"),
});

export function exocortexTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_exocortex_process",
            description: `Process a query via the BEAGLE Exocortex (identity + context + agents + memory + consciousness).

Calls BEAGLE Core: POST /api/exocortex/process

Notes:
- Pass a stable user_id to enable identity persistence (file-backed if configured).
- Returns structured output: response, confidence, agents_used, consciousness_state, suggestions, and (when RAG is enabled) retrieved_sources + citations.`,
            inputSchema: {
                type: "object",
                properties: {
                    user_id: {
                        type: "string",
                        description: "Stable user ID for identity persistence",
                    },
                    query: {
                        type: "string",
                        description: "User query to process through the Exocortex",
                    },
                    intent: {
                        type: "string",
                        description: "Optional explicit intent",
                    },
                    context: {
                        type: "string",
                        description: "Optional additional context",
                    },
                    urgency: {
                        type: "number",
                        description: "Urgency level (0.0-1.0)",
                        minimum: 0,
                        maximum: 1,
                    },
                    modality: {
                        type: "string",
                        description: "Input modality",
                        enum: ["text", "voice", "multimodal"],
                        default: "text",
                    },
                    identity_persistence: {
                        type: "string",
                        description: "Identity persistence backend",
                        enum: ["memory", "file", "postgres"],
                    },
                    identity_path: {
                        type: "string",
                        description: "Base directory for file-based identity persistence",
                    },
                },
                required: ["user_id", "query"],
            },
            handler: async (args: unknown) => {
                const {
                    user_id,
                    query,
                    intent,
                    context,
                    urgency,
                    modality,
                    identity_persistence,
                    identity_path,
                } =
                    ExocortexProcessSchema.parse(args);

                const config: Record<string, unknown> | undefined =
                    identity_persistence || identity_path
                        ? {
                              identity: {
                                  persistence:
                                      identity_persistence ||
                                      (identity_path ? "file" : "memory"),
                                  persistence_path: identity_path,
                              },
                          }
                        : undefined;

                const result = await client.exocortexProcess(user_id, query, {
                    intent,
                    context,
                    urgency,
                    modality,
                    config,
                });

                return sanitizeOutput(result);
            },
        },
    ];
}
