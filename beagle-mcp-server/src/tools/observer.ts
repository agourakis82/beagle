/**
 * Observer Tools (HRV / context)
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { sanitizeOutput } from "../security.js";
import { McpTool } from "./index.js";

const UpdatePhysioSchema = z.object({
    hrv_ms: z.number().describe("Heart Rate Variability (ms)"),
    heart_rate_bpm: z.number().optional().describe("Optional heart rate (bpm)"),
    source: z
        .string()
        .optional()
        .describe("Optional source label (default: mcp)"),
});

const GetObserverContextSchema = z.object({
    run_id: z
        .string()
        .optional()
        .describe("Optional run_id (core currently returns current context)"),
});

export function observerTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_observer_update_physio",
            description:
                "Update BEAGLE Observer physiological state (HRV/HR). Calls BEAGLE Core: POST /api/observer/physio",
            inputSchema: {
                type: "object",
                properties: {
                    hrv_ms: {
                        type: "number",
                        description: "Heart Rate Variability in milliseconds",
                    },
                    heart_rate_bpm: {
                        type: "number",
                        description: "Optional heart rate in bpm",
                    },
                    source: {
                        type: "string",
                        description: "Optional source label (default: mcp)",
                    },
                },
                required: ["hrv_ms"],
            },
            handler: async (args: unknown) => {
                const { hrv_ms, heart_rate_bpm, source } =
                    UpdatePhysioSchema.parse(args);
                const result = await client.updatePhysio(
                    hrv_ms,
                    heart_rate_bpm,
                    source ?? "mcp",
                );
                return sanitizeOutput(result);
            },
        },
        {
            name: "beagle_observer_get_context",
            description:
                "Get current BEAGLE Observer context. Calls BEAGLE Core: GET /api/observer/context",
            inputSchema: {
                type: "object",
                properties: {
                    run_id: {
                        type: "string",
                        description:
                            "Optional run_id (core currently returns current context)",
                    },
                },
            },
            handler: async (args: unknown) => {
                const { run_id } = GetObserverContextSchema.parse(args);
                const result = await client.getObserverContext(run_id);
                return sanitizeOutput(result);
            },
        },
    ];
}

