/**
 * Feedback & Experiment Tools
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { McpTool } from "./index.js";
import { sanitizeOutput } from "../security.js";

const TagRunSchema = z.object({
    run_id: z.string().describe("Run ID to tag"),
    accepted: z
        .boolean()
        .describe("Whether the run output was accepted (good quality)"),
    rating0_10: z
        .number()
        .int()
        .min(0)
        .max(10)
        .optional()
        .describe("Rating from 0-10"),
    notes: z.string().optional().describe("Additional notes"),
});

const TagExperimentRunSchema = z.object({
    experiment_id: z
        .string()
        .describe(
            'Experiment ID (e.g., "triad_vs_ensemble", "hrv_aware_vs_blind")',
        ),
    run_id: z.string().describe("Run ID to tag"),
    condition: z
        .string()
        .describe(
            'Experimental condition (e.g., "triad", "ensemble", "hrv_aware")',
        ),
    notes: z.string().optional().describe("Additional notes"),
});

export function feedbackTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_feedback_tag",
            description: `Tag a pipeline run with human feedback (accepted/rejected, rating, notes).

Use this to:
- Mark runs as accepted (good quality) or rejected
- Provide ratings (0-10) for continuous learning
- Add notes for future reference

This feedback is used for:
- LoRA dataset generation (export_lora_dataset)
- Continuous learning improvements
- Quality analysis`,
            inputSchema: {
                type: "object",
                properties: {
                    run_id: {
                        type: "string",
                        description: "Run ID to tag",
                    },
                    accepted: {
                        type: "boolean",
                        description:
                            "Whether the run output was accepted (good quality)",
                    },
                    rating0_10: {
                        type: "number",
                        description: "Rating from 0-10 (optional)",
                        minimum: 0,
                        maximum: 10,
                    },
                    notes: {
                        type: "string",
                        description: "Additional notes (optional)",
                    },
                },
                required: ["run_id", "accepted"],
            },
            handler: async (args: unknown) => {
                const { run_id, accepted, rating0_10, notes } =
                    TagRunSchema.parse(args);

                const result = await client.tagRun(
                    run_id,
                    accepted,
                    rating0_10,
                    notes,
                );

                return sanitizeOutput({
                    status: result.status,
                    run_id: result.run_id,
                    message: `Run ${run_id} tagged: ${accepted ? "accepted" : "rejected"}${rating0_10 ? ` (rating: ${rating0_10}/10)` : ""}`,
                });
            },
        },
        {
            name: "beagle_tag_experiment_run",
            description: `Tag a run with an experimental condition (for A/B testing, etc.).

Use this for:
- A/B testing (e.g., Triad vs ensemble)
- HRV-aware vs HRV-blind experiments
- Other controlled experiments

The tagged runs can be analyzed later to compare conditions.`,
            inputSchema: {
                type: "object",
                properties: {
                    experiment_id: {
                        type: "string",
                        description:
                            'Experiment ID (e.g., "triad_vs_ensemble", "hrv_aware_vs_blind")',
                    },
                    run_id: {
                        type: "string",
                        description: "Run ID to tag",
                    },
                    condition: {
                        type: "string",
                        description:
                            'Experimental condition (e.g., "triad", "ensemble", "hrv_aware")',
                    },
                    notes: {
                        type: "string",
                        description: "Additional notes (optional)",
                    },
                },
                required: ["experiment_id", "run_id", "condition"],
            },
            handler: async (args: unknown) => {
                const { experiment_id, run_id, condition, notes } =
                    TagExperimentRunSchema.parse(args);

                const result = await client.tagExperimentRun(
                    experiment_id,
                    run_id,
                    condition,
                    notes,
                );

                return sanitizeOutput({
                    status: result.status,
                    message: `Run ${run_id} tagged for experiment ${experiment_id} (condition: ${condition})`,
                });
            },
        },
    ];
}
