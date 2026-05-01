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
import { exocortexTools } from "./exocortex.js";
import { standardTools } from "./standard.js";

export interface McpTool {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>; // JSON Schema
    annotations?: McpToolAnnotations;
    requiredScopes?: string[];
    riskLevel?: McpToolRiskLevel;
    handler: (args: unknown) => Promise<unknown>;
}

export interface McpToolAnnotations {
    title: string;
    readOnlyHint: boolean;
    destructiveHint: boolean;
    idempotentHint: boolean;
    openWorldHint: boolean;
}

export type McpToolRiskLevel = "read" | "write" | "run" | "experimental";
export type McpToolSurface = "review_safe" | "trusted_full";

type ToolPolicy = {
    annotations: McpToolAnnotations;
    requiredScopes: string[];
    riskLevel: McpToolRiskLevel;
};

const READ_EXOCORTEX = ["exocortex:read"];
const WRITE_MEMORY = ["exocortex:read", "memory:write"];
const WRITE_CHRONOSELF = ["exocortex:read", "chronoself:write"];
const RUN_RESEARCH = ["exocortex:read", "research:run"];
const START_AGENT = ["exocortex:read", "agent:start"];

function annotations(
    title: string,
    readOnlyHint: boolean,
    openWorldHint: boolean,
    idempotentHint: boolean,
): McpToolAnnotations {
    return {
        title,
        readOnlyHint,
        destructiveHint: false,
        idempotentHint,
        openWorldHint,
    };
}

const TOOL_POLICIES: Record<string, ToolPolicy> = {
    search: {
        annotations: annotations("Search Beagle Exocortex", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    fetch: {
        annotations: annotations("Fetch Beagle Exocortex Result", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_llm_complete: {
        annotations: annotations("Complete with Beagle LLM Router", false, true, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_pipeline_run: {
        annotations: annotations("Start Beagle Pipeline", false, true, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_pipeline_status: {
        annotations: annotations("Read Pipeline Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_list_recent_runs: {
        annotations: annotations("List Recent Runs", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_query: {
        annotations: annotations("Query Beagle Memory", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_ingest_chat: {
        annotations: annotations("Ingest Chat into Memory", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_feedback_tag: {
        annotations: annotations("Tag Run Feedback", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_tag_experiment_run: {
        annotations: annotations("Tag Experiment Run", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_exocortex_home: {
        annotations: annotations("Read Exocortex Home", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_chronoself_current: {
        annotations: annotations("Read Current Chronoself", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_chronoself_commits: {
        annotations: annotations("Read Chronoself Commits", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_chronoself_create_commit: {
        annotations: annotations("Create Chronoself Commit", false, false, false),
        requiredScopes: WRITE_CHRONOSELF,
        riskLevel: "write",
    },
    beagle_omnimemory_import: {
        annotations: annotations("Import OmniMemory Conversation", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_assisted_import_batch: {
        annotations: annotations("Import Assisted Memory Batch", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_agent_registry: {
        annotations: annotations("Read Agent Role Registry", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_agent_route: {
        annotations: annotations("Route Agent Role", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_write_probe: {
        annotations: annotations("Probe Memory Write Health", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_failed_write_inbox: {
        annotations: annotations("Read Failed Write Inbox", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_failed_write_rescue: {
        annotations: annotations("Rescue Failed Memory Write", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_capture_session_start: {
        annotations: annotations("Start Explicit Capture Session", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_capture_session_status: {
        annotations: annotations("Read Capture Session Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_visual_evidence_analyze: {
        annotations: annotations("Analyze Visual Evidence", false, true, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_capture_review_promote: {
        annotations: annotations("Promote Capture Review Candidates", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_memory_project_graph: {
        annotations: annotations("Project GraphRAG++ Memory", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_memory_graph_status: {
        annotations: annotations("Read GraphRAG++ Runtime Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_bakeoff_status: {
        annotations: annotations("Read GraphRAG++ Bake-Off Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_graphrag_query: {
        annotations: annotations("Query GraphRAG++ Memory", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_engine_status: {
        annotations: annotations("Read Federated Memory Engine Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_mesh_query: {
        annotations: annotations("Query Federated Memory Mesh", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_semantic_index_status: {
        annotations: annotations("Read Semantic Index Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_semantic_index_rebuild: {
        annotations: annotations("Rebuild Semantic Index", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_retrieval_trace: {
        annotations: annotations("Read Retrieval Trace", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_retrieval_agent_query: {
        annotations: annotations("Query Retrieval Agent", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_retrieval_agent_status: {
        annotations: annotations("Read Retrieval Agent Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memoryarena_benchmark_run: {
        annotations: annotations("Run Private MemoryArena Benchmark", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_memoryarena_benchmark_status: {
        annotations: annotations("Read Private MemoryArena Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_context_compile: {
        annotations: annotations("Compile Adaptive Context Pack", true, false, false),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_context_pack_get: {
        annotations: annotations("Fetch Context Pack", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_effectiveness_record: {
        annotations: annotations("Record Memory Effectiveness", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_memory_policy_status: {
        annotations: annotations("Read Memory Policy Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_dreamcycle_run: {
        annotations: annotations("Run DreamCycle Consolidation", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_dreamcycle_status: {
        annotations: annotations("Read DreamCycle Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_program_check: {
        annotations: annotations("Check Sounio Work IR Program", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_claim_check: {
        annotations: annotations("Check Sounio Claim", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_moment_type: {
        annotations: annotations("Type Sounio Ambient Moment", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_sounio_workday_status: {
        annotations: annotations("Read Sounio Workday Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_moment_review: {
        annotations: annotations("Review Sounio Ambient Moment", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_sounio_paperrun_start: {
        annotations: annotations("Start Sounio PaperRun", false, true, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_sounio_paperrun_status: {
        annotations: annotations("Read Sounio PaperRun Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_paperrun_approve_step: {
        annotations: annotations("Approve Sounio PaperRun Step", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_sounio_paperrun_add_claim: {
        annotations: annotations("Add Sounio PaperRun Claim", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_sounio_claim_review: {
        annotations: annotations("Review Sounio Claim", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_sounio_paperrun_theatre: {
        annotations: annotations("Read PaperRun Theatre", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_public_digest: {
        annotations: annotations("Read Sounio Public Digest", true, false, false),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_sounio_trace_query: {
        annotations: annotations("Query Sounio PaperRun Trace", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_bakeoff_run: {
        annotations: annotations("Run Memory Runtime Bake-Off", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_memory_candidates_list: {
        annotations: annotations("List Candidate Memory Items", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_candidate_quorum: {
        annotations: annotations("Record Candidate Memory Quorum", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_memory_governance_status: {
        annotations: annotations("Read Memory Governor Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_governance_run: {
        annotations: annotations("Run Memory Governor", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_memory_contradictions_recent: {
        annotations: annotations("Read Memory Contradictions", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_engine_eval_run: {
        annotations: annotations("Run Memory Engine Eval", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_memory_benchmark_run: {
        annotations: annotations("Run Memory Bench", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_memory_benchmark_status: {
        annotations: annotations("Read Memory Bench Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_truthset_draft: {
        annotations: annotations("Draft Private Memory Truth Set", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_memory_truthset_review: {
        annotations: annotations("Review Private Memory Truth Set", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_agent_observer_status: {
        annotations: annotations("Read Agent Observer Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_memory_engine_governance_evaluate: {
        annotations: annotations("Evaluate Memory Governance", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_work_memory_capture: {
        annotations: annotations("Capture Agent Work Memory", false, false, false),
        requiredScopes: WRITE_MEMORY,
        riskLevel: "write",
    },
    beagle_temporal_analyze: {
        annotations: annotations("Run TemporalAI Analysis", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_go_deeper: {
        annotations: annotations("Run Go Deeper", false, true, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_round_table: {
        annotations: annotations("Convoke Round Table", false, true, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_agent_sessions: {
        annotations: annotations("List Agent Sessions", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_agent_session_start: {
        annotations: annotations("Start Agent Session", false, true, false),
        requiredScopes: START_AGENT,
        riskLevel: "run",
    },
    beagle_start_science_job: {
        annotations: annotations("Start Science Job", false, true, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "run",
    },
    beagle_get_science_job_status: {
        annotations: annotations("Read Science Job Status", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_get_science_job_artifacts: {
        annotations: annotations("Read Science Job Artifacts", true, false, true),
        requiredScopes: READ_EXOCORTEX,
        riskLevel: "read",
    },
    beagle_serendipity_toggle: {
        annotations: annotations("Toggle Serendipity Engine", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "experimental",
    },
    beagle_serendipity_perturb_prompt: {
        annotations: annotations("Perturb Prompt", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "experimental",
    },
    beagle_void_break_loop: {
        annotations: annotations("Apply Void Break Loop", false, false, false),
        requiredScopes: RUN_RESEARCH,
        riskLevel: "experimental",
    },
};

const REVIEW_SAFE_TOOL_NAMES = new Set([
    "search",
    "fetch",
    "beagle_exocortex_home",
    "beagle_chronoself_current",
    "beagle_chronoself_commits",
    "beagle_memory_query",
    "beagle_agent_registry",
    "beagle_agent_route",
    "beagle_write_probe",
    "beagle_failed_write_inbox",
    "beagle_memory_graph_status",
    "beagle_memory_bakeoff_status",
    "beagle_graphrag_query",
    "beagle_memory_engine_status",
    "beagle_memory_mesh_query",
    "beagle_semantic_index_status",
    "beagle_retrieval_trace",
    "beagle_memory_candidates_list",
    "beagle_memory_governance_status",
    "beagle_memory_contradictions_recent",
    "beagle_memory_benchmark_status",
    "beagle_agent_observer_status",
    "beagle_sounio_workday_status",
    "beagle_pipeline_status",
    "beagle_list_recent_runs",
    "beagle_get_science_job_status",
    "beagle_get_science_job_artifacts",
]);

function applyPolicy(tool: McpTool): McpTool {
    const policy = TOOL_POLICIES[tool.name];
    if (!policy) {
        return tool;
    }
    return {
        ...tool,
        annotations: policy.annotations,
        requiredScopes: policy.requiredScopes,
        riskLevel: policy.riskLevel,
    };
}

export function defineTools(client: BeagleClient): McpTool[] {
    const tools = [
        ...standardTools(client),
        // Core tools (canonical set)
        ...llmTools(client),
        ...pipelineTools(client),
        ...memoryTools(client),
        ...feedbackTools(client),
        ...exocortexTools(client),

        // Extended tools
        ...scienceJobTools(client),
        ...experimentalTools(client),
    ].map(applyPolicy);

    const surface = toolSurface();
    if (surface === "review_safe") {
        return tools.filter((tool) => REVIEW_SAFE_TOOL_NAMES.has(tool.name));
    }
    return tools;
}

export function toolSurface(): McpToolSurface {
    return process.env.MCP_TOOL_SURFACE === "review_safe" ? "review_safe" : "trusted_full";
}
