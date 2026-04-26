/**
 * Exocortex tools.
 *
 * These are the "nervous system" tools: they let external agents read and
 * mutate the cluster-canonical Beagle mind state.
 */

import { z } from "zod";
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

const OmniRawImportSchema = z.object({
    source_platform: z.string(),
    original_date: z.string().optional(),
    raw_content: z.string(),
    title: z.string().optional(),
    tags: z.array(z.string()).optional(),
    extracted: z.record(z.unknown()).optional(),
    confidence_score: z.number().min(0).max(1).optional(),
    create_chronoself_commit: z.boolean().optional(),
});

const OmniConversationImportSchema = z.object({
    source: z.string().min(1),
    session_id: z.string().min(1),
    turns: z.array(OmniTurnSchema).min(1),
    tags: z.array(z.string()).optional(),
    metadata: z.record(z.unknown()).optional(),
    original_date: z.string().optional(),
    title: z.string().optional(),
    confidence_score: z.number().min(0).max(1).optional(),
    create_chronoself_commit: z.boolean().optional(),
});

const OmniImportSchema = z.union([OmniRawImportSchema, OmniConversationImportSchema]);

type OmniImportInput = z.infer<typeof OmniImportSchema>;
type OmniImportRequest = z.infer<typeof OmniRawImportSchema>;

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
        confidence_score: input.confidence_score ?? 0.7,
        create_chronoself_commit: input.create_chronoself_commit ?? false,
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
                    confidence_score: { type: "number", minimum: 0, maximum: 1 },
                    create_chronoself_commit: { type: "boolean" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = OmniImportSchema.parse(args ?? {});
                return sanitizeOutput(await client.omnimemoryImport(normalizeOmniImport(parsed)));
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
