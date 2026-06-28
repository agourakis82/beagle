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

const AgentRegistrySchema = z.object({
    project_slug: z.string().default("sounio"),
});

const AgentRouteSchema = z.object({
    project_slug: z.string().default("sounio"),
    task: z.string().min(1),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    arousal_mode: z
        .enum(["phasic_focus", "tonic_explore", "blocked", "recovering", "fatigued"])
        .optional(),
    fallback_roles: z.array(z.string()).optional(),
});

const WriteProbeSchema = z.object({
    principal: z.string().optional().default("mcp-agent"),
    source_platform: z.string().optional().default("mcp"),
    source_surface: z.string().optional().default("mcp"),
    required_scopes: z.array(z.string()).optional().default(["memory:write"]),
    granted_scopes: z.array(z.string()).optional().default([]),
    payload_kind: z.string().optional().default("memory_write"),
    metadata: z.record(z.unknown()).optional().default({}),
});

const FailedWriteInboxSchema = z.object({
    limit: z.number().int().min(1).max(100).optional().default(25),
});

const FailedWriteRescueSchema = z.object({
    failed_write_id: z.string().optional(),
    reason: z.string().optional().default("claude_ios_failed_write_rescue"),
    source_platform: z.string().optional().default("claude"),
    source_surface: z.string().optional().default("claude-ios"),
    principal: z.string().optional().default("claude-ios"),
    summary: z.string().optional(),
    session_id: z.string().optional(),
    project_ref: z.string().optional().default("sounio"),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    payload_kind: z.string().optional().default("sounio_insight"),
    turns: z.array(OmniTurnSchema).optional().default([]),
    tags: z.array(z.string()).optional().default([]),
    artifact_refs: z.array(z.string()).optional().default([]),
    candidate_refs: z.array(z.string()).optional().default([]),
    metadata: z.record(z.unknown()).optional().default({}),
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
    ranking_policy: z.enum(["strict_recent_guarded", "legacy_stable"]).optional(),
    mode: z
        .enum([
            "hypermemory_multivector",
            "hypermemory",
            "graphsearch-lite",
            "drift-lite",
            "local",
            "global",
            "hybrid",
            "adaptive-federation",
        ])
        .optional()
        .default("hypermemory_multivector"),
});

const MemoryMeshQuerySchema = z.object({
    query: z.string().min(1),
    scope: z.string().optional(),
    max_items: z.number().int().min(1).max(20).optional().default(8),
    mode: z.string().optional().default("hypermemory_multivector"),
});

const SemanticIndexRebuildSchema = z.object({
    limit: z.number().int().min(1).max(50000).optional().default(10000),
    include_candidates: z.boolean().optional().default(true),
});

const RetrievalTraceSchema = z.object({
    query: z.string().min(1),
    scope: z.string().optional(),
    max_items: z.number().int().min(1).max(20).optional().default(8),
    mode: z
        .enum(["hypermemory_multivector", "hypermemory", "graphsearch-lite"])
        .optional()
        .default("hypermemory_multivector"),
});

const RetrievalAgentQuerySchema = z.object({
    query: z.string().min(1),
    scope: z.string().optional(),
    max_items: z.number().int().min(1).max(20).optional().default(8),
    mode: z
        .enum(["hypermemory_multivector", "hypermemory", "graphsearch-lite"])
        .optional()
        .default("hypermemory_multivector"),
    planner_mode: z.enum(["deterministic", "hybrid", "llm"]).optional().default("hybrid"),
    surface: z.string().optional().default("mcp-retrieval-agent"),
});

const ContextCompileSchema = z.object({
    query: z.string().min(1),
    scope: z.string().optional(),
    surface: z.string().optional().default("mcp-context-compiler"),
    task: z.string().optional(),
    max_items: z.number().int().min(1).max(20).optional().default(8),
    mode: z
        .enum(["hypermemory_multivector", "hypermemory", "graphsearch-lite"])
        .optional()
        .default("hypermemory_multivector"),
    planner_mode: z.enum(["deterministic", "hybrid", "llm"]).optional().default("hybrid"),
    token_budget: z.number().int().min(256).max(64000).optional(),
    agent: z.string().optional(),
    session_id: z.string().optional(),
});

const ContextPackGetSchema = z.object({
    context_pack_id: z.string().min(1),
});

const MemoryEffectivenessRecordSchema = z.object({
    context_pack_id: z.string().min(1),
    query: z.string().optional(),
    surface: z.string().optional().default("mcp"),
    principal: z.string().optional().default("mcp-agent"),
    session_id: z.string().optional(),
    strategy_used: z.string().optional(),
    tokens_used: z.number().int().min(0).optional(),
    latency_ms: z.number().min(0).optional(),
    tests: z.array(z.string()).optional().default([]),
    feedback: z.string().optional(),
    human_correction: z.string().optional(),
    success: z.boolean().optional(),
    outcome: z.string().optional().default("observed"),
    metadata: z.record(z.unknown()).optional().default({}),
});

const DreamCycleRunSchema = z.object({
    limit: z.number().int().min(1).max(5000).optional().default(500),
    mode: z.enum(["manual", "nightly"]).optional().default("manual"),
    triggered_by: z.string().optional().default("mcp-agent"),
    dry_run: z.boolean().optional().default(true),
});

const SounioGovernanceSchema = z.object({
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    provenance: z.record(z.unknown()).default({ source: "mcp-agent" }),
    restricted_leak_check: z.record(z.unknown()).default({ status: "required" }),
    human_approval_required: z.boolean().optional().default(true),
    policy_refs: z.array(z.string()).optional().default([]),
});

const SounioStepSchema = z.object({
    id: z.string().min(1),
    title: z.string().min(1),
    objective: z.string().optional(),
    agent: z.string().optional(),
    strategy: z.string().optional(),
    requires_human_approval: z.boolean().optional().default(false),
    provenance: z.record(z.unknown()).default({ source: "mcp-agent" }),
    governance: z.record(z.unknown()).default({ privacy_class: "sensitive", restricted_policy: "exclude" }),
});

const SounioProgramSchema = z.object({
    id: z.string().min(1),
    sounio_version: z.string().optional().default("0.1"),
    kind: z.string().optional().default("WorkProgram"),
    intent: z.string().min(1),
    context: z.record(z.unknown()).optional().default({}),
    plan: z.array(SounioStepSchema).min(1),
    actions: z.array(z.record(z.unknown())).optional().default([]),
    evidence: z.array(z.record(z.unknown())).optional().default([]),
    decisions: z.array(z.record(z.unknown())).optional().default([]),
    checks: z.array(z.record(z.unknown())).optional().default([]),
    outcome: z.string().optional(),
    next_action: z.string().optional(),
    governance: SounioGovernanceSchema,
});

const SounioProgramCheckSchema = z.object({
    source_format: z.enum(["json", "yaml", "sio"]).optional().default("json"),
    program: SounioProgramSchema,
});

const SounioPaperRunStartSchema = z.object({
    paper_id: z.string().optional(),
    title: z.string().optional(),
    principal: z.string().optional().default("mcp-agent"),
    surface: z.string().optional().default("mcp-sounio-paperrun"),
    temporal_namespace: z.string().optional(),
    temporal_task_queue: z.string().optional(),
    program: SounioProgramSchema.optional(),
    dry_run: z.boolean().optional().default(false),
});

const SounioPaperRunStatusSchema = z.object({
    paper_run_id: z.string().min(1),
});

const SounioPaperRunApproveStepSchema = z.object({
    paper_run_id: z.string().min(1),
    step_id: z.string().min(1),
    reviewer: z.string().optional().default("demetrios"),
    decision: z.enum(["approved", "rejected", "needs_revision"]).optional().default("approved"),
    rationale: z.string().optional(),
});

const SounioClaimInputSchema = z.object({
    id: z.string().optional(),
    claim_text: z.string().min(1),
    subject: z.string().optional(),
    value_type: z.string().optional().default("Claim<T>"),
    epistemic_status: z.enum(["belief", "contest", "knowledge", "robust"]).optional().default("belief"),
    evidence_refs: z.array(z.string()).optional().default([]),
    provenance: z.record(z.unknown()).optional().default({ source: "mcp-agent" }),
    confidence: z.number().min(0).max(1).optional(),
    contestation: z.record(z.unknown()).optional().default({}),
    review_state: z.string().optional().default("unreviewed"),
    promotion_rule: z.string().optional(),
    publication_readiness: z.string().optional().default("not_ready"),
    section_id: z.string().optional(),
    agent_refs: z.array(z.string()).optional().default([]),
    contract_refs: z.array(z.string()).optional().default([]),
    artifact_refs: z.array(z.string()).optional().default([]),
    chronoself_commit_refs: z.array(z.string()).optional().default([]),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    rationale: z.string().optional(),
});

const SounioClaimCheckSchema = z.object({
    claim: SounioClaimInputSchema,
});

const SounioMomentTypeSchema = z.object({
    source_event_refs: z.array(z.string()).optional().default([]),
    source_platform: z.string().optional().default("mcp-agent"),
    source_surface: z.string().optional().default("mcp-sounio-moment"),
    project_slug: z.string().optional().default("sounio"),
    session_id: z.string().optional(),
    intent_text: z.string().optional(),
    summary: z.string().optional(),
    evidence_refs: z.array(z.string()).optional().default([]),
    claim_seeds: z.array(SounioClaimInputSchema).optional().default([]),
    decision_seeds: z.array(z.string()).optional().default([]),
    next_action: z.string().optional(),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    review_state: z.string().optional().default("unreviewed"),
    provenance: z.record(z.unknown()).optional().default({ source: "mcp-agent" }),
    tags: z.array(z.string()).optional().default(["sounio", "ambient-typing"]),
});

const SounioWorkdayStatusSchema = z.object({
    project_slug: z.string().optional().default("sounio"),
    limit: z.number().int().min(1).max(100).optional().default(20),
});

const SounioMomentReviewSchema = z.object({
    moment_id: z.string().min(1),
    reviewer: z.string().optional().default("demetrios"),
    decision: z.enum(["approved", "rejected", "needs_revision", "mark_contest", "promote_claim_seed"]),
    rationale: z.string().optional(),
    evidence_refs: z.array(z.string()).optional().default([]),
    review_state: z.string().optional(),
    provenance: z.record(z.unknown()).optional().default({ source: "mcp-agent-review" }),
});

const SounioPaperRunAddClaimSchema = z.object({
    paper_run_id: z.string().min(1),
    claim: SounioClaimInputSchema,
    principal: z.string().optional().default("mcp-agent"),
    surface: z.string().optional().default("mcp-sounio-theatre"),
});

const SounioClaimReviewSchema = z.object({
    paper_run_id: z.string().min(1),
    claim_id: z.string().min(1),
    reviewer: z.string().optional().default("demetrios"),
    decision: z
        .enum(["approved", "rejected", "needs_evidence", "contest", "promote_to_knowledge", "promote_to_robust"])
        .default("approved"),
    rationale: z.string().optional(),
    evidence_refs: z.array(z.string()).optional().default([]),
    epistemic_status: z.enum(["belief", "contest", "knowledge", "robust"]).optional(),
    publication_readiness: z.string().optional(),
    provenance: z.record(z.unknown()).optional().default({ source: "mcp-agent-review" }),
});

const SounioPaperRunTheatreSchema = z.object({
    paper_run_id: z.string().min(1),
});

const SounioPublicDigestSchema = z.object({
    paper_run_id: z.string().min(1),
});

const SounioTraceQuerySchema = z.object({
    paper_run_id: z.string().optional(),
    limit: z.number().int().min(1).max(500).optional().default(50),
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

const MemoryBenchmarkRunSchema = z.object({
    limit: z.number().int().min(1).max(10000).optional().default(2000),
    domains: z.array(z.string()).optional(),
    judge_mode: z.string().optional(),
    include_mesh: z.boolean().optional().default(true),
    truthset_id: z.string().optional(),
    baseline_mode: z.string().optional().default("graphsearch-lite"),
    candidate_modes: z.array(z.string()).optional().default(["hypermemory_multivector", "hypermemory"]),
    promotion_policy: z
        .object({
            required_margin: z.number().min(0).max(1).optional().default(0.05),
            required_consecutive_runs: z.number().int().min(1).max(10).optional().default(3),
        })
        .optional(),
});

const MemoryArenaBenchmarkRunSchema = z.object({
    limit: z.number().int().min(1).max(10000).optional().default(2000),
    truthset_id: z.string().optional(),
    domains: z.array(z.string()).optional(),
    planner_mode: z.enum(["deterministic", "hybrid", "llm"]).optional().default("hybrid"),
    baseline_mode: z.string().optional().default("hypermemory_multivector-v2.1"),
    candidate_mode: z.string().optional().default("retrieval-agent-v2.2"),
});

const MemoryTruthsetDraftSchema = z.object({
    limit: z.number().int().min(1).max(10000).optional().default(2000),
    domains: z.array(z.string()).optional(),
    title: z.string().optional(),
    description: z.string().optional(),
    source_refs: z.array(z.string()).optional(),
    reviewer: z.string().optional().default("mcp-agent"),
});

const MemoryTruthsetReviewSchema = z.object({
    truthset_id: z.string().min(1),
    status: z.enum(["draft", "provisional_approved", "approved", "rejected"]).default("approved"),
    reviewer: z.string().optional().default("mcp-agent"),
    rationale: z.string().optional(),
});

const AgentObserverStatusSchema = z.object({
    platform: z.string().optional().default("mcp-agent-observer"),
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
    capture_session_id: z.string().optional(),
    artifact_refs: z.array(z.string()).optional().default([]),
    transcription_segments: z
        .array(
            z.object({
                text: z.string().min(1),
                start_ms: z.number().int().min(0).optional(),
                end_ms: z.number().int().min(0).optional(),
                confidence: z.number().min(0).max(1).optional(),
                source: z.string().optional(),
            }),
        )
        .optional()
        .default([]),
    visual_evidence_refs: z.array(z.string()).optional().default([]),
});

const CaptureSessionStartSchema = z.object({
    project_slug: z.string().optional().default("sounio"),
    mode: z.enum(["text", "thinking_aloud", "visual_evidence", "multimodal"]).optional().default("thinking_aloud"),
    surface: z.string().optional().default("mcp-capture"),
    principal: z.string().optional().default("mcp-agent"),
    title: z.string().optional(),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    metadata: z.record(z.unknown()).optional().default({}),
});

const CaptureSessionStatusSchema = z.object({
    session_id: z.string().min(1),
});

const VisualEvidenceAnalyzeSchema = z.object({
    artifact_id: z.string().min(1),
    prompt: z.string().optional(),
    allow_external_model: z.boolean().optional().default(false),
    preferred_provider: z.enum(["openai-responses-vision", "claude-vision", "local-only"]).optional(),
    local_analysis: z.record(z.unknown()).optional().default({}),
    redaction_summary: z.string().optional(),
    principal: z.string().optional().default("mcp-agent"),
    surface: z.string().optional().default("mcp-visual-evidence"),
});

const CaptureReviewCandidateSchema = z.object({
    id: z.string().optional(),
    kind: z.enum(["moment", "decision", "claim_seed", "tension", "next_action"]).default("moment"),
    title: z.string().min(1),
    summary: z.string().min(1),
    evidence_refs: z.array(z.string()).optional().default([]),
    claim_text: z.string().optional(),
    decision_text: z.string().optional(),
    next_action: z.string().optional(),
    epistemic_status: z.enum(["belief", "contest", "knowledge", "robust"]).optional().default("belief"),
    confidence: z.number().min(0).max(1).optional(),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    provenance: z.record(z.unknown()).optional().default({}),
});

const CaptureReviewPromoteSchema = z.object({
    session_id: z.string().optional(),
    artifact_id: z.string().optional(),
    project_slug: z.string().optional().default("sounio"),
    source_surface: z.string().optional().default("mcp-capture-review"),
    candidates: z.array(CaptureReviewCandidateSchema).min(1),
    decision: z.string().optional().default("promote"),
    reviewer: z.string().optional().default("demetrios"),
    promote: z.boolean().optional().default(true),
    privacy_class: PrivacyClassSchema.optional().default("sensitive"),
    provenance: z.record(z.unknown()).optional().default({}),
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
        capture_session_id: input.capture_session_id,
        artifact_refs: input.artifact_refs,
        transcription_segments: input.transcription_segments,
        visual_evidence_refs: input.visual_evidence_refs,
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
        capture_session_id: undefined,
        artifact_refs: [],
        transcription_segments: [],
        visual_evidence_refs: [],
    };
}

const RecallAnswerSchema = z.object({
    query: z.string(),
    scope: z.string().optional(),
    max_items: z.number().int().min(1).max(12).optional(),
});
const ProposeNextSchema = z.object({ scope: z.string().optional() });
const COORD_URL = (process.env.COORD_URL || "http://coord-mcp.beagle.svc.cluster.local:8900").replace(/\/$/, "");

export function exocortexTools(client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_recall_answer",
            description:
                "Composed recall: retrieve project-scoped memory from the exocortex and return a SYNTHESIZED, cited answer (not raw hits). Ask 'what did we decide about X' and get a composed answer (headline + cited bullets) with sources. scope = all|beagle|sounio|darwin.",
            inputSchema: {
                type: "object",
                properties: {
                    query: { type: "string" },
                    scope: { type: "string", description: "project scope: all|beagle|sounio|darwin" },
                    max_items: { type: "number", minimum: 1, maximum: 12, default: 8 },
                },
                required: ["query"],
            },
            handler: async (args: unknown) => {
                const p = RecallAnswerSchema.parse(args ?? {});
                return sanitizeOutput(
                    await client.recallAnswer({ query: p.query, scope: p.scope, max_items: p.max_items ?? 8 }),
                );
            },
        },
        {
            name: "beagle_propose_next",
            description:
                "Ask the fleet to propose the 2-3 MOST VALUABLE next steps from recent decisions + current state in the exocortex (the cognitive loop's planner). Returns titled, cited proposals with effort (S/M/L). PROPOSE only — does not execute. scope = all|beagle|sounio|darwin.",
            inputSchema: {
                type: "object",
                properties: {
                    scope: { type: "string", description: "project scope: all|beagle|sounio|darwin" },
                },
            },
            handler: async (args: unknown) => {
                const p = ProposeNextSchema.parse(args ?? {});
                const r = await fetch(`${COORD_URL}/propose`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ scope: p.scope }),
                    signal: AbortSignal.timeout(60000),
                });
                if (!r.ok) {
                    throw new Error(`coord propose ${r.status}`);
                }
                return sanitizeOutput(await r.json());
            },
        },
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
                    capture_session_id: { type: "string" },
                    artifact_refs: { type: "array", items: { type: "string" } },
                    transcription_segments: {
                        type: "array",
                        items: {
                            type: "object",
                            required: ["text"],
                            properties: {
                                text: { type: "string" },
                                start_ms: { type: "number", minimum: 0 },
                                end_ms: { type: "number", minimum: 0 },
                                confidence: { type: "number", minimum: 0, maximum: 1 },
                                source: { type: "string" },
                            },
                        },
                    },
                    visual_evidence_refs: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const parsed = AssistedImportBatchSchema.parse(args ?? {});
                return sanitizeOutput(await client.assistedImportBatch(parsed));
            },
        },
        {
            name: "beagle_agent_registry",
            description:
                "Read the role-first Sounio/Beagle model ecology registry: Builder, code worker, semanticist, maintainer, platform operator, global reader, audiovisual memory, local sensor, and coding UI.",
            inputSchema: {
                type: "object",
                properties: {
                    project_slug: { type: "string", default: "sounio" },
                },
            },
            handler: async (args: unknown) => {
                const { project_slug } = AgentRegistrySchema.parse(args ?? {});
                return sanitizeOutput(await client.agentRegistry(project_slug));
            },
        },
        {
            name: "beagle_agent_route",
            description:
                "Route a task to a Beagle agent role using deterministic Sounio/Beagle model ecology rules and LC-NE arousal mode.",
            inputSchema: {
                type: "object",
                required: ["task"],
                properties: {
                    project_slug: { type: "string", default: "sounio" },
                    task: { type: "string" },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    arousal_mode: {
                        type: "string",
                        enum: ["phasic_focus", "tonic_explore", "blocked", "recovering", "fatigued"],
                    },
                    fallback_roles: { type: "array", items: { type: "string" } },
                },
            },
            handler: async (args: unknown) => {
                const parsed = AgentRouteSchema.parse(args ?? {});
                const { project_slug, ...body } = parsed;
                return sanitizeOutput(await client.agentRoute(project_slug, body));
            },
        },
        {
            name: "beagle_write_probe",
            description:
                "Diagnose whether a Claude iOS, MCP, Apple, or agent surface has the scopes and core write health needed to create memory.",
            inputSchema: {
                type: "object",
                properties: {
                    principal: { type: "string", default: "mcp-agent" },
                    source_platform: { type: "string", default: "mcp" },
                    source_surface: { type: "string", default: "mcp" },
                    required_scopes: { type: "array", items: { type: "string" }, default: ["memory:write"] },
                    granted_scopes: { type: "array", items: { type: "string" } },
                    payload_kind: { type: "string", default: "memory_write" },
                    metadata: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = WriteProbeSchema.parse(args ?? {});
                return sanitizeOutput(await client.writeProbe(parsed));
            },
        },
        {
            name: "beagle_failed_write_inbox",
            description:
                "List append-only failed-write inbox items awaiting diagnosis or reviewed rescue into cluster-canonical memory.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 100, default: 25 },
                },
            },
            handler: async (args: unknown) => {
                const { limit } = FailedWriteInboxSchema.parse(args ?? {});
                return sanitizeOutput(await client.failedWriteInbox(limit));
            },
        },
        {
            name: "beagle_failed_write_rescue",
            description:
                "Rescue a reviewed failed Claude iOS or agent memory write into GraphRAG++ as sensitive Episode+Atom and conservative SounioMoment/Claim<T> seeds. Restricted payloads remain blocked.",
            inputSchema: {
                type: "object",
                properties: {
                    failed_write_id: { type: "string" },
                    reason: { type: "string", default: "claude_ios_failed_write_rescue" },
                    source_platform: { type: "string", default: "claude" },
                    source_surface: { type: "string", default: "claude-ios" },
                    principal: { type: "string", default: "claude-ios" },
                    summary: { type: "string" },
                    session_id: { type: "string" },
                    project_ref: { type: "string", default: "sounio" },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    payload_kind: { type: "string", default: "sounio_insight" },
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
                    tags: { type: "array", items: { type: "string" } },
                    artifact_refs: { type: "array", items: { type: "string" } },
                    candidate_refs: { type: "array", items: { type: "string" } },
                    metadata: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = FailedWriteRescueSchema.parse(args ?? {});
                return sanitizeOutput(await client.failedWriteRescue(parsed));
            },
        },
        {
            name: "beagle_capture_session_start",
            description:
                "Start an explicit user-visible multimodal capture session for Text, Thinking Aloud voice, or Visual Evidence. Beagle does not perform ambient adtech-style listening.",
            inputSchema: {
                type: "object",
                properties: {
                    project_slug: { type: "string", default: "sounio" },
                    mode: {
                        type: "string",
                        enum: ["text", "thinking_aloud", "visual_evidence", "multimodal"],
                        default: "thinking_aloud",
                    },
                    surface: { type: "string", default: "mcp-capture" },
                    principal: { type: "string", default: "mcp-agent" },
                    title: { type: "string" },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    metadata: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = CaptureSessionStartSchema.parse(args ?? {});
                return sanitizeOutput(await client.captureSessionStart(parsed));
            },
        },
        {
            name: "beagle_capture_session_status",
            description:
                "Read the current status and provenance policy for an explicit multimodal capture session.",
            inputSchema: {
                type: "object",
                required: ["session_id"],
                properties: {
                    session_id: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = CaptureSessionStatusSchema.parse(args ?? {});
                return sanitizeOutput(await client.captureSessionStatus(parsed.session_id));
            },
        },
        {
            name: "beagle_visual_evidence_analyze",
            description:
                "Analyze a private visual evidence artifact into conservative Sounio claim seeds, tensions, missing evidence, and provenance. External vision providers require explicit confirmation.",
            inputSchema: {
                type: "object",
                required: ["artifact_id"],
                properties: {
                    artifact_id: { type: "string" },
                    prompt: { type: "string" },
                    allow_external_model: { type: "boolean", default: false },
                    preferred_provider: {
                        type: "string",
                        enum: ["openai-responses-vision", "claude-vision", "local-only"],
                    },
                    local_analysis: { type: "object", additionalProperties: true },
                    redaction_summary: { type: "string" },
                    principal: { type: "string", default: "mcp-agent" },
                    surface: { type: "string", default: "mcp-visual-evidence" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = VisualEvidenceAnalyzeSchema.parse(args ?? {});
                return sanitizeOutput(await client.visualEvidenceAnalyze(parsed));
            },
        },
        {
            name: "beagle_capture_review_promote",
            description:
                "Review and optionally promote multimodal capture candidates into SounioMoment and Claim<T> seeds. Restricted candidates are not promoted.",
            inputSchema: {
                type: "object",
                required: ["candidates"],
                properties: {
                    session_id: { type: "string" },
                    artifact_id: { type: "string" },
                    project_slug: { type: "string", default: "sounio" },
                    source_surface: { type: "string", default: "mcp-capture-review" },
                    candidates: {
                        type: "array",
                        minItems: 1,
                        items: {
                            type: "object",
                            required: ["title", "summary"],
                            properties: {
                                id: { type: "string" },
                                kind: {
                                    type: "string",
                                    enum: ["moment", "decision", "claim_seed", "tension", "next_action"],
                                    default: "moment",
                                },
                                title: { type: "string" },
                                summary: { type: "string" },
                                evidence_refs: { type: "array", items: { type: "string" } },
                                claim_text: { type: "string" },
                                decision_text: { type: "string" },
                                next_action: { type: "string" },
                                epistemic_status: {
                                    type: "string",
                                    enum: ["belief", "contest", "knowledge", "robust"],
                                    default: "belief",
                                },
                                confidence: { type: "number", minimum: 0, maximum: 1 },
                                privacy_class: {
                                    type: "string",
                                    enum: ["public", "sensitive", "restricted"],
                                    default: "sensitive",
                                },
                                provenance: { type: "object", additionalProperties: true },
                            },
                        },
                    },
                    decision: { type: "string", default: "promote" },
                    reviewer: { type: "string", default: "demetrios" },
                    promote: { type: "boolean", default: true },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    provenance: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = CaptureReviewPromoteSchema.parse(args ?? {});
                const candidates = parsed.candidates.map((candidate, index) => ({
                    ...candidate,
                    id:
                        candidate.id ??
                        `capture-candidate-${crypto
                            .createHash("sha256")
                            .update(`${candidate.title}\n${candidate.summary}\n${index}`)
                            .digest("hex")
                            .slice(0, 16)}`,
                }));
                return sanitizeOutput(
                    await client.captureReviewPromote({
                        ...parsed,
                        candidates,
                    }),
                );
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
                    ranking_policy: {
                        type: "string",
                        enum: ["strict_recent_guarded", "legacy_stable"],
                        description:
                            "Optional retrieval ranking policy. strict_recent_guarded boosts recent work memory while Stable Fact Guard protects canonical facts.",
                    },
                    mode: {
                        type: "string",
                        enum: [
                            "hypermemory_multivector",
                            "hypermemory",
                            "graphsearch-lite",
                            "drift-lite",
                            "local",
                            "global",
                            "hybrid",
                            "adaptive-federation",
                        ],
                        default: "hypermemory_multivector",
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
                    mode: { type: "string", default: "hypermemory_multivector" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryMeshQuerySchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryMeshQuery(parsed));
            },
        },
        {
            name: "beagle_semantic_index_status",
            description:
                "Read the v2.1 native Semantic Truth Backbone status: LanceDB table, row count, MaxSim readiness, Jina-ColBERT-v2 model, fallback model, reranker, freshness, and latest rebuild.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.semanticIndexStatus()),
        },
        {
            name: "beagle_semantic_index_rebuild",
            description:
                "Rebuild the derived v2.1 LanceDB multivector table from the cluster-canonical JSONL export. Restricted records are excluded; JSONL/Merkle/Chronoself remains authoritative.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 50000, default: 10000 },
                    include_candidates: { type: "boolean", default: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SemanticIndexRebuildSchema.parse(args ?? {});
                return sanitizeOutput(await client.semanticIndexRebuild(parsed));
            },
        },
        {
            name: "beagle_retrieval_trace",
            description:
                "Run a HyperMemory multivector query through the memory-engine and return native semantic results, MaxSim/graph/rerank trace, fallback chain, truthset gate, leak check, and provenance.",
            inputSchema: {
                type: "object",
                required: ["query"],
                properties: {
                    query: { type: "string" },
                    scope: { type: "string" },
                    max_items: { type: "number", minimum: 1, maximum: 20, default: 8 },
                    mode: {
                        type: "string",
                        enum: ["hypermemory_multivector", "hypermemory", "graphsearch-lite"],
                        default: "hypermemory_multivector",
                    },
                },
            },
            handler: async (args: unknown) => {
                const parsed = RetrievalTraceSchema.parse(args ?? {});
                const result = await client.memoryMeshQuery(parsed);
                if (typeof result === "object" && result !== null) {
                    const value = result as Record<string, unknown>;
                    const core = (value.core_response ?? {}) as Record<string, unknown>;
                    return sanitizeOutput({
                        summary: core.summary ?? value.summary,
                        mode: value.mode,
                        runtime_used: value.runtime_used,
                        fallback_chain: value.fallback_chain,
                        semantic_trace: value.semantic_trace,
                        semantic_results: value.semantic_results,
                        maxsim_scores: value.maxsim_scores ?? core.maxsim_scores,
                        graph_expansion: value.graph_expansion ?? core.graph_expansion,
                        reranker_scores: value.reranker_scores ?? core.reranker_scores,
                        retrieval_trace: value.retrieval_trace,
                        mesh_trace: value.mesh_trace,
                        truthset_gate_status: value.truthset_gate_status,
                        restricted_leak_check: value.restricted_leak_check,
                        provenance: core.provenance,
                        confidence: core.confidence,
                    });
                }
                return sanitizeOutput(result);
            },
        },
        {
            name: "beagle_retrieval_agent_query",
            description:
                "Run the v2.2 Retrieval Agent over Beagle memory. It chooses a strategy such as episode nucleus expansion, temporal trace, contradiction check, work-memory replay, schema-guided graph, or parallel decomposition, then returns evidence, strategy, context format, runtime trace, provenance, and fallback chain.",
            inputSchema: {
                type: "object",
                required: ["query"],
                properties: {
                    query: { type: "string" },
                    scope: { type: "string" },
                    max_items: { type: "number", minimum: 1, maximum: 20, default: 8 },
                    mode: {
                        type: "string",
                        enum: ["hypermemory_multivector", "hypermemory", "graphsearch-lite"],
                        default: "hypermemory_multivector",
                    },
                    planner_mode: {
                        type: "string",
                        enum: ["deterministic", "hybrid", "llm"],
                        default: "hybrid",
                    },
                    surface: { type: "string", default: "mcp-retrieval-agent" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = RetrievalAgentQuerySchema.parse(args ?? {});
                return sanitizeOutput(await client.retrievalAgentQuery(parsed));
            },
        },
        {
            name: "beagle_retrieval_agent_status",
            description:
                "Read v2.2 Retrieval Agent readiness by combining memory-engine runtime status, semantic index status, and Private MemoryArena gate state.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => {
                const [engine, semantic, memoryarena] = await Promise.allSettled([
                    client.memoryEngineStatus(),
                    client.semanticIndexStatus(),
                    client.memoryArenaStatus(),
                ]);
                return sanitizeOutput({
                    retrieval_agent: process.env.BEAGLE_RETRIEVAL_AGENT || "canary",
                    planner_mode: process.env.BEAGLE_RETRIEVAL_PLANNER || "hybrid",
                    engine: engine.status === "fulfilled" ? engine.value : { error: String(engine.reason) },
                    semantic_index: semantic.status === "fulfilled" ? semantic.value : { error: String(semantic.reason) },
                    memoryarena: memoryarena.status === "fulfilled" ? memoryarena.value : { error: String(memoryarena.reason) },
                    policy: "deterministic policy on hot path; LLM planner only for Memory Lens, Deep, bench, and debug.",
                });
            },
        },
        {
            name: "beagle_context_compile",
            description:
                "Compile an adaptive v2.3 ContextPack for a task or query. The pack preserves episodic envelopes, evidence frontier, procedural hints, contradiction guards, provenance, token budget, policy version, and restricted-leak check without creating canonical memory.",
            inputSchema: {
                type: "object",
                required: ["query"],
                properties: {
                    query: { type: "string" },
                    scope: { type: "string" },
                    surface: { type: "string", default: "mcp-context-compiler" },
                    task: { type: "string" },
                    max_items: { type: "number", minimum: 1, maximum: 20, default: 8 },
                    mode: {
                        type: "string",
                        enum: ["hypermemory_multivector", "hypermemory", "graphsearch-lite"],
                        default: "hypermemory_multivector",
                    },
                    planner_mode: {
                        type: "string",
                        enum: ["deterministic", "hybrid", "llm"],
                        default: "hybrid",
                    },
                    token_budget: { type: "number", minimum: 256, maximum: 64000 },
                    agent: { type: "string" },
                    session_id: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = ContextCompileSchema.parse(args ?? {});
                return sanitizeOutput(await client.contextCompile(parsed));
            },
        },
        {
            name: "beagle_context_pack_get",
            description:
                "Fetch a previously compiled v2.3 ContextPack from the cluster-canonical append-only context pack log.",
            inputSchema: {
                type: "object",
                required: ["context_pack_id"],
                properties: {
                    context_pack_id: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = ContextPackGetSchema.parse(args ?? {});
                return sanitizeOutput(await client.contextPackGet(parsed.context_pack_id));
            },
        },
        {
            name: "beagle_memory_effectiveness_record",
            description:
                "Record whether a ContextPack helped an agent action. This append-only signal trains the v2.3 memory policy learner through offline/bandit evaluation, never through fine-tuning.",
            inputSchema: {
                type: "object",
                required: ["context_pack_id"],
                properties: {
                    context_pack_id: { type: "string" },
                    query: { type: "string" },
                    surface: { type: "string", default: "mcp" },
                    principal: { type: "string", default: "mcp-agent" },
                    session_id: { type: "string" },
                    strategy_used: { type: "string" },
                    tokens_used: { type: "number", minimum: 0 },
                    latency_ms: { type: "number", minimum: 0 },
                    tests: { type: "array", items: { type: "string" } },
                    feedback: { type: "string" },
                    human_correction: { type: "string" },
                    success: { type: "boolean" },
                    outcome: { type: "string", default: "observed" },
                    metadata: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryEffectivenessRecordSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryEffectivenessRecord(parsed));
            },
        },
        {
            name: "beagle_memory_policy_status",
            description:
                "Read the v2.3 Memory Policy Learner status: current policy version, observe/recommend/canary mode, latest evaluation, MemoryArena gate, and promotion requirements.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => {
                const [engine, core] = await Promise.allSettled([
                    client.memoryPolicyStatus(),
                    client.coreMemoryPolicyStatus(),
                ]);
                return sanitizeOutput({
                    engine: engine.status === "fulfilled" ? engine.value : { error: String(engine.reason) },
                    core: core.status === "fulfilled" ? core.value : { error: String(core.reason) },
                });
            },
        },
        {
            name: "beagle_dreamcycle_run",
            description:
                "Run v2.3 DreamCycle consolidation in manual/nightly mode. Output is candidate-only: procedural memories, contradictions, stale beliefs, project summaries, unresolved loops, and truthset suggestions require Governor/Triad before active retrieval.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 5000, default: 500 },
                    mode: { type: "string", enum: ["manual", "nightly"], default: "manual" },
                    triggered_by: { type: "string", default: "mcp-agent" },
                    dry_run: { type: "boolean", default: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = DreamCycleRunSchema.parse(args ?? {});
                return sanitizeOutput(await client.dreamCycleRun(parsed));
            },
        },
        {
            name: "beagle_dreamcycle_status",
            description:
                "Read v2.3 DreamCycle status, latest consolidation run, candidate-only policy, and whether manual/nightly consolidation is configured.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => {
                const [engine, core] = await Promise.allSettled([
                    client.dreamCycleStatus(),
                    client.coreDreamCycleStatus(),
                ]);
                return sanitizeOutput({
                    engine: engine.status === "fulfilled" ? engine.value : { error: String(engine.reason) },
                    core: core.status === "fulfilled" ? core.value : { error: String(core.reason) },
                });
            },
        },
        {
            name: "beagle_sounio_program_check",
            description:
                "Validate a Sounio v0.1 Work IR program before it is compiled into durable Temporal PaperRun execution, Beagle memory projection, ContextPack, audit trace, or paper artifacts.",
            inputSchema: {
                type: "object",
                required: ["program"],
                properties: {
                    source_format: { type: "string", enum: ["json", "yaml", "sio"], default: "json" },
                    program: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioProgramCheckSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioProgramCheck(parsed));
            },
        },
        {
            name: "beagle_sounio_claim_check",
            description:
                "Validate a Sounio Claim<T> without writing it. Sounio types the claim as Belief, Contest, Knowledge, or Robust using evidence, provenance, confidence, review state, and publication-readiness gates.",
            inputSchema: {
                type: "object",
                required: ["claim"],
                properties: {
                    claim: {
                        type: "object",
                        required: ["claim_text"],
                        properties: {
                            id: { type: "string" },
                            claim_text: { type: "string" },
                            subject: { type: "string" },
                            value_type: { type: "string", default: "Claim<T>" },
                            epistemic_status: {
                                type: "string",
                                enum: ["belief", "contest", "knowledge", "robust"],
                                default: "belief",
                            },
                            evidence_refs: { type: "array", items: { type: "string" }, default: [] },
                            provenance: { type: "object", additionalProperties: true },
                            confidence: { type: "number", minimum: 0, maximum: 1 },
                            contestation: { type: "object", additionalProperties: true },
                            review_state: { type: "string", default: "unreviewed" },
                            promotion_rule: { type: "string" },
                            publication_readiness: { type: "string", default: "not_ready" },
                            section_id: { type: "string" },
                            agent_refs: { type: "array", items: { type: "string" }, default: [] },
                            contract_refs: { type: "array", items: { type: "string" }, default: [] },
                            artifact_refs: { type: "array", items: { type: "string" }, default: [] },
                            chronoself_commit_refs: { type: "array", items: { type: "string" }, default: [] },
                            privacy_class: {
                                type: "string",
                                enum: ["public", "sensitive", "restricted"],
                                default: "sensitive",
                            },
                            rationale: { type: "string" },
                        },
                    },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioClaimCheckSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioClaimCheck(parsed));
            },
        },
        {
            name: "beagle_sounio_moment_type",
            description:
                "Append an ambient SounioMoment derived from visible work, Apple capture, Watch microintention, Codex/Claude Code work memory, or agent conversation. Claims remain conservative seeds (Belief/Contest) until evidence and review promote them.",
            inputSchema: {
                type: "object",
                properties: {
                    source_event_refs: { type: "array", items: { type: "string" }, default: [] },
                    source_platform: { type: "string", default: "mcp-agent" },
                    source_surface: { type: "string", default: "mcp-sounio-moment" },
                    project_slug: { type: "string", default: "sounio" },
                    session_id: { type: "string" },
                    intent_text: { type: "string" },
                    summary: { type: "string" },
                    evidence_refs: { type: "array", items: { type: "string" }, default: [] },
                    claim_seeds: { type: "array", items: { type: "object", additionalProperties: true }, default: [] },
                    decision_seeds: { type: "array", items: { type: "string" }, default: [] },
                    next_action: { type: "string" },
                    privacy_class: {
                        type: "string",
                        enum: ["public", "sensitive", "restricted"],
                        default: "sensitive",
                    },
                    review_state: { type: "string", default: "unreviewed" },
                    provenance: { type: "object", additionalProperties: true },
                    tags: { type: "array", items: { type: "string" }, default: ["sounio", "ambient-typing"] },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioMomentTypeSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioMomentType(parsed));
            },
        },
        {
            name: "beagle_sounio_workday_status",
            description:
                "Read the current Sounio Workday snapshot: recent moments, decisions, Claim<T> seeds, tensions, agents involved, evidence references, review queue, and next gesture.",
            inputSchema: {
                type: "object",
                properties: {
                    project_slug: { type: "string", default: "sounio" },
                    limit: { type: "number", minimum: 1, maximum: 100, default: 20 },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioWorkdayStatusSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioWorkdayStatus(parsed.project_slug, parsed.limit));
            },
        },
        {
            name: "beagle_sounio_moment_review",
            description:
                "Review a SounioMoment from the ambient workday. This can approve, reject, request revision, mark contestation, or mark a claim seed for later promotion; it never performs destructive actions.",
            inputSchema: {
                type: "object",
                required: ["moment_id", "decision"],
                properties: {
                    moment_id: { type: "string" },
                    reviewer: { type: "string", default: "demetrios" },
                    decision: {
                        type: "string",
                        enum: ["approved", "rejected", "needs_revision", "mark_contest", "promote_claim_seed"],
                    },
                    rationale: { type: "string" },
                    evidence_refs: { type: "array", items: { type: "string" }, default: [] },
                    review_state: { type: "string" },
                    provenance: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioMomentReviewSchema.parse(args ?? {});
                const { moment_id, ...body } = parsed;
                return sanitizeOutput(await client.sounioMomentReview(moment_id, body));
            },
        },
        {
            name: "beagle_sounio_paperrun_start",
            description:
                "Start the v2.4 Sounio PaperRun for the Beagle self-writing systems paper. It creates a durable Temporal workflow request, ContextPack, trace event, memory event, and claim registry without submitting anything externally.",
            inputSchema: {
                type: "object",
                properties: {
                    paper_id: { type: "string" },
                    title: { type: "string" },
                    principal: { type: "string", default: "mcp-agent" },
                    surface: { type: "string", default: "mcp-sounio-paperrun" },
                    temporal_namespace: { type: "string" },
                    temporal_task_queue: { type: "string" },
                    program: { type: "object", additionalProperties: true },
                    dry_run: { type: "boolean", default: false },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioPaperRunStartSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioPaperRunStart(parsed));
            },
        },
        {
            name: "beagle_sounio_paperrun_status",
            description:
                "Read a Sounio PaperRun status by ID, including Temporal workflow ID, approval state, section status, claim registry, citation registry, and artifact references.",
            inputSchema: {
                type: "object",
                required: ["paper_run_id"],
                properties: {
                    paper_run_id: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioPaperRunStatusSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioPaperRunStatus(parsed.paper_run_id));
            },
        },
        {
            name: "beagle_sounio_paperrun_approve_step",
            description:
                "Record the human approval, rejection, or revision request for one Sounio PaperRun step. This only signals/records the durable workflow state; it performs no external publication.",
            inputSchema: {
                type: "object",
                required: ["paper_run_id", "step_id"],
                properties: {
                    paper_run_id: { type: "string" },
                    step_id: { type: "string" },
                    reviewer: { type: "string", default: "demetrios" },
                    decision: {
                        type: "string",
                        enum: ["approved", "rejected", "needs_revision"],
                        default: "approved",
                    },
                    rationale: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioPaperRunApproveStepSchema.parse(args ?? {});
                const { paper_run_id, ...body } = parsed;
                return sanitizeOutput(await client.sounioPaperRunApproveStep(paper_run_id, body));
            },
        },
        {
            name: "beagle_sounio_paperrun_add_claim",
            description:
                "Append a Sounio Claim<T> to a PaperRun's epistemic claim graph. This records provenance, memory, trace, and audit metadata but never publishes or performs destructive actions.",
            inputSchema: {
                type: "object",
                required: ["paper_run_id", "claim"],
                properties: {
                    paper_run_id: { type: "string" },
                    claim: { type: "object", additionalProperties: true },
                    principal: { type: "string", default: "mcp-agent" },
                    surface: { type: "string", default: "mcp-sounio-theatre" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioPaperRunAddClaimSchema.parse(args ?? {});
                const { paper_run_id, ...body } = parsed;
                return sanitizeOutput(await client.sounioPaperRunAddClaim(paper_run_id, body));
            },
        },
        {
            name: "beagle_sounio_claim_review",
            description:
                "Review or promote a Sounio Claim<T> inside a PaperRun. Knowledge<T> requires evidence plus provenance; Robust<T> requires independent verification or replication provenance.",
            inputSchema: {
                type: "object",
                required: ["paper_run_id", "claim_id", "decision"],
                properties: {
                    paper_run_id: { type: "string" },
                    claim_id: { type: "string" },
                    reviewer: { type: "string", default: "demetrios" },
                    decision: {
                        type: "string",
                        enum: [
                            "approved",
                            "rejected",
                            "needs_evidence",
                            "contest",
                            "promote_to_knowledge",
                            "promote_to_robust",
                        ],
                        default: "approved",
                    },
                    rationale: { type: "string" },
                    evidence_refs: { type: "array", items: { type: "string" }, default: [] },
                    epistemic_status: { type: "string", enum: ["belief", "contest", "knowledge", "robust"] },
                    publication_readiness: { type: "string" },
                    provenance: { type: "object", additionalProperties: true },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioClaimReviewSchema.parse(args ?? {});
                const { paper_run_id, claim_id, ...body } = parsed;
                return sanitizeOutput(await client.sounioClaimReview(paper_run_id, claim_id, body));
            },
        },
        {
            name: "beagle_sounio_paperrun_theatre",
            description:
                "Read the PaperRun Theatre snapshot: manuscript, epistemic claim graph, evidence table, agent contributions, approvals, Sounio score, public/private trace boundaries, and next human action.",
            inputSchema: {
                type: "object",
                required: ["paper_run_id"],
                properties: {
                    paper_run_id: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioPaperRunTheatreSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioPaperRunTheatre(parsed.paper_run_id));
            },
        },
        {
            name: "beagle_sounio_public_digest",
            description:
                "Generate and read the sanitized public digest for a PaperRun, including public claims, Sedenion SSM demonstration summary, disclosure, and explicit exclusion of private/restricted traces.",
            inputSchema: {
                type: "object",
                required: ["paper_run_id"],
                properties: {
                    paper_run_id: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioPublicDigestSchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioPaperRunPublicDigest(parsed.paper_run_id));
            },
        },
        {
            name: "beagle_sounio_trace_query",
            description:
                "Read Sounio PaperRun trace events for the self-writing Beagle paper: workflow starts, ContextPacks, claim checks, approvals, artifacts, and memory/audit links.",
            inputSchema: {
                type: "object",
                properties: {
                    paper_run_id: { type: "string" },
                    limit: { type: "number", minimum: 1, maximum: 500, default: 50 },
                },
            },
            handler: async (args: unknown) => {
                const parsed = SounioTraceQuerySchema.parse(args ?? {});
                return sanitizeOutput(await client.sounioTraceQuery(parsed.paper_run_id, parsed.limit));
            },
        },
        {
            name: "beagle_memoryarena_benchmark_run",
            description:
                "Start a private cluster-only MemoryArena-style benchmark for multi-session memory-action loops. It compares v2.2 Retrieval Agent against the v2.1 HyperMemory multivector baseline without exporting private corpus.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 10000, default: 2000 },
                    truthset_id: { type: "string" },
                    domains: { type: "array", items: { type: "string" } },
                    planner_mode: {
                        type: "string",
                        enum: ["deterministic", "hybrid", "llm"],
                        default: "hybrid",
                    },
                    baseline_mode: { type: "string", default: "hypermemory_multivector-v2.1" },
                    candidate_mode: { type: "string", default: "retrieval-agent-v2.2" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryArenaBenchmarkRunSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryArenaRun(parsed));
            },
        },
        {
            name: "beagle_memoryarena_benchmark_status",
            description:
                "Read the latest Private MemoryArena gate for Retrieval Agent promotion: score delta, hard gates, consecutive passing runs, and regression state.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.memoryArenaStatus()),
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
            name: "beagle_memory_benchmark_run",
            description:
                "Start a cluster-only Memory Bench v1.9 run against an approved private truthset, comparing GraphRAG++ baseline, HyperMemory, and federated mesh modes with hard gates for provenance and restricted leakage.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 10000, default: 2000 },
                    domains: { type: "array", items: { type: "string" } },
                    judge_mode: { type: "string" },
                    include_mesh: { type: "boolean", default: true },
                    truthset_id: { type: "string" },
                    baseline_mode: { type: "string", default: "graphsearch-lite" },
                    candidate_modes: {
                        type: "array",
                        items: { type: "string" },
                        default: ["hypermemory_multivector", "hypermemory"],
                    },
                    promotion_policy: {
                        type: "object",
                        additionalProperties: false,
                        properties: {
                            required_margin: { type: "number", minimum: 0, maximum: 1, default: 0.05 },
                            required_consecutive_runs: {
                                type: "number",
                                minimum: 1,
                                maximum: 10,
                                default: 3,
                            },
                        },
                    },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryBenchmarkRunSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryBenchmarkRun(parsed));
            },
        },
        {
            name: "beagle_memory_benchmark_status",
            description:
                "Read the latest Memory Bench v1.9 truthset gate, scores, hard gates, evaluated retrieval modes, and regression count.",
            inputSchema: { type: "object", properties: {} },
            handler: async () => sanitizeOutput(await client.memoryBenchmarkStatus()),
        },
        {
            name: "beagle_memory_truthset_draft",
            description:
                "Draft a private, cluster-only Memory Truth Set from sanitized Beagle memory signals. The draft requires user review before benchmark authority.",
            inputSchema: {
                type: "object",
                properties: {
                    limit: { type: "number", minimum: 1, maximum: 10000, default: 2000 },
                    domains: { type: "array", items: { type: "string" } },
                    title: { type: "string" },
                    description: { type: "string" },
                    source_refs: { type: "array", items: { type: "string" } },
                    reviewer: { type: "string", default: "mcp-agent" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryTruthsetDraftSchema.parse(args ?? {});
                return sanitizeOutput(await client.memoryTruthsetDraft(parsed));
            },
        },
        {
            name: "beagle_memory_truthset_review",
            description:
                "Approve or reject a private Memory Truth Set after human review. Approved truthsets can drive v1.9 Memory Bench gates.",
            inputSchema: {
                type: "object",
                required: ["truthset_id"],
                properties: {
                    truthset_id: { type: "string" },
                    status: {
                        type: "string",
                        enum: ["draft", "provisional_approved", "approved", "rejected"],
                        default: "approved",
                    },
                    reviewer: { type: "string", default: "mcp-agent" },
                    rationale: { type: "string" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = MemoryTruthsetReviewSchema.parse(args ?? {});
                const { truthset_id, ...body } = parsed;
                return sanitizeOutput(await client.memoryTruthsetReview(truthset_id, body));
            },
        },
        {
            name: "beagle_agent_observer_status",
            description:
                "Read Home trust fields that show whether Codex/Claude Code project-file work memory and Apple capture loops have been observed by the cluster.",
            inputSchema: {
                type: "object",
                properties: {
                    platform: { type: "string", default: "mcp-agent-observer" },
                },
            },
            handler: async (args: unknown) => {
                const parsed = AgentObserverStatusSchema.parse(args ?? {});
                const home = await client.exocortexHome(undefined, parsed.platform);
                if (typeof home === "object" && home !== null && "trust_context" in home) {
                    return sanitizeOutput({
                        generated_at: (home as { generated_at?: unknown }).generated_at,
                        trust_context: (home as { trust_context?: unknown }).trust_context,
                        agent_context: (home as { agent_context?: unknown }).agent_context,
                    });
                }
                return sanitizeOutput(home);
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
