/**
 * MCP Tools Registry
 *
 * Defines all MCP tools exposed by BEAGLE server.
 *
 * Canonical tools (production-ready):
 * - beagle_llm_complete: LLM proxy via TieredRouter
 * - beagle_pipeline_run: Start BEAGLE pipeline
 * - beagle_pipeline_status: Check pipeline status
 * - beagle_memory_ingest_chat: Ingest conversation into memory
 * - beagle_memory_query: Query memory (Memory RAG)
 * - beagle_feedback_tag: Tag run with feedback
 */

import { BeagleClient } from "../beagle-client.js";
import { llmTools } from "./llm.js";
import { pipelineTools } from "./pipeline.js";
import { scienceJobTools } from "./science-jobs.js";
import { memoryTools } from "./memory.js";
import { feedbackTools } from "./feedback.js";
import { experimentalTools } from "./experimental.js";

export interface McpTool {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>; // JSON Schema
    handler: (args: unknown) => Promise<unknown>;
}

export function defineTools(client: BeagleClient): McpTool[] {
    return [
        // Core tools (canonical set)
        ...llmTools(client),
        ...pipelineTools(client),
        ...memoryTools(client),
        ...feedbackTools(client),

        // Extended tools
        ...scienceJobTools(client),
        ...experimentalTools(client),
    ];
}
