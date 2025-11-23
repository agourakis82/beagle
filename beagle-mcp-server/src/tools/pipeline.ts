/**
 * Pipeline & Triad Tools
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { McpTool } from "./index.js";
import { sanitizeOutput } from "../security.js";

const RunPipelineSchema = z.object({
    question: z
        .string()
        .describe("Research question or topic for the pipeline"),
    with_triad: z
        .boolean()
        .optional()
        .describe("Whether to run Triad adversarial review after pipeline"),
    hrv_aware: z
        .boolean()
        .optional()
        .describe("Whether to use HRV-aware model selection"),
    experiment_id: z
        .string()
        .optional()
        .describe("Optional experiment ID to tag this run"),
});

const GetRunStatusSchema = z.object({
    run_id: z.string().describe("Run ID from beagle_pipeline_run"),
});

const ListRecentRunsSchema = z.object({
    limit: z
        .number()
        .int()
        .min(1)
        .max(50)
        .optional()
        .default(10)
        .describe("Maximum number of runs to return"),
});

export function pipelineTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_pipeline_run",
            description: `Run BEAGLE pipeline to generate a scientific draft from a research question.

This tool starts an asynchronous pipeline that:
1. Uses Darwin (GraphRAG) to gather semantic context
2. Captures physiological state (HRV) via Observer
3. Uses HERMES to synthesize a draft paper
4. Optionally runs Triad adversarial review (ATHENA-HERMES-ARGOS + final judge)

Returns a run_id that can be used to check status and retrieve artifacts.

IMPORTANT: This is an asynchronous operation. Use beagle_pipeline_status to check progress and retrieve results.`,
            inputSchema: {
                type: "object",
                properties: {
                    question: {
                        type: "string",
                        description: "Research question or topic",
                    },
                    with_triad: {
                        type: "boolean",
                        description: "Whether to run Triad adversarial review",
                    },
                    hrv_aware: {
                        type: "boolean",
                        description: "Whether to use HRV-aware model selection",
                    },
                    experiment_id: {
                        type: "string",
                        description: "Optional experiment ID to tag this run",
                    },
                },
                required: ["question"],
            },
            handler: async (args: unknown) => {
                const { question, with_triad, hrv_aware, experiment_id } =
                    RunPipelineSchema.parse(args);

                const result = await client.startPipeline(
                    question,
                    with_triad,
                    hrv_aware,
                    experiment_id,
                );

                return sanitizeOutput({
                    run_id: result.run_id,
                    status: result.status,
                    message: `Pipeline started successfully. Run ID: ${result.run_id}. Use beagle_pipeline_status to check progress.`,
                });
            },
        },
        {
            name: "beagle_pipeline_status",
            description: `Get status and artifacts for a pipeline run.

Returns:
- Status: "pending" | "running" | "completed" | "failed"
- Question
- Summary (if completed)
- Artifacts: paths to draft.md, draft_reviewed.md, PDFs
- LLM usage statistics

Use this to check if a pipeline run has completed and retrieve the generated artifacts.`,
            inputSchema: {
                type: "object",
                properties: {
                    run_id: {
                        type: "string",
                        description: "Run ID from beagle_pipeline_run",
                    },
                },
                required: ["run_id"],
            },
            handler: async (args: unknown) => {
                const { run_id } = GetRunStatusSchema.parse(args);

                // Get status first
                const status = await client.getRunStatus(run_id);

                // If completed, get artifacts
                let artifacts = null;
                if (status.status === "completed") {
                    try {
                        artifacts = await client.getRunArtifacts(run_id);
                    } catch (error) {
                        // Artifacts may not be available yet
                    }
                }

                return sanitizeOutput({
                    run_id: status.run_id,
                    status: status.status,
                    question: status.question || "N/A",
                    summary: artifacts
                        ? `Draft generated${artifacts.triad_final_md ? " with Triad review" : ""}`
                        : undefined,
                    artifacts: artifacts
                        ? {
                              draft_md: artifacts.draft_md,
                              draft_pdf: artifacts.draft_pdf,
                              triad_final_md: artifacts.triad_final_md,
                              triad_report_json: artifacts.triad_report_json,
                          }
                        : undefined,
                    llm_stats: artifacts?.llm_stats,
                });
            },
        },
        {
            name: "beagle_list_recent_runs",
            description: `List recent pipeline runs with their status and metadata.

Useful for:
- Finding run_ids to retrieve artifacts
- Reviewing recent work
- Tracking pipeline activity`,
            inputSchema: {
                type: "object",
                properties: {
                    limit: {
                        type: "number",
                        description: "Maximum number of runs to return (1-50)",
                        minimum: 1,
                        maximum: 50,
                        default: 10,
                    },
                },
            },
            handler: async (args: unknown) => {
                const { limit } = ListRecentRunsSchema.parse(args);

                const result = await client.listRecentRuns(limit);

                return sanitizeOutput({
                    runs: result.runs.map((run) => ({
                        run_id: run.run_id,
                        question: run.question,
                        status: run.status,
                        created_at: run.created_at,
                    })),
                });
            },
        },
    ];
}
