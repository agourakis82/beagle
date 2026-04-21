use crate::{
    CompiledContextSourceSliceSummary,
    IntentPlannerAvailability, PlanExecutionStatusSummary,
    WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
    WorkstreamContextPacketMemoryHierarchyCount,
    WorkstreamContextPacketLastResult, WorkstreamContextPacketPhysioSnapshot,
    WorkstreamContextPacketRecipe,
};
use anyhow::{anyhow, Context};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::{
    cmp::Ordering,
    collections::{BTreeMap, BTreeSet},
    env, fs,
    path::Path,
};

const PROGRAM_CONTEXT_PACKET_PHASE: &str = "B19.2";
const PROGRAM_CONTEXT_PACKET_VERSION: &str = "beagle-program-context-packet-v1";

const PROGRAM_FILE_PATH: &str = "docs/darwin/hpc/programs/beagle-physio-symbolic-exocortex.yaml";
const CAMPAIGN_GOVERNANCE_FILE_PATH: &str =
    "docs/darwin/hpc/campaigns/darwin-hpc-governance.yaml";
const CAMPAIGN_EXPEDITION_002_FILE_PATH: &str =
    "docs/darwin/hpc/campaigns/expedition-002-hrv-aware.yaml";

const EMBEDDED_PROGRAM_YAML: &str =
    include_str!("../../../docs/darwin/hpc/programs/beagle-physio-symbolic-exocortex.yaml");
const EMBEDDED_GOVERNANCE_CAMPAIGN_YAML: &str =
    include_str!("../../../docs/darwin/hpc/campaigns/darwin-hpc-governance.yaml");
const EMBEDDED_EXPEDITION_002_CAMPAIGN_YAML: &str =
    include_str!("../../../docs/darwin/hpc/campaigns/expedition-002-hrv-aware.yaml");

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgramDocument {
    pub id: String,
    pub title: String,
    pub status: String,
    pub source_phase: String,
    pub program_kind: String,
    pub north_star: ProgramNorthStar,
    #[serde(default)]
    pub campaigns: Vec<ProgramCampaignRef>,
    #[serde(default)]
    pub workstreams: Vec<ProgramWorkstreamRef>,
    #[serde(default)]
    pub experiments: Vec<ProgramExperimentRef>,
    #[serde(default)]
    pub evidence_targets: Vec<ProgramEvidenceTarget>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProgramNorthStar {
    #[serde(default)]
    pub statement: String,
    #[serde(default)]
    pub target_outputs: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProgramCampaignRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub file: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProgramWorkstreamRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub role: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProgramExperimentRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub campaign_id: String,
    #[serde(default)]
    pub spec_doc: String,
    #[serde(default)]
    pub results_doc: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProgramEvidenceTarget {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CampaignDocument {
    pub id: String,
    pub program_id: String,
    pub title: String,
    pub status: String,
    pub campaign_kind: String,
    pub source_phase: String,
    #[serde(default)]
    pub objective: String,
    #[serde(default)]
    pub workstreams: Vec<CampaignWorkstreamRef>,
    #[serde(default)]
    pub experiments: Vec<CampaignExperimentRef>,
    #[serde(default)]
    pub datasets: Vec<CampaignDatasetRef>,
    #[serde(default)]
    pub observer_context: Option<CampaignObserverContext>,
    #[serde(default)]
    pub memory_context: Option<CampaignMemoryContext>,
    #[serde(default)]
    pub evidence_targets: Vec<ProgramEvidenceTarget>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CampaignWorkstreamRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub role: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CampaignExperimentRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub spec_doc: String,
    #[serde(default)]
    pub results_doc: String,
    #[serde(default)]
    pub live_batch_id: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CampaignDatasetRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub artifact_root: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CampaignObserverContext {
    #[serde(default)]
    pub contract: String,
    #[serde(default)]
    pub source_phase: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CampaignMemoryContext {
    #[serde(default)]
    pub source_phase: String,
    #[serde(default)]
    pub query_contract: String,
}

#[derive(Debug, Clone)]
pub struct ProgramCampaignBinding {
    pub program: ProgramDocument,
    pub campaign: CampaignDocument,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgramContextPacketResponse {
    pub status: String,
    pub phase: String,
    pub packet: ProgramContextPacket,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgramContextPacket {
    pub packet_version: String,
    pub program_id: String,
    pub program_title: String,
    pub program_kind: String,
    pub north_star: String,
    pub campaign_id: String,
    pub campaign_ids: Vec<String>,
    pub campaign_title: String,
    pub campaign_kind: String,
    pub campaign_status: String,
    pub objective: String,
    pub experiment_ids: Vec<String>,
    pub workstream_ids: Vec<String>,
    pub active_workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub latest_results: Vec<ProgramContextPacketLatestResult>,
    pub latest_memory_hits: Vec<ProgramContextPacketMemoryHit>,
    pub retrieval_context: Option<ProgramContextPacketRetrievalContext>,
    pub latest_physio: Option<WorkstreamContextPacketPhysioSnapshot>,
    pub experiment_flags: Option<WorkstreamContextPacketExperimentFlags>,
    pub recommended_next_recipe: Option<WorkstreamContextPacketRecipe>,
    pub evidence_targets: Vec<ProgramContextPacketEvidenceTarget>,
    pub manuscript_targets: Vec<ProgramContextPacketEvidenceTarget>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgramContextPacketLatestResult {
    pub workstream_id: String,
    pub last_result: WorkstreamContextPacketLastResult,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgramContextPacketMemoryHit {
    pub workstream_id: String,
    pub memory_id: Option<String>,
    pub source: String,
    pub conversation_id: Option<String>,
    pub turn_index: Option<usize>,
    pub role: Option<String>,
    pub snippet: String,
    pub timestamp: Option<chrono::DateTime<chrono::Utc>>,
    pub relevance: f32,
    pub tags: Vec<String>,
    pub domain: Option<String>,
    pub physio_snapshot: Option<WorkstreamContextPacketPhysioSnapshot>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgramContextPacketRetrievalContext {
    pub active_workstream_id: String,
    pub contributing_workstream_count: usize,
    pub query_type: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub routing_source: String,
    pub reranking_applied: bool,
    pub reranking_profile_id: Option<String>,
    pub reranker_backend: Option<String>,
    pub reranker_runtime_state: Option<String>,
    pub reranking_latency_ms: Option<u64>,
    pub top_memory_ids: Vec<String>,
    pub top_domains: Vec<String>,
    pub top_tags: Vec<String>,
    pub promotion_policy_id: Option<String>,
    pub retention_policy_id: Option<String>,
    pub graphrag_query_mode: Option<String>,
    pub graphrag_query_mode_reason: Option<String>,
    pub graphrag_root_entity_type: Option<String>,
    pub graphrag_root_entity_id: Option<String>,
    pub graphrag_node_count: usize,
    pub graphrag_edge_count: usize,
    pub graphrag_node_types: Vec<String>,
    pub graphrag_edge_types: Vec<String>,
    pub memory_hierarchy_counts: Vec<WorkstreamContextPacketMemoryHierarchyCount>,
    pub promoted_memory_count: usize,
    pub promoted_target_memory_types: Vec<String>,
    pub compiled_context_task_profile: Option<String>,
    pub compiled_context_budget_profile_id: Option<String>,
    pub compiled_context_retrieval_query_type: Option<String>,
    pub compiled_context_graphrag_query_mode: Option<String>,
    pub compiled_context_selected_memory_tiers: Vec<String>,
    pub compiled_context_source_slices: Vec<CompiledContextSourceSliceSummary>,
    pub compiled_context_top_memory_ids: Vec<String>,
    pub compiled_context_preview: Option<String>,
    pub planner: Option<IntentPlannerAvailability>,
    pub execution: Option<PlanExecutionStatusSummary>,
    pub temporal_truth_view: Option<String>,
    pub temporal_subject_refs: Vec<String>,
    pub temporal_current_memory_ids: Vec<String>,
    pub temporal_historical_memory_ids: Vec<String>,
    pub temporal_track_count: usize,
    pub temporal_contradiction_count: usize,
    pub temporal_contradiction_ids: Vec<String>,
    pub temporal_preview: Option<String>,
    pub suggested_subagent_id: Option<String>,
    pub suggested_work_mode: Option<String>,
    pub influence_reason: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgramContextPacketEvidenceTarget {
    pub scope: String,
    pub scope_id: String,
    pub id: String,
    pub kind: String,
    pub path: String,
}

pub fn resolve_program_context_binding(program_id: &str) -> anyhow::Result<ProgramCampaignBinding> {
    let program = load_program_document(program_id)?;
    let campaign = select_active_campaign_for_program(&program)?;
    Ok(ProgramCampaignBinding { program, campaign })
}

pub fn resolve_campaign_context_binding(
    campaign_id: &str,
) -> anyhow::Result<ProgramCampaignBinding> {
    let campaign = load_campaign_document(campaign_id)?;
    let program = load_program_document(&campaign.program_id)?;
    Ok(ProgramCampaignBinding { program, campaign })
}

pub fn resolve_program_campaign_binding_for_workstream(
    workstream_id: &str,
) -> anyhow::Result<Option<ProgramCampaignBinding>> {
    let mut candidates = load_campaign_documents()?
        .into_iter()
        .filter(|campaign| {
            campaign
                .workstreams
                .iter()
                .any(|workstream| workstream.id == workstream_id)
        })
        .collect::<Vec<_>>();

    candidates.sort_by(|left, right| {
        campaign_status_rank(&right.status).cmp(&campaign_status_rank(&left.status))
    });

    if let Some(campaign) = candidates.into_iter().next() {
        let program = load_program_document(&campaign.program_id)?;
        return Ok(Some(ProgramCampaignBinding { program, campaign }));
    }

    Ok(None)
}

pub fn build_program_context_packet(
    binding: &ProgramCampaignBinding,
    workstream_packets: &[WorkstreamContextPacket],
) -> anyhow::Result<ProgramContextPacketResponse> {
    let packet = build_packet(binding, workstream_packets)?;
    Ok(ProgramContextPacketResponse {
        status: "ok".to_string(),
        phase: PROGRAM_CONTEXT_PACKET_PHASE.to_string(),
        packet,
    })
}

fn build_packet(
    binding: &ProgramCampaignBinding,
    workstream_packets: &[WorkstreamContextPacket],
) -> anyhow::Result<ProgramContextPacket> {
    let packet_map = workstream_packets
        .iter()
        .map(|packet| (packet.workstream_id.clone(), packet))
        .collect::<BTreeMap<_, _>>();

    let ordered_workstream_ids = binding
        .campaign
        .workstreams
        .iter()
        .map(|workstream| workstream.id.clone())
        .collect::<Vec<_>>();

    let active_workstream_id = ordered_workstream_ids
        .iter()
        .find(|workstream_id| packet_map.contains_key(*workstream_id))
        .cloned()
        .or_else(|| workstream_packets.first().map(|packet| packet.workstream_id.clone()))
        .ok_or_else(|| anyhow!("no workstream packets available for {}", binding.campaign.id))?;

    let active_packet = packet_map
        .get(&active_workstream_id)
        .copied()
        .ok_or_else(|| anyhow!("missing active workstream packet {}", active_workstream_id))?;

    let latest_results = ordered_workstream_ids
        .iter()
        .filter_map(|workstream_id| {
            packet_map.get(workstream_id).and_then(|packet| {
                if packet.last_result.available || packet.last_result.reference.is_some() {
                    Some(ProgramContextPacketLatestResult {
                        workstream_id: (*workstream_id).clone(),
                        last_result: packet.last_result.clone(),
                    })
                } else {
                    None
                }
            })
        })
        .take(5)
        .collect::<Vec<_>>();

    let latest_memory_hits = aggregate_memory_hits(&ordered_workstream_ids, &packet_map);
    let retrieval_context = build_program_retrieval_context(
        &active_workstream_id,
        &ordered_workstream_ids,
        &packet_map,
        &latest_memory_hits,
    );
    let latest_physio = active_packet
        .latest_physio
        .clone()
        .or_else(|| first_non_none_physio(&ordered_workstream_ids, &packet_map));
    let experiment_flags = active_packet
        .experiment_flags
        .clone()
        .or_else(|| first_non_none_experiment_flags(&ordered_workstream_ids, &packet_map));
    let recommended_next_recipe = active_packet.recommended_recipe.clone();

    let evidence_targets = combined_evidence_targets(binding);
    let manuscript_targets = evidence_targets
        .iter()
        .filter(|target| target.kind.contains("manuscript"))
        .cloned()
        .collect::<Vec<_>>();

    Ok(ProgramContextPacket {
        packet_version: PROGRAM_CONTEXT_PACKET_VERSION.to_string(),
        program_id: binding.program.id.clone(),
        program_title: binding.program.title.clone(),
        program_kind: binding.program.program_kind.clone(),
        north_star: binding.program.north_star.statement.clone(),
        campaign_id: binding.campaign.id.clone(),
        campaign_ids: binding
            .program
            .campaigns
            .iter()
            .map(|campaign| campaign.id.clone())
            .collect(),
        campaign_title: binding.campaign.title.clone(),
        campaign_kind: binding.campaign.campaign_kind.clone(),
        campaign_status: binding.campaign.status.clone(),
        objective: binding.campaign.objective.clone(),
        experiment_ids: binding
            .campaign
            .experiments
            .iter()
            .map(|experiment| experiment.id.clone())
            .collect(),
        workstream_ids: ordered_workstream_ids,
        active_workstream_id,
        workspace_id: active_packet.workspace_id.clone(),
        session_id: active_packet.session_id.clone(),
        repo: active_packet.repo.clone(),
        branch: active_packet.branch.clone(),
        governance_state: active_packet.governance_state.clone(),
        latest_results,
        latest_memory_hits,
        retrieval_context,
        latest_physio,
        experiment_flags,
        recommended_next_recipe,
        evidence_targets,
        manuscript_targets,
    })
}

fn aggregate_memory_hits(
    ordered_workstream_ids: &[String],
    packet_map: &BTreeMap<String, &WorkstreamContextPacket>,
) -> Vec<ProgramContextPacketMemoryHit> {
    let mut seen = BTreeSet::new();
    let mut hits = Vec::new();

    for workstream_id in ordered_workstream_ids {
        if let Some(packet) = packet_map.get(workstream_id) {
            for hit in &packet.memory_hits {
                let key = hit.memory_id.clone().unwrap_or_else(|| {
                    format!(
                        "{}:{}:{}:{}",
                        workstream_id,
                        hit.source,
                        hit.conversation_id.clone().unwrap_or_default(),
                        hit.turn_index.unwrap_or_default()
                    )
                });
                if seen.insert(key) {
                    hits.push(ProgramContextPacketMemoryHit {
                        workstream_id: workstream_id.clone(),
                        memory_id: hit.memory_id.clone(),
                        source: hit.source.clone(),
                        conversation_id: hit.conversation_id.clone(),
                        turn_index: hit.turn_index,
                        role: hit.role.clone(),
                        snippet: hit.snippet.clone(),
                        timestamp: hit.timestamp,
                        relevance: hit.relevance,
                        tags: hit.tags.clone(),
                        domain: hit.domain.clone(),
                        physio_snapshot: hit.physio_snapshot.clone(),
                    });
                }
            }
        }
    }

    hits.sort_by(|left, right| {
        match right.timestamp.cmp(&left.timestamp) {
            Ordering::Equal => right
                .relevance
                .partial_cmp(&left.relevance)
                .unwrap_or(Ordering::Equal),
            other => other,
        }
    });
    hits.truncate(5);
    hits
}

fn build_program_retrieval_context(
    active_workstream_id: &str,
    ordered_workstream_ids: &[String],
    packet_map: &BTreeMap<String, &WorkstreamContextPacket>,
    latest_memory_hits: &[ProgramContextPacketMemoryHit],
) -> Option<ProgramContextPacketRetrievalContext> {
    let active_retrieval = packet_map
        .get(active_workstream_id)
        .and_then(|packet| packet.retrieval_context.as_ref())?;

    let mut top_memory_ids = Vec::new();
    let mut top_domains = Vec::new();
    let mut top_tags = Vec::new();
    let mut contributing_workstream_count = 0usize;

    for workstream_id in ordered_workstream_ids {
        if let Some(packet) = packet_map.get(workstream_id) {
            if let Some(retrieval) = packet.retrieval_context.as_ref() {
                contributing_workstream_count += 1;
                extend_unique(
                    &mut top_memory_ids,
                    retrieval.top_memory_ids.iter().cloned(),
                    6,
                );
                extend_unique(&mut top_domains, retrieval.top_domains.iter().cloned(), 5);
                extend_unique(&mut top_tags, retrieval.top_tags.iter().cloned(), 8);
            }
        }
    }

    extend_unique(
        &mut top_memory_ids,
        latest_memory_hits.iter().filter_map(|hit| hit.memory_id.clone()),
        6,
    );
    extend_unique(
        &mut top_domains,
        latest_memory_hits.iter().filter_map(|hit| hit.domain.clone()),
        5,
    );
    extend_unique(
        &mut top_tags,
        latest_memory_hits
            .iter()
            .flat_map(|hit| hit.tags.iter().cloned()),
        8,
    );

    Some(ProgramContextPacketRetrievalContext {
        active_workstream_id: active_workstream_id.to_string(),
        contributing_workstream_count,
        query_type: active_retrieval.query_type.clone(),
        dense_backend: active_retrieval.dense_backend.clone(),
        sparse_backend: active_retrieval.sparse_backend.clone(),
        routing_source: active_retrieval.routing_source.clone(),
        reranking_applied: active_retrieval.reranking_applied,
        reranking_profile_id: active_retrieval.reranking_profile_id.clone(),
        reranker_backend: active_retrieval.reranker_backend.clone(),
        reranker_runtime_state: active_retrieval.reranker_runtime_state.clone(),
        reranking_latency_ms: active_retrieval.reranking_latency_ms,
        top_memory_ids,
        top_domains,
        top_tags,
        promotion_policy_id: active_retrieval.promotion_policy_id.clone(),
        retention_policy_id: active_retrieval.retention_policy_id.clone(),
        graphrag_query_mode: active_retrieval.graphrag_query_mode.clone(),
        graphrag_query_mode_reason: active_retrieval.graphrag_query_mode_reason.clone(),
        graphrag_root_entity_type: active_retrieval.graphrag_root_entity_type.clone(),
        graphrag_root_entity_id: active_retrieval.graphrag_root_entity_id.clone(),
        graphrag_node_count: active_retrieval.graphrag_node_count,
        graphrag_edge_count: active_retrieval.graphrag_edge_count,
        graphrag_node_types: active_retrieval.graphrag_node_types.clone(),
        graphrag_edge_types: active_retrieval.graphrag_edge_types.clone(),
        memory_hierarchy_counts: active_retrieval.memory_hierarchy_counts.clone(),
        promoted_memory_count: active_retrieval.promoted_memory_count,
        promoted_target_memory_types: active_retrieval.promoted_target_memory_types.clone(),
        compiled_context_task_profile: active_retrieval.compiled_context_task_profile.clone(),
        compiled_context_budget_profile_id: active_retrieval
            .compiled_context_budget_profile_id
            .clone(),
        compiled_context_retrieval_query_type: active_retrieval
            .compiled_context_retrieval_query_type
            .clone(),
        compiled_context_graphrag_query_mode: active_retrieval
            .compiled_context_graphrag_query_mode
            .clone(),
        compiled_context_selected_memory_tiers: active_retrieval
            .compiled_context_selected_memory_tiers
            .clone(),
        compiled_context_source_slices: active_retrieval
            .compiled_context_source_slices
            .clone(),
        compiled_context_top_memory_ids: active_retrieval
            .compiled_context_top_memory_ids
            .clone(),
        compiled_context_preview: active_retrieval.compiled_context_preview.clone(),
        planner: active_retrieval.planner.clone(),
        execution: active_retrieval.execution.clone(),
        temporal_truth_view: active_retrieval.temporal_truth_view.clone(),
        temporal_subject_refs: active_retrieval.temporal_subject_refs.clone(),
        temporal_current_memory_ids: active_retrieval
            .temporal_current_memory_ids
            .clone(),
        temporal_historical_memory_ids: active_retrieval
            .temporal_historical_memory_ids
            .clone(),
        temporal_track_count: active_retrieval.temporal_track_count,
        temporal_contradiction_count: active_retrieval.temporal_contradiction_count,
        temporal_contradiction_ids: active_retrieval
            .temporal_contradiction_ids
            .clone(),
        temporal_preview: active_retrieval.temporal_preview.clone(),
        suggested_subagent_id: active_retrieval.suggested_subagent_id.clone(),
        suggested_work_mode: active_retrieval.suggested_work_mode.clone(),
        influence_reason: format!(
            "program/campaign context preserved retrieval guidance from {}: {}",
            active_workstream_id, active_retrieval.influence_reason
        ),
    })
}

fn extend_unique<I>(target: &mut Vec<String>, values: I, limit: usize)
where
    I: IntoIterator<Item = String>,
{
    for value in values {
        let normalized = value.trim();
        if normalized.is_empty() {
            continue;
        }
        if target.iter().any(|existing| existing == normalized) {
            continue;
        }
        target.push(normalized.to_string());
        if target.len() >= limit {
            break;
        }
    }
}

fn first_non_none_physio(
    ordered_workstream_ids: &[String],
    packet_map: &BTreeMap<String, &WorkstreamContextPacket>,
) -> Option<WorkstreamContextPacketPhysioSnapshot> {
    ordered_workstream_ids.iter().find_map(|workstream_id| {
        packet_map
            .get(workstream_id)
            .and_then(|packet| packet.latest_physio.clone())
    })
}

fn first_non_none_experiment_flags(
    ordered_workstream_ids: &[String],
    packet_map: &BTreeMap<String, &WorkstreamContextPacket>,
) -> Option<WorkstreamContextPacketExperimentFlags> {
    ordered_workstream_ids.iter().find_map(|workstream_id| {
        packet_map
            .get(workstream_id)
            .and_then(|packet| packet.experiment_flags.clone())
    })
}

fn combined_evidence_targets(binding: &ProgramCampaignBinding) -> Vec<ProgramContextPacketEvidenceTarget> {
    let mut targets = Vec::new();

    for target in &binding.program.evidence_targets {
        targets.push(ProgramContextPacketEvidenceTarget {
            scope: "program".to_string(),
            scope_id: binding.program.id.clone(),
            id: target.id.clone(),
            kind: target.kind.clone(),
            path: target.path.clone(),
        });
    }

    for target in &binding.campaign.evidence_targets {
        targets.push(ProgramContextPacketEvidenceTarget {
            scope: "campaign".to_string(),
            scope_id: binding.campaign.id.clone(),
            id: target.id.clone(),
            kind: target.kind.clone(),
            path: target.path.clone(),
        });
    }

    targets
}

fn select_active_campaign_for_program(program: &ProgramDocument) -> anyhow::Result<CampaignDocument> {
    let campaign_ids = program
        .campaigns
        .iter()
        .map(|campaign| campaign.id.as_str())
        .collect::<Vec<_>>();
    let mut campaigns = campaign_ids
        .into_iter()
        .map(load_campaign_document)
        .collect::<anyhow::Result<Vec<_>>>()?;

    campaigns.sort_by(|left, right| {
        campaign_status_rank(&right.status).cmp(&campaign_status_rank(&left.status))
    });

    campaigns.into_iter().next().ok_or_else(|| {
        anyhow!(
            "program {} does not reference any resolvable campaign",
            program.id
        )
    })
}

fn campaign_status_rank(status: &str) -> u8 {
    let normalized = status.trim().to_ascii_lowercase();
    if normalized.contains("live") {
        3
    } else if normalized.contains("canonical") {
        2
    } else if normalized.contains("pilot") {
        1
    } else {
        0
    }
}

fn load_program_document(program_id: &str) -> anyhow::Result<ProgramDocument> {
    let program = load_yaml_document::<ProgramDocument>(PROGRAM_FILE_PATH)?;
    if program.id == program_id {
        Ok(program)
    } else {
        Err(anyhow!("program {} is not registered", program_id))
    }
}

fn load_campaign_document(campaign_id: &str) -> anyhow::Result<CampaignDocument> {
    load_campaign_documents()?
        .into_iter()
        .find(|campaign| campaign.id == campaign_id)
        .ok_or_else(|| anyhow!("campaign {} is not registered", campaign_id))
}

fn load_campaign_documents() -> anyhow::Result<Vec<CampaignDocument>> {
    Ok(vec![
        load_yaml_document(CAMPAIGN_GOVERNANCE_FILE_PATH)?,
        load_yaml_document(CAMPAIGN_EXPEDITION_002_FILE_PATH)?,
    ])
}

fn load_yaml_document<T>(path: &str) -> anyhow::Result<T>
where
    T: DeserializeOwned,
{
    let body = load_document_text(path)?;
    serde_yaml::from_str::<T>(&body)
        .with_context(|| format!("failed to decode program context document {}", path))
}

fn load_document_text(path: &str) -> anyhow::Result<String> {
    if let Some(contents) = load_document_text_from_fs(path)? {
        return Ok(contents);
    }

    embedded_document(path)
        .map(str::to_string)
        .ok_or_else(|| anyhow!("program context document {} is not embedded", path))
}

fn load_document_text_from_fs(path: &str) -> anyhow::Result<Option<String>> {
    let mut candidate_roots = Vec::new();

    if let Ok(root) = env::var("BEAGLE_REPO_ROOT") {
        if !root.trim().is_empty() {
            candidate_roots.push(root);
        }
    }

    if let Ok(current_dir) = env::current_dir() {
        candidate_roots.push(current_dir.display().to_string());
    }

    for root in candidate_roots {
        let candidate = Path::new(&root).join(path);
        if candidate.exists() {
            let contents = fs::read_to_string(&candidate).with_context(|| {
                format!("failed to read program context document {}", candidate.display())
            })?;
            return Ok(Some(contents));
        }
    }

    Ok(None)
}

fn embedded_document(path: &str) -> Option<&'static str> {
    match path {
        PROGRAM_FILE_PATH => Some(EMBEDDED_PROGRAM_YAML),
        CAMPAIGN_GOVERNANCE_FILE_PATH => Some(EMBEDDED_GOVERNANCE_CAMPAIGN_YAML),
        CAMPAIGN_EXPEDITION_002_FILE_PATH => Some(EMBEDDED_EXPEDITION_002_CAMPAIGN_YAML),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use crate::WorkstreamContextPacketMemoryHit;

    fn sample_packet(workstream_id: &str, session_id: &str, recipe_kind: &str) -> WorkstreamContextPacket {
        WorkstreamContextPacket {
            packet_version: "test".to_string(),
            workstream_id: workstream_id.to_string(),
            workspace_id: format!("workspace-{}", workstream_id),
            session_id: session_id.to_string(),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            governance_state: "canonical".to_string(),
            handoff: crate::WorkstreamContextPacketHandoff {
                handoff_required: true,
                recovery_required: true,
                handoff_present: true,
                last_handoff: Some("resume from canonical packet".to_string()),
            },
            last_result: WorkstreamContextPacketLastResult {
                available: true,
                reference: None,
                summary: Some(crate::WorkstreamContextPacketResultSummary {
                    job_id: 42,
                    state: "COMPLETED".to_string(),
                    run_label: format!("run-{}", workstream_id),
                    profile_id: "cpu-batch-v1".to_string(),
                    node_list: "t560-proxmox".to_string(),
                    manifest_key: format!("manifest-{}", workstream_id),
                    source_phase: Some("B17.4".to_string()),
                    source_run_id: Some("run-42".to_string()),
                }),
                manifest: None,
                error: None,
            },
            last_successful_task: None,
            latest_physio: Some(WorkstreamContextPacketPhysioSnapshot {
                hr: Some(72.0),
                hrv_level: Some("balanced".to_string()),
                spo2: Some(98.0),
                timestamp: Some(Utc::now()),
                source: Some("observer-smoke".to_string()),
            }),
            experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                hrv_aware: Some(true),
                observer_enabled: Some(true),
                serendipity_enabled: Some(false),
                triad_enabled: Some(false),
                provider: Some("xai".to_string()),
                model: Some("grok-4-1-fast-reasoning".to_string()),
                experiment_id: Some("beagle_exp_002_hrv_aware_vs_blind".to_string()),
                condition: Some("hrv_aware".to_string()),
            }),
            memory_hits: vec![WorkstreamContextPacketMemoryHit {
                memory_id: Some(format!("memory-{}", workstream_id)),
                source: "codex".to_string(),
                conversation_id: Some(session_id.to_string()),
                turn_index: Some(1),
                role: Some("tool".to_string()),
                snippet: format!("memory for {}", workstream_id),
                timestamp: Some(Utc::now()),
                relevance: 0.9,
                tags: vec![workstream_id.to_string()],
                domain: Some("beagle-engine".to_string()),
                physio_snapshot: None,
            }],
            retrieval_context: None,
            recommended_recipe: Some(WorkstreamContextPacketRecipe {
                id: format!("{}-recipe", recipe_kind),
                kind: recipe_kind.to_string(),
                summary: "bounded next step".to_string(),
            }),
            bounded_study_baseline: None,
        }
    }

    #[test]
    fn program_binding_prefers_live_campaign_for_workstream() {
        let binding = resolve_program_campaign_binding_for_workstream("beagle-darwin-hpc-governance")
            .unwrap()
            .unwrap();
        assert_eq!(binding.program.id, "beagle-physio-symbolic-exocortex");
        assert_eq!(binding.campaign.id, "expedition-002-hrv-aware");
    }

    #[test]
    fn program_context_packet_prefers_live_campaign_resolution() {
        let binding = resolve_program_context_binding("beagle-physio-symbolic-exocortex").unwrap();
        let packet = build_program_context_packet(
            &binding,
            &[sample_packet(
                "beagle-darwin-hpc-governance",
                "ws-program",
                "operator_cpu_loop",
            )],
        )
        .unwrap();

        assert_eq!(packet.packet.program_id, "beagle-physio-symbolic-exocortex");
        assert_eq!(packet.packet.campaign_id, "expedition-002-hrv-aware");
        assert_eq!(packet.packet.active_workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(packet.packet.recommended_next_recipe.as_ref().unwrap().kind, "operator_cpu_loop");
        assert!(packet
            .packet
            .manuscript_targets
            .iter()
            .any(|target| target.id == "expedition-002-results"));
    }

    #[test]
    fn campaign_context_packet_aggregates_workstreams_memory_and_results() {
        let binding = resolve_campaign_context_binding("darwin-hpc-governance").unwrap();
        let packet = build_program_context_packet(
            &binding,
            &[
                sample_packet(
                    "beagle-darwin-hpc-governance",
                    "ws-governance",
                    "operator_cpu_loop",
                ),
                sample_packet(
                    "beagle-darwin-hpc-wave1",
                    "ws-wave1",
                    "repo_native_dev_loop",
                ),
            ],
        )
        .unwrap();

        assert_eq!(packet.packet.campaign_id, "darwin-hpc-governance");
        assert_eq!(packet.packet.workstream_ids.len(), 2);
        assert_eq!(packet.packet.latest_results.len(), 2);
        assert_eq!(packet.packet.latest_memory_hits.len(), 2);
        assert_eq!(packet.packet.active_workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(packet.packet.latest_memory_hits[0].workstream_id, "beagle-darwin-hpc-wave1");
    }
}
