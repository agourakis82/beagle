/**
 * Exocortex tools.
 *
 * These are the "nervous system" tools: they let external agents read and
 * mutate the cluster-canonical Beagle mind state.
 */

import { z } from "zod";
import crypto from "node:crypto";
import { BeagleClient } from "../beagle-client.js";
import { sanitizeOutput } from "../security.js";
import { McpTool } from "./index.js";

const HomeSchema = z.object({
    active_project_slug: z.string().optional(),
    platform: z.string().optional().default("mcp"),
});

const CommitSchema = z.object({
    user_id: z.string().optional(),
    self_version: z.string().optional(),
    parent_commit_ids: z.array(z.string()).optional(),
    context_snapshot: z.record(z.unknown()).optional(),
    identity_delta: z.record(z.unknown()).optional().default({}),
    trigger_type: z.string().optional().default("manual"),
    confidence: z.number().min(0).max(1).optional(),
    source_refs: z.array(z.string()).optional(),
    summary: z.string().optional(),
});

const OmniTurnSchema = z.object({
    role: z.string().min(1),
    content: z.string().min(1),
    timestamp: z.string().optional(),
    model: z.string().optional(),
});

const PrivacyClassSchema = z.enum(["public", "sensitive", "restricted"]);

const OmniRawImportSchema = z.object({
    source_platform: z.string(),
    session_id: z.string().optional(),
    original_date: z.string().optional(),
    raw_content: z.string(),
    title: z.string().optional(),
    tags: z.array(z.string()).optional(),
    extracted: z.record(z.unknown()).optional(),
    privacy_class: PrivacyClassSchema.optional(),
    metadata: z.record(z.unknown()).optional(),
    confidence_score: z.number().min(0).max(1).optional(),
    create_chronoself_commit: z.boolean().optional(),
});

const OmniConversationImportSchema = z.object({
    source: z.string().min(1),
    session_id: z.string().min(1),
    turns: z.array(OmniTurnSchema).min(1),
    tags: z.array(z.string()).optional(),
    metadata: z.record(z.unknown()).optional(),
    privacy_class: PrivacyClassSchema.optional(),
    original_date: z.string().optional(),
    title: z.string().optional(),
    confidence_score: z.number().min(0).max(1).optional(),
    create_chronoself_commit: z.boolean().optional(),
});

const OmniImportSchema = z.union([OmniRawImportSchema, OmniConversationImportSchema]);

type OmniImportInput = z.infer<typeof OmniImportSchema>;
type OmniImportRequest = z.infer<typeof OmniRawImportSchema>;
type AssistedImportBatchInput = z.infer<typeof AssistedImportBatchSchema>;

const TemporalAnalyzeSchema = z.object({
    topic: z.string(),
    days_back: z.number().int().min(1).max(3650).optional(),
    time_range_start: z.string().optional(),
    time_range_end: z.string().optional(),
});

const GoDeeperSchema = z.object({
    modality: z
        .enum(["deep_research", "swarm", "temporal", "neurosymbolic", "causal"])
        .default("deep_research"),
    query: z.string(),
});

const RoundTableSchema = z.object({
    prompt: z.string(),
    voices: z.array(z.string()).optional().default([]),
});

const AgentSessionsSchema = z.object({
    project_slug: z.string().default("sounio"),
});

const AgentStartSchema = z.object({
    project_slug: z.string().default("sounio"),
    kind: z.string().default("claude-code"),
    objective: z.string().optional(),
});

const ProjectMemorySchema = z.object({
    rebuild: z.boolean().optional().default(false),
    source_refs: z.array(z.string()).optional().default([]),
});

const GraphBakeoffSchema = z.object({
    dataset_limit: z.number().int().min(1).max(2000).optional().default(200),
    include_baseline: z.boolean().optional().default(true),
});

const GraphIndexSchema = z.object({
    rebuild: z.boolean().optional().default(false),
    source_refs: z.array(z.string()).optional().default([]),
    runtime: z.string().optional(),
});

const GraphRagQuerySchema = z.object({
    query: z.string().min(1),
    scope: z.string().optional(),
    max_items: z.number().int().min(1).max(20).optional().default(5),
    mode: z
        .enum(["graphsearch-lite", "drift-lite", "local", "global", "hybrid", "adaptive-federation"])
        .optional()
        .default("graphsearch-lite"),
});

const MemoryMeshQuerySchema = z.object({
    query: z.string().min(1),
    scope: z.string().optional(),
    max_items: z.number().int().min(1).max(20).optional().default(8),
    mode: z.string().optional().default("adaptive-federation"),
});

const MemoryEngineBakeoffRunSchema = z.object({
    limit: z.number().int().min(1).max(10000).optional().default(1000),
    domains: z.array(z.string()).optional(),
});

const MemoryCandidatesListSchema = z.object({
    limit: z.number().int().min(1).max(100).optional().default(20),
});

const MemoryCandidateQuorumSchema = z.object({
    candidate_id: z.string().min(1),
    memory_approved: z.boolean().default(false),
    temporal_approved: z.boolean().default(false),
    critical_approved: z.boolean().default(false),
    rationale: z.string().optional(),
    reviewer: z.string().optional().default("mcp-agent"),
    quality_score: z
        .object({
            provenance_score: z.number().min(0).max(1).optional(),
            temporal_score: z.number().min(0).max(1).optional(),
            critical_score: z.number().min(0).max(1).optional(),
            restricted_risk: z.number().min(0).max(1).optional(),
            contradiction_risk: z.number().min(0).max(1).optional(),
            rationale: z.string().optional(),
        })
        .optional(),
});

const MemoryGovernanceRunSchema = z.object({
    limit: z.number().int().min(1).max(1000).optional().default(100),
    reviewer: z.string().optional().default("mcp-agent"),
    dry_run: z.boolean().optional().default(false),
});

const MemoryContradictionsSchema = z.object({
    limit: z.number().int().min(1).max(100).optional().default(20),
});

const MemoryEngineEvalRunSchema = z.object({
    limit: z.number().int().min(1).max(10000).optional().default(1000),
    domains: z.array(z.string()).optional(),
    judge_mode: z.string().optional(),
});

const MemoryEngineGovernanceEvaluateSchema = z.object({
    limit: z.number().int().min(1).max(1000).optional().default(100),
    reviewer: z.string().optional().default("mcp-agent"),
    dry_run: z.boolean().optional().default(false),
});

const WorkMemoryCaptureSchema = z.object({
    agent_kind: z.string().min(1).default("codex"),
    source_surface: z.string().min(1).optional(),
    session_id: z.string().min(1),
    project_slug: z.string().min(1).default("beagle"),
    repo: z.string().optional(),
    branch: z.string().optional(),
    phase: z
        .enum(["start", "plan", "decision", "diff", "test", "summary", "next_action"])
        .default("summary"),
    summary: z.string().min(1),
    plan: z.array(z.string()).optional().default([]),
    decisions: z.array(z.string()).optional().default([]),
    tests_run: z.array(z.string()).optional().default([]),
    diff_summary: z.string().optional(),
    next_action: z.string().optional(),
    tags: z.array(z.string()).optional().default([]),
    metadata: z.record(z.unknown()).optional().default({}),
    privacy_class: PrivacyClassSchema.default("sensitive"),
});

const AssistedImportBatchSchema = z.object({
    source_platform: z.string().min(1),
    source_surface: z.string().min(1).default("mcp-visible-context"),
    import_scope: z
        .enum(["current_conversation", "visible_project", "user_supplied_export"])
        .default("current_conversation"),
    session_id: z.string().min(1),
    project_ref: z.string().optional(),
    batch_index: z.number().int().min(1).default(1),
    batch_total: z.number().int().min(1).default(1),
    turns: z.array(OmniTurnSchema).min(1),
    tags: z.array(z.string()).optional().default([]),
    metadata: z.record(z.unknown()).optional().default({}),
    coverage: z.record(z.unknown()).optional().default({}),
    extracted: z.record(z.unknown()).optional(),
    privacy_class: PrivacyClassSchema.default("sensitive"),
    title: z.string().optional(),
    original_date: z.string().optional(),
    confidence_score: z.number().min(0).max(1).optional(),
    create_chronoself_commit: z.boolean().optional().default(false),
});

function uniqueNonEmpty(values: Array<string | undefined>): string[] {
    return Array.from(new Set(values.map((value) => value?.trim()).filter((value): value is string => Boolean(value))));
}

function metadataStringArray(metadata: Record<string, unknown> | undefined, key: string): string[] {
    const value = metadata?.[key];
    if (Array.isArray(value)) {
        return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
    }
    if (typeof value === "string" && value.trim().length > 0) {
        return [value.trim()];
    }
    return [];
}

function normalizeOmniImport(input: OmniImportInput): OmniImportRequest {
    if ("raw_content" in input) {
        return input;
    }

    const metadata = input.metadata ?? {};
    const tags = uniqueNonEmpty([...(input.tags ?? []), input.source, "conversation"]);
    const firstTimestamp = input.turns.find((turn) => turn.timestamp)?.timestamp;
    const rawContent = input.turns
        .map((turn) => {
            const timestamp = turn.timestamp ? ` @ ${turn.timestamp}` : "";
            const model = turn.model ? `/${turn.model}` : "";
            return `[${turn.role}${model}${timestamp}]\n${turn.content}`;
        })
        .join("\n\n");

    return {
        source_platform: input.source,
        session_id: input.session_id,
        original_date: input.original_date ?? firstTimestamp,
        raw_content: rawContent,
        title: input.title ?? `${input.source} conversation ${input.session_id}`,
        tags,
        extracted: {
            key_insights: [],
            decisions: [],
            hypotheses: [],
            belief_changes: [],
            projects_mentioned: uniqueNonEmpty([
                ...metadataStringArray(metadata, "project"),
                ...metadataStringArray(metadata, "projects"),
            ]),
            unresolved_questions: [],
            identity_signals: {
                import_kind: "conversation_turns",
                session_id: input.session_id,
                source: input.source,
                turn_count: input.turns.length,
                tags,
                metadata,
            },
        },
        privacy_class: input.privacy_class ?? "sensitive",
        metadata,
        confidence_score: input.confidence_score ?? 0.7,
        create_chronoself_commit: input.create_chronoself_commit ?? false,
    };
}

function sha256Text(value: string): string {
    return crypto.createHash("sha256").update(value).digest("hex");
}

function enrichOmniImport(input: OmniImportRequest): OmniImportRequest {
    const contentHash = sha256Text(input.raw_content);
    const existingSignals =
        input.extracted?.identity_signals &&
        typeof input.extracted.identity_signals === "object" &&
        !Array.isArray(input.extracted.identity_signals)
            ? input.extracted.identity_signals
            : {};
    return {
        ...input,
        privacy_class: input.privacy_class ?? "sensitive",
        metadata: {
            ...(input.metadata ?? {}),
            privacy_class: input.privacy_class ?? "sensitive",
        },
        tags: uniqueNonEmpty([
            ...(input.tags ?? []),
            `source:${input.source_platform}`,
            `hash:${contentHash.slice(0, 12)}`,
            `privacy:${input.privacy_class ?? "sensitive"}`,
        ]),
        extracted: {
            ...(input.extracted ?? {
                key_insights: [],
                decisions: [],
                hypotheses: [],
                belief_changes: [],
                projects_mentioned: [],
                unresolved_questions: [],
            }),
            identity_signals: {
                ...existingSignals,
                provenance: {
                    source_platform: input.source_platform,
                    imported_via: "mcp",
                    content_hash: `sha256:${contentHash}`,
                    explicit_import_only: true,
                },
                privacy_class: input.privacy_class ?? "sensitive",
                dedupe: {
                    strategy: "source_platform_raw_content_hash",
                    key: `${input.source_platform}:sha256:${contentHash}`,
                    content_hash: `sha256:${contentHash}`,
                },
            },
        },
    };
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function omnimemorySourceRefs(imported: unknown): string[] {
    if (!isRecord(imported)) {
        return [];
    }
    const refs: string[] = [];
    if (typeof imported.id === "string" && imported.id.trim().length > 0) {
        refs.push(`omnimemory:${imported.id}`);
    }
    if (typeof imported.raw_content_ref === "string" && imported.raw_content_ref.trim().length > 0) {
        refs.push(imported.raw_content_ref);
    }
    return refs;
}

function assistedRawContent(input: AssistedImportBatchInput): string {
    return input.turns
        .map((turn, index) => {
            const timestamp = turn.timestamp ? ` @ ${turn.timestamp}` : "";
            const model = turn.model ? `/${turn.model}` : "";
            return `[${index + 1}:${turn.role}${model}${timestamp}]\n${turn.content}`;
        })
        .join("\n\n");
}

function assistedImportPayload(input: AssistedImportBatchInput): OmniImportRequest {
    const tags = uniqueNonEmpty([
        ...input.tags,
        input.source_platform,
        input.source_surface,
        input.import_scope,
        input.project_ref ? `project:${input.project_ref}` : undefined,
        "assisted-import",
        "graphrag-projection",
    ]);
    const firstTimestamp = input.turns.find((turn) => turn.timestamp)?.timestamp;
    const metadata = {
        ...input.metadata,
        import_scope: input.import_scope,
        source_surface: input.source_surface,
        session_id: input.session_id,
        project_ref: input.project_ref,
        batch_index: input.batch_index,
        batch_total: input.batch_total,
        coverage: input.coverage,
        explicit_import_only: true,
    };

    return {
        source_platform: input.source_platform,
        session_id: input.session_id,
        original_date: input.original_date ?? firstTimestamp,
        raw_content: assistedRawContent(input),
        title:
            input.title ??
            `${input.source_platform} ${input.import_scope} ${input.session_id} batch ${input.batch_index}/${input.batch_total}`,
        tags,
        extracted: input.extracted,
        privacy_class: input.privacy_class,
        metadata,
        confidence_score: input.confidence_score ?? 0.76,
        create_chronoself_commit: input.create_chronoself_commit,
    };
}

function workMemoryCapturePayload(input: z.infer<typeof WorkMemoryCaptureSchema>): AssistedImportBatchInput {
    const sourceSurface = input.source_surface ?? `${input.agent_kind}-work-memory`;
    const lines = [
        `Phase: ${input.phase}`,
        `Summary: ${input.summary}`,
        input.repo ? `Repo: ${input.repo}` : undefined,
        input.branch ? `Branch: ${input.branch}` : undefined,
        input.plan.length ? `Plan:\n${input.plan.map((item) => `- ${item}`).join("\n")}` : undefined,
        input.decisions.length
            ? `Decisions:\n${input.decisions.map((item) => `- ${item}`).join("\n")}`
            : undefined,
        input.tests_run.length
            ? `Tests:\n${input.tests_run.map((item) => `- ${item}`).join("\n")}`
            : undefined,
        input.diff_summary ? `Diff: ${input.diff_summary}` : undefined,
        input.next_action ? `Next action: ${input.next_action}` : undefined,
    ].filter((line): line is string => Boolean(line));

    const tags = uniqueNonEmpty([
        ...input.tags,
        "work-memory",
        "graphrag++",
        `agent:${input.agent_kind}`,
        `phase:${input.phase}`,
        `project:${input.project_slug}`,
        input.repo ? `repo:${input.repo}` : undefined,
        input.branch ? `branch:${input.branch}` : undefined,
    ]);

    return {
        source_platform: input.agent_kind,
        source_surface: sourceSurface,
        import_scope: "visible_project",
        session_id: input.session_id,
        project_ref: input.project_slug,
        batch_index: 1,
        batch_total: 1,
        turns: [
            {
                role: "assistant",
                content: lines.join("\n\n"),
                timestamp: new Date().toISOString(),
                model: input.agent_kind,
            },
        ],
        tags,
        metadata: {
            ...input.metadata,
            principal: input.metadata.principal ?? input.agent_kind,
            source_platform: input.agent_kind,
            source_surface: sourceSurface,
            surface_claimed: sourceSurface,
            work_memory: true,
            project_slug: input.project_slug,
            repo: input.repo,
            branch: input.branch,
            phase: input.phase,
            tests_run: input.tests_run,
            diff_summary: input.diff_summary,
            next_action: input.next_action,
        },
        coverage: {
            work_memory_fields: lines.length,
            visible_project_only: true,
        },
        extracted: {
            key_insights: [input.summary],
            decisions: input.decisions,
            hypotheses: [],
            belief_changes: [],
            projects_mentioned: [input.project_slug],
            unresolved_questions: input.next_action ? [input.next_action] : [],
        },
        privacy_class: input.privacy_class,
        title: `${input.agent_kind} work memory ${input.phase}: ${input.project_slug}`,
        confidence_score: 0.82,
        create_chronoself_commit: false,
    };
}

export function exocortexTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_exocortex_home",
            description:
                "Read the cluster-canonical Exocortex Home snapshot: current self, memory signals, body context, cluster truth, and next action.",
            inputSchema: {
                type: "object",
                properties: {
                    active_project_slug: { type: "string" },
                    platform: { type: "string", default: "mcp" },
                },
            },
            handler: async (args: unknown) => {
                const { active_project_slug, platform } = HomeSchema.parse(args ?? {});
                return sanitizeOutput(await client.exocortexHome(active_project_slug, platform));
            },
        },
        {
            name: "beagle_chronoself_current",
            description: "Read the current Chronoself SelfVersion from the cluster.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.chronoselfCurrent()),
        },
        {
            name: "beagle_chronoself_commits",
            description: "Read recent immutable Chronoself commits.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 100, default: 20 },
                },
            },
            handler: async (args: unknown) => {
                const parsed = z.object({ limit: z.number().int().min(1).max(100).default(20) }).parse(args ?? {});
                return sanitizeOutput(await client.chronoselfCommits(parsed.limit));
            },
        },
        {
            name: "beagle_chronoself_create_commit",
            description:
                "Create an immutable Chronoself commit. Use for explicit decisions, milestones, identity shifts, or important agent observations.",
            inputSchema: {
                type: "object",
                properties: {
                    user_id: { type: "string" },
                    self_version: { type: "string" },
                    parent_commit_ids: { type: "array", items: { type: "string" } },
                    context_snapshot: {
                        type: "object",
                        additionalProperties: true,
                        properties: {
                            health_ref: { type: "string" },
                            active_project_ids: { type: "array", items: { type: "string" } },
                            recent_decision_ids: { type: "array", items: { type: "string" } },
                            energy_level: { type: "number" },
                            emotional_valence: { type: "number" },
                            platform: { type: "string" },
                            target_hardware: {
                                type: "object",
                                properties: {
                                    phone: { type: "string" },
                                    watch: { type: "string" },
                                    tablet: { type: "string" },
                                    desktop: { type: "string" },
                                    spatial: { type: "string" },
                                    notes: { type: "array", items: { type: "string" } },
                                },
                            },
                        },
                    },
                    identity_delta: {
                        type: "object",
                        additionalProperties: true,
                        properties: {
                            beliefs_added: { type: "array", items: { type: "string" } },
                            beliefs_removed: { type: "array", items: { type: "string" } },
                            values_changed: { type: "array", items: { type: "object", additionalProperties: true } },
                            cognitive_style_shift: { type: "string" },
                            priority_reordering: { type: "array", items: { type: "string" } },
                            product_principles: { type: "array", items: { type: "string" } },
                        },
                    },
                    trigger_type: { type: "string", default: "manual" },
                    confidence: { type: "number", minimum: 0, maximum: 1 },
                    source_refs: { type: "array", items: { type: "string" } },
                    summary: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = CommitSchema.parse(args ?? {});
                return sanitizeOutput(await client.chronoselfCreateCommit(parsed));
            },
        },
        {
            name: "beagle_omnimemory_import",
            description:
                "Import a ChatGPT/Claude/Grok/Gemini/manual conversation into OmniMemory and optionally create linked Chronoself commits.",
            inputSchema: {
                type: "object",
                oneOf: [
                    { required: ["source_platform", "raw_content"] },
                    { required: ["source", "session_id", "turns"] },
                ],
                properties: {
                    source_platform: { type: "string" },
                    source: { type: "string" },
                    session_id: { type: "string" },
                    turns: {
                        type: "array",
                        items: {
                            type: "object",
                            required: ["role", "content"],
                            properties: {
                                role: { type: "string" },
                                content: { type: "string" },
                                timestamp: { type: "string" },
                                model: { type: "string" },
                            },
                        },
                    },
                    metadata: { type: "object", additionalProperties: true },
                    original_date: { type: "string" },
                    raw_content: { type: "string" },
                    title: { type: "string" },
                    tags: { type: "array", items: { type: "string" } },
                    extracted: { type: "object", additionalProperties: true },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    confidence_score: { type: "number", minimum: 0, maximum: 1 },
                    create_chronoself_commit: { type: "boolean" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = OmniImportSchema.parse(args ?? {});
                return sanitizeOutput(
                    await client.omnimemoryImport(enrichOmniImport(normalizeOmniImport(parsed))),
                );
            },
        },
        {
            name: "beagle_assisted_import_batch",
            description:
                "Import visible or user-supplied conversation context as projected GraphRAG++ memory with episode and atom records.",
            inputSchema: {
                type: "object",
                required: ["source_platform", "session_id", "turns"],
                properties: {
                    source_platform: { type: "string" },
                    source_surface: { type: "string", default: "mcp-visible-context" },
                    import_scope: {
                        type: "string",
                        enum: ["current_conversation", "visible_project", "user_supplied_export"],
                        default: "current_conversation",
                    },
                    session_id: { type: "string" },
                    project_ref: { type: "string" },
                    batch_index: { type: "number", minimum: 1, default: 1 },
                    batch_total: { type: "number", minimum: 1, default: 1 },
                    turns: {
                        type: "array",
                        minItems: 1,
                        items: {
                            type: "object",
                            required: ["role", "content"],
                            properties: {
                                role: { type: "string" },
                                content: { type: "string" },
                                timestamp: { type: "string" },
                                model: { type: "string" },
                            },
                        },
                    },
                    tags: { type: "array", items: { type: "string" } },
                    metadata: { type: "object", additionalProperties: true },
                    coverage: { type: "object", additionalProperties: true },
                    extracted: { type: "object", additionalProperties: true },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    title: { type: "string" },
                    original_date: { type: "string" },
                    confidence_score: { type: "number", minimum: 0, maximum: 1 },
                    create_chronoself_commit: { type: "boolean", default: false },
                },
            },
            handler: async (args: unknown) => {
                const parsed = AssistedImportBatchSchema.parse(args ?? {});
                return sanitizeOutput(await client.assistedImportBatch(parsed));
            },
        },
        {
            name: "beagle_memory_project_graph",
            description:
                "Run the idempotent GraphRAG++ projection over OmniMemory imports and memory events.",
            inputSchema: {
                type: "object",
                properties: {
                    rebuild: { type: "boolean", default: false },
                    source_refs: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const parsed = ProjectMemorySchema.parse(args ?? {});
                return sanitizeOutput(await client.projectMemory(parsed));
            },
        },
        {
            name: "beagle_memory_graph_status",
            description:
                "Read the living GraphRAG++ runtime status: current graph runtime hypothesis, projection freshness, MemoryWorld count, latest bake-off, and degraded mode.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.memoryGraphStatus()),
        },
        {
            name: "beagle_memory_bakeoff_status",
            description:
                "Read the latest FalkorDB vs Memgraph vs SurrealDB GraphRAG++ bake-off status and candidate metrics.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.memoryGraphBakeoffStatus()),
        },
        {
            name: "beagle_graphrag_query",
            description:
                "Query Beagle's GraphRAG++ living memory with evidence graph, temporal context, provenance, community context, and retrieval trace.",
            inputSchema: {
                type: "object",
                required: ["query"],
                properties: {
                    query: { type: "string" },
                    scope: { type: "string" },
                    max_items: { type: "number", minimum: 1, maximum: 20, default: 5 },
                    mode: {
                        type: "string",
                        enum: ["graphsearch-lite", "drift-lite", "local", "global", "hybrid", "adaptive-federation"],
                        default: "graphsearch-lite",
                    },
                },
            },
            handler: async (args: unknown) => {
                const parsed = GraphRagQuerySchema.parse(args ?? {});
                return sanitizeOutput(await client.graphRagQuery(parsed));
            },
        },
        {
            name: "beagle_memory_engine_status",
            description:
                "Read Beagle Memory Engine v1.6 federated runtime mesh and governor status across online graph, analytics, vector, and ontology candidates.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.memoryEngineStatus()),
        },
        {
            name: "beagle_memory_mesh_query",
            description:
                "Query the federated Beagle Memory Engine mesh with adaptive runtime voting, core canonical merge, mesh trace, and degraded fallback.",
            inputSchema: {
                type: "object",
                required: ["query"],
                properties: {
                    query: { type: "string" },
                    scope: { type: "string" },
                    max_items: { type: "number", minimum: 1, maximum: 20, default: 8 },
                    mode: { type: "string", default: "adaptive-federation" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryMeshQuerySchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryMeshQuery(parsed));
            },
        },
        {
            name: "beagle_memory_bakeoff_run",
            description:
                "Start a cluster-only Beagle Memory Engine v1.6 shadow bake-off over sanitized real/synthetic golden queries and federated runtime candidates.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 10000, default: 1000 },
                    domains: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryEngineBakeoffRunSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryEngineBakeoffRun(parsed));
            },
        },
        {
            name: "beagle_memory_candidates_list",
            description:
                "List candidate atoms/hyperedges proposed by the memory engine; candidates are excluded from active retrieval until strict Triad quorum promotion.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 100, default: 20 },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryCandidatesListSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryCandidates(parsed.limit));
            },
        },
        {
            name: "beagle_memory_candidate_quorum",
            description:
                "Record a strict Memory+Temporal+Critical Triad quorum decision for a candidate memory item without destructive actions.",
            inputSchema: {
                type: "object",
                required: ["candidate_id"],
                properties: {
                    candidate_id: { type: "string" },
                    memory_approved: { type: "boolean", default: false },
                    temporal_approved: { type: "boolean", default: false },
                    critical_approved: { type: "boolean", default: false },
                    rationale: { type: "string" },
                    reviewer: { type: "string", default: "mcp-agent" },
                    quality_score: {
                        type: "object",
                        additionalProperties: true,
                        properties: {
                            provenance_score: { type: "number", minimum: 0, maximum: 1 },
                            temporal_score: { type: "number", minimum: 0, maximum: 1 },
                            critical_score: { type: "number", minimum: 0, maximum: 1 },
                            restricted_risk: { type: "number", minimum: 0, maximum: 1 },
                            contradiction_risk: { type: "number", minimum: 0, maximum: 1 },
                            rationale: { type: "string" },
                        },
                    },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryCandidateQuorumSchema.parse(args ?? {});
                const { candidate_id, ...body } = parsed;
                return sanitizeOutput(await client.memoryCandidateQuorum(candidate_id, body));
            },
        },
        {
            name: "beagle_memory_governance_status",
            description:
                "Read the v1.6 Memory Governor status: pending Triad candidates, promoted/rejected counts, open contradictions, and promoted-only retrieval policy.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.memoryGovernanceStatus()),
        },
        {
            name: "beagle_memory_governance_run",
            description:
                "Run the append-only v1.6 Memory Governor over candidate memories to score quality, detect contradictions, and move candidates into Triad pending state.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 1000, default: 100 },
                    reviewer: { type: "string", default: "mcp-agent" },
                    dry_run: { type: "boolean", default: false },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryGovernanceRunSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryGovernanceRun(parsed));
            },
        },
        {
            name: "beagle_memory_contradictions_recent",
            description:
                "Read recent contradiction candidates detected by the Memory Governor before promotion into active GraphRAG++ memory.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 100, default: 20 },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryContradictionsSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryContradictions(parsed.limit));
            },
        },
        {
            name: "beagle_memory_engine_eval_run",
            description:
                "Start a v1.6 shadow evaluation run over 60 golden queries and hard gates before any runtime canary promotion.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 10000, default: 1000 },
                    domains: { type: "array", items: { type: "string" } },
                    judge_mode: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryEngineEvalRunSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryEngineEvalRun(parsed));
            },
        },
        {
            name: "beagle_memory_engine_governance_evaluate",
            description:
                "Ask the memory-engine to trigger the core Memory Governor and persist a cluster-only governance evaluation artifact.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 1000, default: 100 },
                    reviewer: { type: "string", default: "mcp-agent" },
                    dry_run: { type: "boolean", default: false },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryEngineGovernanceEvaluateSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryEngineGovernanceEvaluate(parsed));
            },
        },
        {
            name: "beagle_work_memory_capture",
            description:
                "Capture Claude Code/Codex work memory into the same Episode+Atom GraphRAG++ memory loop: plan, decisions, tests, diffs, summary, and next action.",
            inputSchema: {
                type: "object",
                required: ["session_id", "summary"],
                properties: {
                    agent_kind: { type: "string", default: "codex" },
                    source_surface: { type: "string" },
                    session_id: { type: "string" },
                    project_slug: { type: "string", default: "beagle" },
                    repo: { type: "string" },
                    branch: { type: "string" },
                    phase: {
                        type: "string",
                        enum: ["start", "plan", "decision", "diff", "test", "summary", "next_action"],
                        default: "summary",
                    },
                    summary: { type: "string" },
                    plan: { type: "array", items: { type: "string" } },
                    decisions: { type: "array", items: { type: "string" } },
                    tests_run: { type: "array", items: { type: "string" } },
                    diff_summary: { type: "string" },
                    next_action: { type: "string" },
                    tags: { type: "array", items: { type: "string" } },
                    metadata: { type: "object", additionalProperties: true },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                },
            },
            handler: async (args: unknown) => {
                const parsed = WorkMemoryCaptureSchema.parse(args ?? {});
                return sanitizeOutput(await client.assistedImportBatch(workMemoryCapturePayload(parsed)));
            },
        },
        {
            name: "beagle_temporal_analyze",
            description:
                "Run TemporalAI analysis over the cluster-canonical Chronoself and OmniMemory history for a topic.",
            inputSchema: {
                type: "object",
                required: ["topic"],
                properties: {
                    topic: { type: "string" },
                    days_back: { type: "number", minimum: 1, maximum: 3650 },
                    time_range_start: { type: "string" },
                    time_range_end: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = TemporalAnalyzeSchema.parse(args);
                return sanitizeOutput(await client.temporalAnalyze(parsed));
            },
        },
        {
            name: "beagle_go_deeper",
            description:
                "Invoke a Go Deeper modality: deep research, swarm, temporal, neurosymbolic, or causal reasoning.",
            inputSchema: {
                type: "object",
                required: ["query"],
                properties: {
                    modality: {
                        type: "string",
                        enum: ["deep_research", "swarm", "temporal", "neurosymbolic", "causal"],
                        default: "deep_research",
                    },
                    query: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const { modality, query } = GoDeeperSchema.parse(args);
                return sanitizeOutput(await client.goDeeper(modality, query));
            },
        },
        {
            name: "beagle_round_table",
            description:
                "Convoke Beagle's Round Table voices for deliberation over a prompt.",
            inputSchema: {
                type: "object",
                required: ["prompt"],
                properties: {
                    prompt: { type: "string" },
                    voices: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const { prompt, voices } = RoundTableSchema.parse(args);
                return sanitizeOutput(await client.roundTable(prompt, voices));
            },
        },
        {
            name: "beagle_agent_sessions",
            description: "List external/persistent agent sessions for a Beagle project through the cockpit boundary.",
            inputSchema: {
                type: "object",
                properties: {
                    project_slug: { type: "string", default: "sounio" },
                },
            },
            handler: async (args: unknown) => {
                const { project_slug } = AgentSessionsSchema.parse(args ?? {});
                return sanitizeOutput(await client.agentSessions(project_slug));
            },
        },
        {
            name: "beagle_agent_session_start",
            description:
                "Start or request a persistent external agent session for a project. Authenticated MCP agents are broadly trusted in v1.",
            inputSchema: {
                type: "object",
                properties: {
                    project_slug: { type: "string", default: "sounio" },
                    kind: { type: "string", default: "claude-code" },
                    objective: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const { project_slug, kind, objective } = AgentStartSchema.parse(args ?? {});
                return sanitizeOutput(await client.startAgentSession(project_slug, kind, objective));
            },
        },
    ];
}
