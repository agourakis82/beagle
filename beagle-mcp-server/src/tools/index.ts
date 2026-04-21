/**
 * MCP Tools Registry
 *
 * Defines all MCP tools exposed by BEAGLE server.
 *
 * Canonical tools (production-ready):
 * - beagle_llm_complete: LLM proxy via TieredRouter
 * - beagle_llm_complete_stream: Streaming LLM completion (P2 feature)
 * - beagle_pipeline_run: Start BEAGLE pipeline
 * - beagle_pipeline_status: Check pipeline status
 * - beagle_memory_ingest_chat: Ingest conversation into memory
 * - beagle_memory_query: Query memory (Memory RAG)
 * - beagle_feedback_tag: Tag run with feedback
 * - tavily_search: Web search via Tavily API
 * - tavily_research: Comprehensive research query
 * - beagle_webhook_*: Webhook registration and management
 */

import { BeagleClient } from "../beagle-client.js";
import { llmTools } from "./llm.js";
import { llmStreamTools } from "./llm-stream.js";
import { pipelineTools } from "./pipeline.js";
import { scienceJobTools } from "./science-jobs.js";
import { memoryTools } from "./memory.js";
import { feedbackTools } from "./feedback.js";
import { experimentalTools } from "./experimental.js";
import { tavilyTools } from "./tavily.js";
import { webhookTools } from "./webhooks.js";

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
        ...llmStreamTools(client), // P2: Streaming support
        ...pipelineTools(client),
        ...memoryTools(client),
        ...feedbackTools(client),

        // Webhook management
        ...webhookTools(client),

        // Extended tools
        ...scienceJobTools(client),
        ...experimentalTools(client),

        // Third-party integrations
        ...tavilyTools(client),
    ];
}
