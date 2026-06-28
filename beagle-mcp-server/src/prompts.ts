/**
 * MCP prompts.
 *
 * Prompts are intentionally operational: they teach external agents how to use
 * Beagle as an exocortex, not as a generic chatbot endpoint.
 */

export interface McpPromptArgument {
    name: string;
    description: string;
    required?: boolean;
}

export interface McpPromptMessage {
    role: "user" | "assistant";
    content: {
        type: "text";
        text: string;
    };
}

export interface McpPromptDef {
    name: string;
    description: string;
    arguments?: McpPromptArgument[];
    get: (args: Record<string, string | undefined>) => Promise<{
        description: string;
        messages: McpPromptMessage[];
    }>;
}

function message(text: string): McpPromptMessage {
    return {
        role: "user",
        content: {
            type: "text",
            text,
        },
    };
}

export function definePrompts(): McpPromptDef[] {
    return [
        {
            name: "exocortex_daily_brief",
            description:
                "Generate a daily operational brief from Beagle Home, Chronoself, memory, body context, and active projects.",
            arguments: [
                {
                    name: "focus",
                    description: "Optional focus area for the brief.",
                    required: false,
                },
            ],
            get: async ({ focus }) => ({
                description: "Daily Exocortex brief",
                messages: [
                    message(`Use beagle_exocortex_home plus relevant resources to produce a concise daily brief.

Focus: ${focus || "current self, active project, body context, open loops, and next action"}

Rules:
- Distinguish observed facts, remembered context, and inference.
- Prefer one clear next action over a dashboard dump.
- If the cluster truth is degraded, say what is reliable and what is not.`),
                ],
            }),
        },
        {
            name: "import_conversation",
            description:
                "Import a conversation transcript into OmniMemory and, when appropriate, create Chronoself commits.",
            arguments: [
                {
                    name: "source_platform",
                    description: "chatgpt, claude, grok, gemini, or manual.",
                    required: true,
                },
                {
                    name: "project",
                    description: "Optional project slug/tag.",
                    required: false,
                },
            ],
            get: async ({ source_platform, project }) => ({
                description: "Conversation import workflow",
                messages: [
                    message(`Import the provided transcript with beagle_assisted_import_batch, not as a loose transcript.

source_platform: ${source_platform || "manual"}
project: ${project || "unspecified"}

Defaults:
- privacy_class: sensitive
- import_scope: user_supplied_export when the transcript is an export
- import_scope: current_conversation when only visible context is available
- restricted content must be skipped unless the user explicitly approves a later review workflow

Extract:
- key insights
- decisions
- hypotheses
- belief changes
- unresolved questions
- projects mentioned

Then run beagle_memory_project_graph for the new source_ref when needed and create a Chronoself commit when the transcript changes priorities, self-model, research direction, or project commitments.`),
                ],
            }),
        },
        {
            name: "import_visible_project",
            description:
                "Capture the currently visible project context as GraphRAG++ memory without requiring a full account export.",
            arguments: [
                {
                    name: "source_platform",
                    description: "claude, chatgpt, grok, gemini, codex, or manual.",
                    required: true,
                },
                {
                    name: "project",
                    description: "Project slug, title, or stable reference.",
                    required: true,
                },
                {
                    name: "session_id",
                    description: "Stable session or thread identifier for this import batch.",
                    required: true,
                },
            ],
            get: async ({ source_platform, project, session_id }) => ({
                description: "Visible project import workflow",
                messages: [
                    message(`Use beagle_assisted_import_batch to capture only the project context visible in this client.

source_platform: ${source_platform || "manual"}
project_ref: ${project || "<project>"}
session_id: ${session_id || "<session_id>"}
import_scope: visible_project
privacy_class: sensitive

Capture:
- decisions and priority changes
- hypotheses and open questions
- project entities and relationships
- next actions with provenance

After import, query beagle://memory/graph/status or run beagle_memory_query to confirm the projected atoms are retrievable.`),
                ],
            }),
        },
        {
            name: "round_table",
            description:
                "Convoke Beagle Round Table voices and synthesize disagreements into action.",
            arguments: [
                {
                    name: "problem",
                    description: "Problem or decision to deliberate.",
                    required: true,
                },
            ],
            get: async ({ problem }) => ({
                description: "Round Table deliberation",
                messages: [
                    message(`Use beagle_round_table for this problem:

${problem || "<problem>"}

Then synthesize:
- strongest convergence
- strongest dissent
- hidden assumption
- confidence
- recommended action

Do not turn agents into theater; use the voices only to improve the decision.`),
                ],
            }),
        },
        {
            name: "temporal_self_analysis",
            description:
                "Run TemporalAI over a theme and map changes in self, projects, and decisions.",
            arguments: [
                {
                    name: "topic",
                    description: "Theme to analyze longitudinally.",
                    required: true,
                },
                {
                    name: "days_back",
                    description: "Number of days to include.",
                    required: false,
                },
            ],
            get: async ({ topic, days_back }) => ({
                description: "Temporal self analysis",
                messages: [
                    message(`Run beagle_temporal_analyze with:
- topic: ${topic || "<topic>"}
- days_back: ${days_back || "90"}

Then explain:
- phases
- turning points
- recurring patterns
- plausible causal hypothesis
- next Chronoself commit that would improve continuity.`),
                ],
            }),
        },
        {
            name: "deep_research",
            description:
                "Use Go Deeper for rigorous research with sources, uncertainty, and next steps.",
            arguments: [
                {
                    name: "question",
                    description: "Research question.",
                    required: true,
                },
            ],
            get: async ({ question }) => ({
                description: "Deep research workflow",
                messages: [
                    message(`Use beagle_go_deeper with modality=deep_research for:

${question || "<question>"}

Your synthesis must separate:
- what is known
- what is uncertain
- strongest evidence
- weak inference
- implications for Beagle projects
- next experiment or search.`),
                ],
            }),
        },
        {
            name: "veritas_review",
            description:
                "Review Beagle work for correctness risks, maintenance risks, and philosophical drift.",
            arguments: [
                {
                    name: "artifact",
                    description: "Code, plan, output, or design to review.",
                    required: true,
                },
            ],
            get: async ({ artifact }) => ({
                description: "Veritas review",
                messages: [
                    message(`Review this artifact through Beagle's Veritas lens:

${artifact || "<artifact>"}

Prioritize:
- correctness and data-contract risks
- maintenance risks
- security/auth scope risks
- loss of cluster truth
- places where the product drifts into chatbot/dashboard/gimmick

Return findings first, then practical fixes.`),
                ],
            }),
        },
    ];
}
