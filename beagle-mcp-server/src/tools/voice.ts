/**
 * Voice Tools (TTS)
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { sanitizeOutput } from "../security.js";
import { McpTool } from "./index.js";

const VoiceTtsSchema = z.object({
    text: z.string().describe("Text to synthesize as audio"),
    language: z.string().optional().describe("Optional BCP-47 language tag"),
    voice: z.string().optional().describe("Optional voice identifier"),
    rate_wpm: z.number().int().optional().describe("Optional speech rate (WPM)"),
    use_hrv_rate: z
        .boolean()
        .optional()
        .describe("Whether to adapt rate based on HRV (default: true)"),
    max_bytes: z
        .number()
        .int()
        .min(1)
        .max(5_000_000)
        .optional()
        .describe("Maximum bytes allowed for base64 output (default: 512000)"),
});

export function voiceTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_voice_tts",
            description:
                "Generate a WAV via BEAGLE Core TTS. Returns base64-encoded audio. Calls BEAGLE Core: POST /api/voice/tts",
            inputSchema: {
                type: "object",
                properties: {
                    text: { type: "string", description: "Text to synthesize" },
                    language: {
                        type: "string",
                        description: "Optional BCP-47 language tag (e.g., en-US)",
                    },
                    voice: {
                        type: "string",
                        description: "Optional voice identifier",
                    },
                    rate_wpm: {
                        type: "number",
                        description: "Optional speech rate (words per minute)",
                    },
                    use_hrv_rate: {
                        type: "boolean",
                        description:
                            "Whether to adapt speech rate based on HRV (default: true)",
                    },
                    max_bytes: {
                        type: "number",
                        description:
                            "Maximum bytes allowed for base64 output (default: 512000)",
                    },
                },
                required: ["text"],
            },
            handler: async (args: unknown) => {
                const { text, language, voice, rate_wpm, use_hrv_rate, max_bytes } =
                    VoiceTtsSchema.parse(args);

                const result = await client.voiceTts(text, {
                    language,
                    voice,
                    rate_wpm,
                    use_hrv_rate,
                    max_bytes,
                });
                return sanitizeOutput(result);
            },
        },
    ];
}

