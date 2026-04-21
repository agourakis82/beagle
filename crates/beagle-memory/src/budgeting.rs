use serde::{Deserialize, Serialize};

pub const CONTEXT_BUDGET_PROFILE_VERSION: &str = "beagle-context-budget-profile-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ContextBudgetAllocation {
    pub source_kind: String,
    pub max_items: usize,
    pub budget_weight: f32,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ContextBudgetProfile {
    pub profile_version: String,
    pub profile_id: String,
    pub task_profile: String,
    pub default_tool_id: String,
    pub retrieval_query_type: String,
    pub graphrag_query_mode_hint: String,
    pub temporal_truth_view: String,
    pub include_temporal_contradictions: bool,
    pub selected_memory_tiers: Vec<String>,
    pub max_context_items: usize,
    pub allocations: Vec<ContextBudgetAllocation>,
    pub note: String,
}

pub fn supported_task_profiles() -> Vec<&'static str> {
    vec!["implementation", "analysis", "interactive-editing", "manuscript"]
}

pub fn context_budget_profile(task_profile: &str) -> Option<ContextBudgetProfile> {
    let normalized = normalize_task_profile(task_profile);
    match normalized.as_str() {
        "implementation" => Some(ContextBudgetProfile {
            profile_version: CONTEXT_BUDGET_PROFILE_VERSION.to_string(),
            profile_id: "b235-budget-implementation".to_string(),
            task_profile: normalized,
            default_tool_id: "codex".to_string(),
            retrieval_query_type: "code".to_string(),
            graphrag_query_mode_hint: "local".to_string(),
            temporal_truth_view: "current".to_string(),
            include_temporal_contradictions: true,
            selected_memory_tiers: vec![
                "procedural".to_string(),
                "semantic".to_string(),
                "episodic".to_string(),
            ],
            max_context_items: 8,
            allocations: vec![
                ContextBudgetAllocation {
                    source_kind: "procedural".to_string(),
                    max_items: 3,
                    budget_weight: 0.38,
                    note: "Implementation prefers procedural memory first so repo-native actions and workflows stay near the top.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "semantic".to_string(),
                    max_items: 2,
                    budget_weight: 0.25,
                    note: "Semantic memory keeps the why behind the change close to the implementation lane.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "episodic".to_string(),
                    max_items: 1,
                    budget_weight: 0.12,
                    note: "A bounded episodic slice preserves the most relevant recent operator context.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "temporal".to_string(),
                    max_items: 1,
                    budget_weight: 0.12,
                    note: "Implementation keeps only the current bounded truth slice so procedural work stays aligned to the latest valid state without losing contradiction awareness.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "graphrag".to_string(),
                    max_items: 1,
                    budget_weight: 0.13,
                    note: "A single bounded graph slice keeps implementation tethered to the canonical Beagle object neighborhood.".to_string(),
                },
            ],
            note: "B23.5 keeps the implementation lane procedural-first, code-routed, locally scoped, and current-truth aware.".to_string(),
        }),
        "interactive-editing" => Some(ContextBudgetProfile {
            profile_version: CONTEXT_BUDGET_PROFILE_VERSION.to_string(),
            profile_id: "b235-budget-interactive-editing".to_string(),
            task_profile: normalized,
            default_tool_id: "cursor".to_string(),
            retrieval_query_type: "code".to_string(),
            graphrag_query_mode_hint: "local".to_string(),
            temporal_truth_view: "current".to_string(),
            include_temporal_contradictions: false,
            selected_memory_tiers: vec![
                "procedural".to_string(),
                "episodic".to_string(),
                "semantic".to_string(),
            ],
            max_context_items: 7,
            allocations: vec![
                ContextBudgetAllocation {
                    source_kind: "procedural".to_string(),
                    max_items: 2,
                    budget_weight: 0.29,
                    note: "Interactive editing keeps folder-entry and workflow hints dominant.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "episodic".to_string(),
                    max_items: 2,
                    budget_weight: 0.29,
                    note: "Cursor benefits from recent session-local edits and handoff residue.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "semantic".to_string(),
                    max_items: 1,
                    budget_weight: 0.14,
                    note: "A narrow semantic slice keeps the editor aligned with current intent.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "temporal".to_string(),
                    max_items: 1,
                    budget_weight: 0.14,
                    note: "Interactive editing only carries the current temporal truth slice so the editor is not overloaded with historical branches.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "graphrag".to_string(),
                    max_items: 1,
                    budget_weight: 0.14,
                    note: "A bounded graph slice keeps interactive editing tied to nearby canonical objects.".to_string(),
                },
            ],
            note: "B23.5 keeps the interactive editor lane code-routed, tightly local, and current-truth bounded.".to_string(),
        }),
        "manuscript" => Some(ContextBudgetProfile {
            profile_version: CONTEXT_BUDGET_PROFILE_VERSION.to_string(),
            profile_id: "b235-budget-manuscript".to_string(),
            task_profile: normalized,
            default_tool_id: "claude-code".to_string(),
            retrieval_query_type: "general".to_string(),
            graphrag_query_mode_hint: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            include_temporal_contradictions: true,
            selected_memory_tiers: vec![
                "semantic".to_string(),
                "episodic".to_string(),
                "procedural".to_string(),
            ],
            max_context_items: 10,
            allocations: vec![
                ContextBudgetAllocation {
                    source_kind: "semantic".to_string(),
                    max_items: 4,
                    budget_weight: 0.40,
                    note: "Manuscript compilation is semantic-first so claims, evidence, and supportable narrative stay dominant.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "episodic".to_string(),
                    max_items: 1,
                    budget_weight: 0.10,
                    note: "Recent bounded editorial and experiment handoffs remain visible without overwhelming the manuscript lane.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "procedural".to_string(),
                    max_items: 1,
                    budget_weight: 0.10,
                    note: "A small procedural slice keeps the subagent aware of the current editorial workflow.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "temporal".to_string(),
                    max_items: 2,
                    budget_weight: 0.20,
                    note: "Manuscript work keeps current and historical truth visible so claims and contradictions stay explicit rather than implied.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "graphrag".to_string(),
                    max_items: 2,
                    budget_weight: 0.20,
                    note: "Manuscript work benefits from a broader graph view across campaign, result, claim, and manuscript objects.".to_string(),
                },
            ],
            note: "B23.5 keeps manuscript compilation semantic-heavy, globally scoped, and explicit about current versus historical truth.".to_string(),
        }),
        "analysis" => Some(ContextBudgetProfile {
            profile_version: CONTEXT_BUDGET_PROFILE_VERSION.to_string(),
            profile_id: "b235-budget-analysis".to_string(),
            task_profile: normalized,
            default_tool_id: "claude-code".to_string(),
            retrieval_query_type: "general".to_string(),
            graphrag_query_mode_hint: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            include_temporal_contradictions: true,
            selected_memory_tiers: vec![
                "semantic".to_string(),
                "episodic".to_string(),
                "procedural".to_string(),
            ],
            max_context_items: 9,
            allocations: vec![
                ContextBudgetAllocation {
                    source_kind: "semantic".to_string(),
                    max_items: 3,
                    budget_weight: 0.33,
                    note: "Analysis prefers semantic memory so campaign/workstream meaning comes before local execution detail.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "episodic".to_string(),
                    max_items: 1,
                    budget_weight: 0.11,
                    note: "Recent bounded session history helps explain why the current state exists.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "procedural".to_string(),
                    max_items: 1,
                    budget_weight: 0.11,
                    note: "A narrow procedural slice preserves practical next-step hints for the analyst.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "temporal".to_string(),
                    max_items: 2,
                    budget_weight: 0.22,
                    note: "Analysis keeps both current and historical truth visible so drift and contradiction remain auditable.".to_string(),
                },
                ContextBudgetAllocation {
                    source_kind: "graphrag".to_string(),
                    max_items: 2,
                    budget_weight: 0.23,
                    note: "Analysis keeps a broader graph slice because cross-object relationships matter more than local execution detail.".to_string(),
                },
            ],
            note: "B23.5 makes the analysis lane semantic-first, globally scoped, and explicitly contradiction-aware.".to_string(),
        }),
        _ => None,
    }
}

pub fn compiler_policy_variants(task_profile: &str) -> Option<Vec<ContextBudgetProfile>> {
    let normalized = normalize_task_profile(task_profile);
    let canonical = context_budget_profile(&normalized)?;
    let variants = match normalized.as_str() {
        "implementation" => vec![
            canonical.clone(),
            variant_profile(
                &canonical,
                "b236-eval-implementation-both-global",
                "global",
                "both",
                true,
                &["semantic", "procedural", "episodic"],
                8,
                vec![
                    allocation(
                        "semantic",
                        3,
                        0.34,
                        "Eval variant tests whether broader semantic rationale helps implementation more than the canonical procedural-first policy.",
                    ),
                    allocation(
                        "procedural",
                        2,
                        0.24,
                        "Procedural memory remains present but is no longer dominant in this evaluation variant.",
                    ),
                    allocation(
                        "episodic",
                        1,
                        0.12,
                        "A bounded episodic slice is retained for local operator residue.",
                    ),
                    allocation(
                        "temporal",
                        1,
                        0.15,
                        "This variant tests whether carrying both current and historical truth helps implementation despite the extra context cost.",
                    ),
                    allocation(
                        "graphrag",
                        1,
                        0.15,
                        "A broader graph scope is evaluated to see if implementation benefits from more global object context.",
                    ),
                ],
                "B23.6 eval variant broadens implementation toward both-truth and global graph scope so the harness can test whether the canonical local/current procedural-first policy should remain dominant.",
            ),
        ],
        "analysis" => vec![
            canonical.clone(),
            variant_profile(
                &canonical,
                "b236-eval-analysis-current-local",
                "local",
                "current",
                false,
                &["semantic", "procedural", "episodic"],
                7,
                vec![
                    allocation(
                        "semantic",
                        2,
                        0.31,
                        "This variant trims semantic breadth to test whether tighter local context is enough for analysis work.",
                    ),
                    allocation(
                        "procedural",
                        1,
                        0.14,
                        "A small procedural slice remains available for analyst next steps.",
                    ),
                    allocation(
                        "episodic",
                        1,
                        0.15,
                        "Recent session context stays visible in a bounded way.",
                    ),
                    allocation(
                        "temporal",
                        1,
                        0.18,
                        "This variant tests whether current truth alone is sufficient for analysis.",
                    ),
                    allocation(
                        "graphrag",
                        1,
                        0.22,
                        "This variant evaluates whether local graph scope can replace the canonical broader global view.",
                    ),
                ],
                "B23.6 eval variant compresses analysis toward current/local context so the harness can measure whether the canonical global/both-truth policy is justified.",
            ),
            variant_profile(
                &canonical,
                "b236-eval-analysis-both-drift",
                "drift",
                "both",
                true,
                &["semantic", "episodic", "procedural"],
                9,
                vec![
                    allocation(
                        "semantic",
                        2,
                        0.27,
                        "Semantic memory stays dominant while leaving more budget for temporal and graph drift signals.",
                    ),
                    allocation(
                        "episodic",
                        1,
                        0.11,
                        "A bounded episodic slice remains visible.",
                    ),
                    allocation(
                        "procedural",
                        1,
                        0.10,
                        "Procedural hints remain narrow in the drift variant.",
                    ),
                    allocation(
                        "temporal",
                        2,
                        0.25,
                        "This variant favors both-truth temporal context to test contradiction-heavy analysis.",
                    ),
                    allocation(
                        "graphrag",
                        3,
                        0.27,
                        "This variant gives more budget to graph drift so the harness can evaluate when drift mode should beat canonical global mode.",
                    ),
                ],
                "B23.6 eval variant pushes analysis into drift mode so the harness can measure when broader temporal and graph divergence is worth the extra budget.",
            ),
        ],
        "manuscript" => vec![
            canonical.clone(),
            variant_profile(
                &canonical,
                "b236-eval-manuscript-current-local",
                "local",
                "current",
                true,
                &["semantic", "procedural", "episodic"],
                8,
                vec![
                    allocation(
                        "semantic",
                        3,
                        0.39,
                        "Semantic memory stays dominant but the total context is narrowed to test a tighter editorial lane.",
                    ),
                    allocation(
                        "procedural",
                        1,
                        0.11,
                        "Procedural memory remains available for editorial workflow coordination.",
                    ),
                    allocation(
                        "episodic",
                        1,
                        0.10,
                        "A bounded episodic slice preserves recent handoffs.",
                    ),
                    allocation(
                        "temporal",
                        1,
                        0.18,
                        "This variant tests whether manuscript work can stay current-truth only without losing needed historical context.",
                    ),
                    allocation(
                        "graphrag",
                        2,
                        0.22,
                        "This variant narrows graph scope to local so the harness can compare against the canonical global editorial view.",
                    ),
                ],
                "B23.6 eval variant narrows manuscript compilation toward current/local context so the harness can verify that the canonical both-truth global policy is actually earning its budget.",
            ),
        ],
        "interactive-editing" => vec![
            canonical.clone(),
            variant_profile(
                &canonical,
                "b236-eval-interactive-editing-both-drift",
                "drift",
                "both",
                true,
                &["episodic", "procedural", "semantic"],
                8,
                vec![
                    allocation(
                        "episodic",
                        2,
                        0.25,
                        "This variant tests whether interactive editing benefits from more recent session-local residue.",
                    ),
                    allocation(
                        "procedural",
                        2,
                        0.25,
                        "Procedural hints stay strong for editing tasks.",
                    ),
                    allocation(
                        "semantic",
                        1,
                        0.12,
                        "A narrow semantic slice remains available.",
                    ),
                    allocation(
                        "temporal",
                        1,
                        0.18,
                        "This variant tests whether both-truth temporal context helps interactive editing enough to justify the extra weight.",
                    ),
                    allocation(
                        "graphrag",
                        2,
                        0.20,
                        "This variant exercises drift mode to see whether interactive editing benefits from slightly broader graph context.",
                    ),
                ],
                "B23.6 eval variant probes whether interactive editing should stay tightly local/current or occasionally use a broader both-truth drift context.",
            ),
        ],
        _ => return None,
    };

    Some(variants)
}

pub fn normalize_task_profile(task_profile: &str) -> String {
    task_profile.trim().to_ascii_lowercase()
}

fn allocation(
    source_kind: &str,
    max_items: usize,
    budget_weight: f32,
    note: &str,
) -> ContextBudgetAllocation {
    ContextBudgetAllocation {
        source_kind: source_kind.to_string(),
        max_items,
        budget_weight,
        note: note.to_string(),
    }
}

fn variant_profile(
    canonical: &ContextBudgetProfile,
    profile_id: &str,
    graphrag_query_mode_hint: &str,
    temporal_truth_view: &str,
    include_temporal_contradictions: bool,
    selected_memory_tiers: &[&str],
    max_context_items: usize,
    allocations: Vec<ContextBudgetAllocation>,
    note: &str,
) -> ContextBudgetProfile {
    ContextBudgetProfile {
        profile_version: canonical.profile_version.clone(),
        profile_id: profile_id.to_string(),
        task_profile: canonical.task_profile.clone(),
        default_tool_id: canonical.default_tool_id.clone(),
        retrieval_query_type: canonical.retrieval_query_type.clone(),
        graphrag_query_mode_hint: graphrag_query_mode_hint.to_string(),
        temporal_truth_view: temporal_truth_view.to_string(),
        include_temporal_contradictions,
        selected_memory_tiers: selected_memory_tiers
            .iter()
            .map(|tier| (*tier).to_string())
            .collect(),
        max_context_items,
        allocations,
        note: note.to_string(),
    }
}
