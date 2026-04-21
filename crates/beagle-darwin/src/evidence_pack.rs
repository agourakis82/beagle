use crate::{
    ProgramCampaignBinding, ProgramContextPacket, ProgramContextPacketEvidenceTarget,
    ProgramContextPacketMemoryHit, WorkstreamContextPacketLastResult,
    WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
};
use anyhow::anyhow;
use chrono::{DateTime, Datelike, Utc};
use serde::Serialize;
use std::collections::BTreeSet;

const EVIDENCE_PACK_PHASE: &str = "B19.3";
const EVIDENCE_PACK_VERSION: &str = "beagle-evidence-pack-v1";
const EVIDENCE_PACK_CRATE_PROFILE: &str = "ro-crate-inspired";
const EVIDENCE_PACK_PROVENANCE_PROFILE: &str = "w3c-prov-bounded";
const EVIDENCE_PACK_CITATION_PROFILE: &str = "datacite-4.7-ready";

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackResponse {
    pub status: String,
    pub phase: String,
    pub pack: EvidencePack,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePack {
    pub pack_version: String,
    pub crate_profile: String,
    pub pack_id: String,
    pub program_id: String,
    pub campaign_id: String,
    pub campaign_title: String,
    pub campaign_kind: String,
    pub campaign_status: String,
    pub objective: String,
    pub workstream_ids: Vec<String>,
    pub active_workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub experiment_refs: Vec<EvidencePackExperimentRef>,
    pub dataset_refs: Vec<EvidencePackDatasetRef>,
    pub result_refs: Vec<EvidencePackResultRef>,
    pub memory_refs: Vec<EvidencePackMemoryRef>,
    pub physio_refs: Vec<EvidencePackPhysioRef>,
    pub recipe_refs: Vec<EvidencePackRecipeRef>,
    pub evidence_targets: Vec<ProgramContextPacketEvidenceTarget>,
    pub manuscript_target: Option<ProgramContextPacketEvidenceTarget>,
    pub decision_notes: Vec<EvidencePackDecisionNote>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackExperimentRef {
    pub experiment_id: String,
    pub spec_doc: String,
    pub results_doc: String,
    pub live_batch_id: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackDatasetRef {
    pub dataset_id: String,
    pub kind: String,
    pub artifact_root: String,
    pub expected_files: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackResultRef {
    pub workstream_id: String,
    pub job_id: Option<u64>,
    pub run_label: Option<String>,
    pub profile_id: Option<String>,
    pub node_list: Option<String>,
    pub result_reference: Option<String>,
    pub manifest_key: Option<String>,
    pub object_bucket: Option<String>,
    pub object_key: Option<String>,
    pub manifest_object_key: Option<String>,
    pub source_phase: Option<String>,
    pub source_run_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackMemoryRef {
    pub workstream_id: String,
    pub memory_id: Option<String>,
    pub source: String,
    pub conversation_id: Option<String>,
    pub turn_index: Option<usize>,
    pub role: Option<String>,
    pub snippet: String,
    pub timestamp: Option<DateTime<Utc>>,
    pub tags: Vec<String>,
    pub domain: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackPhysioRef {
    pub scope: String,
    pub workstream_id: Option<String>,
    pub memory_id: Option<String>,
    pub source: Option<String>,
    pub timestamp: Option<DateTime<Utc>>,
    pub hr: Option<f64>,
    pub hrv_level: Option<String>,
    pub spo2: Option<f64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackRecipeRef {
    pub scope: String,
    pub workstream_id: String,
    pub recipe_id: String,
    pub kind: String,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackDecisionNote {
    pub note_kind: String,
    pub summary: String,
    pub related_refs: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackProvenance {
    pub profile: String,
    pub generated_at: DateTime<Utc>,
    pub generator_component: String,
    pub generator_phase: String,
    pub agents: Vec<EvidencePackProvenanceAgent>,
    pub activities: Vec<EvidencePackProvenanceActivity>,
    pub entities: Vec<EvidencePackProvenanceEntity>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackProvenanceAgent {
    pub id: String,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackProvenanceActivity {
    pub id: String,
    pub kind: String,
    pub used: Vec<String>,
    pub generated: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackProvenanceEntity {
    pub id: String,
    pub entity_kind: String,
    pub location: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackCitation {
    pub profile: String,
    pub title: String,
    pub creators: Vec<String>,
    pub publisher: String,
    pub publication_year: i32,
    pub resource_type_general: String,
    pub version: String,
    pub subjects: Vec<String>,
    pub descriptions: Vec<String>,
    pub related_identifiers: Vec<EvidencePackRelatedIdentifier>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvidencePackRelatedIdentifier {
    pub relation_type: String,
    pub identifier_type: String,
    pub value: String,
}

pub fn build_campaign_evidence_pack(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
) -> anyhow::Result<EvidencePackResponse> {
    if packet.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "campaign packet {} does not match binding {}",
            packet.campaign_id,
            binding.campaign.id
        ));
    }

    let experiment_refs = binding
        .campaign
        .experiments
        .iter()
        .map(|experiment| EvidencePackExperimentRef {
            experiment_id: experiment.id.clone(),
            spec_doc: experiment.spec_doc.clone(),
            results_doc: experiment.results_doc.clone(),
            live_batch_id: experiment.live_batch_id.clone(),
        })
        .collect::<Vec<_>>();
    let dataset_refs = binding
        .campaign
        .datasets
        .iter()
        .map(|dataset| EvidencePackDatasetRef {
            dataset_id: dataset.id.clone(),
            kind: dataset.kind.clone(),
            artifact_root: dataset.artifact_root.clone(),
            expected_files: expected_dataset_files(dataset.artifact_root.as_str(), dataset.kind.as_str()),
        })
        .collect::<Vec<_>>();
    let result_refs = packet
        .latest_results
        .iter()
        .map(|result| result_ref_from_packet(result.workstream_id.as_str(), &result.last_result))
        .collect::<Vec<_>>();
    let memory_refs = packet
        .latest_memory_hits
        .iter()
        .map(memory_ref_from_hit)
        .collect::<Vec<_>>();
    let physio_refs = collect_physio_refs(packet);
    let recipe_refs = collect_recipe_refs(packet);
    let manuscript_target = packet.manuscript_targets.first().cloned();
    let decision_notes = collect_decision_notes(packet, &manuscript_target);
    let provenance = build_provenance(
        binding,
        packet,
        &experiment_refs,
        &dataset_refs,
        &result_refs,
        &memory_refs,
        &physio_refs,
        &recipe_refs,
        &manuscript_target,
    );
    let citation = build_citation(binding, packet, &experiment_refs, &manuscript_target, &result_refs);

    Ok(EvidencePackResponse {
        status: "ok".to_string(),
        phase: EVIDENCE_PACK_PHASE.to_string(),
        pack: EvidencePack {
            pack_version: EVIDENCE_PACK_VERSION.to_string(),
            crate_profile: EVIDENCE_PACK_CRATE_PROFILE.to_string(),
            pack_id: format!("{}-evidence-pack", binding.campaign.id),
            program_id: packet.program_id.clone(),
            campaign_id: packet.campaign_id.clone(),
            campaign_title: packet.campaign_title.clone(),
            campaign_kind: packet.campaign_kind.clone(),
            campaign_status: packet.campaign_status.clone(),
            objective: packet.objective.clone(),
            workstream_ids: packet.workstream_ids.clone(),
            active_workstream_id: packet.active_workstream_id.clone(),
            workspace_id: packet.workspace_id.clone(),
            session_id: packet.session_id.clone(),
            repo: packet.repo.clone(),
            branch: packet.branch.clone(),
            governance_state: packet.governance_state.clone(),
            experiment_refs,
            dataset_refs,
            result_refs,
            memory_refs,
            physio_refs,
            recipe_refs,
            evidence_targets: packet.evidence_targets.clone(),
            manuscript_target,
            decision_notes,
            provenance,
            citation,
        },
    })
}

fn expected_dataset_files(artifact_root: &str, kind: &str) -> Vec<String> {
    let root = artifact_root.trim_end_matches('/');
    let mut files = vec![root.to_string()];
    if kind == "run-matrix" {
        files.extend(
            [
                "run-matrix.json",
                "analysis-summary.json",
                "analysis-summary.csv",
                "results-summary.json",
                "final-cluster-health.txt",
            ]
            .into_iter()
            .map(|name| format!("{}/{}", root, name)),
        );
    }
    files
}

fn result_ref_from_packet(
    workstream_id: &str,
    last_result: &WorkstreamContextPacketLastResult,
) -> EvidencePackResultRef {
    let job_id = last_result
        .summary
        .as_ref()
        .map(|summary| summary.job_id)
        .or_else(|| last_result.reference.as_ref().map(|reference| reference.job_id))
        .or_else(|| last_result.manifest.as_ref().map(|manifest| manifest.job_id));
    let run_label = last_result
        .summary
        .as_ref()
        .map(|summary| summary.run_label.clone())
        .or_else(|| {
            last_result
                .reference
                .as_ref()
                .and_then(|reference| reference.run_label.clone())
        })
        .or_else(|| last_result.manifest.as_ref().and_then(|manifest| manifest.run_label.clone()));
    let profile_id = last_result
        .summary
        .as_ref()
        .map(|summary| summary.profile_id.clone())
        .or_else(|| {
            last_result
                .reference
                .as_ref()
                .and_then(|reference| reference.profile_id.clone())
        })
        .or_else(|| last_result.manifest.as_ref().and_then(|manifest| manifest.profile_id.clone()));
    let node_list = last_result
        .summary
        .as_ref()
        .map(|summary| summary.node_list.clone())
        .or_else(|| {
            last_result
                .reference
                .as_ref()
                .and_then(|reference| reference.node_list.clone())
        });
    let result_reference = job_id.map(|job_id| format!("result:{job_id}"));

    EvidencePackResultRef {
        workstream_id: workstream_id.to_string(),
        job_id,
        run_label,
        profile_id,
        node_list,
        result_reference,
        manifest_key: last_result
            .summary
            .as_ref()
            .map(|summary| summary.manifest_key.clone())
            .or_else(|| {
                last_result
                    .reference
                    .as_ref()
                    .and_then(|reference| reference.manifest_key.clone())
            }),
        object_bucket: last_result
            .manifest
            .as_ref()
            .map(|manifest| manifest.object_bucket.clone()),
        object_key: last_result
            .manifest
            .as_ref()
            .map(|manifest| manifest.object_key.clone()),
        manifest_object_key: last_result
            .manifest
            .as_ref()
            .map(|manifest| manifest.manifest_object_key.clone()),
        source_phase: last_result
            .summary
            .as_ref()
            .and_then(|summary| summary.source_phase.clone()),
        source_run_id: last_result
            .summary
            .as_ref()
            .and_then(|summary| summary.source_run_id.clone()),
    }
}

fn memory_ref_from_hit(hit: &ProgramContextPacketMemoryHit) -> EvidencePackMemoryRef {
    EvidencePackMemoryRef {
        workstream_id: hit.workstream_id.clone(),
        memory_id: hit.memory_id.clone(),
        source: hit.source.clone(),
        conversation_id: hit.conversation_id.clone(),
        turn_index: hit.turn_index,
        role: hit.role.clone(),
        snippet: hit.snippet.clone(),
        timestamp: hit.timestamp,
        tags: hit.tags.clone(),
        domain: hit.domain.clone(),
    }
}

fn collect_physio_refs(packet: &ProgramContextPacket) -> Vec<EvidencePackPhysioRef> {
    let mut refs = Vec::new();
    let mut seen = BTreeSet::new();

    if let Some(snapshot) = packet.latest_physio.as_ref() {
        if seen.insert(physio_ref_key("latest_physio", &packet.active_workstream_id, None, snapshot)) {
            refs.push(EvidencePackPhysioRef {
                scope: "latest_physio".to_string(),
                workstream_id: Some(packet.active_workstream_id.clone()),
                memory_id: None,
                source: snapshot.source.clone(),
                timestamp: snapshot.timestamp,
                hr: snapshot.hr,
                hrv_level: snapshot.hrv_level.clone(),
                spo2: snapshot.spo2,
            });
        }
    }

    for hit in &packet.latest_memory_hits {
        if let Some(snapshot) = hit.physio_snapshot.as_ref() {
            let key = physio_ref_key("memory_hit", &hit.workstream_id, hit.memory_id.as_deref(), snapshot);
            if seen.insert(key) {
                refs.push(EvidencePackPhysioRef {
                    scope: "memory_hit".to_string(),
                    workstream_id: Some(hit.workstream_id.clone()),
                    memory_id: hit.memory_id.clone(),
                    source: snapshot.source.clone(),
                    timestamp: snapshot.timestamp,
                    hr: snapshot.hr,
                    hrv_level: snapshot.hrv_level.clone(),
                    spo2: snapshot.spo2,
                });
            }
        }
    }

    refs
}

fn physio_ref_key(
    scope: &str,
    workstream_id: &str,
    memory_id: Option<&str>,
    snapshot: &WorkstreamContextPacketPhysioSnapshot,
) -> String {
    format!(
        "{}:{}:{}:{}:{}:{}",
        scope,
        workstream_id,
        memory_id.unwrap_or_default(),
        snapshot.source.clone().unwrap_or_default(),
        snapshot
            .timestamp
            .map(|timestamp| timestamp.to_rfc3339())
            .unwrap_or_default(),
        snapshot.hrv_level.clone().unwrap_or_default()
    )
}

fn collect_recipe_refs(packet: &ProgramContextPacket) -> Vec<EvidencePackRecipeRef> {
    packet
        .recommended_next_recipe
        .as_ref()
        .map(|recipe| vec![recipe_ref("recommended_next_recipe", &packet.active_workstream_id, recipe)])
        .unwrap_or_default()
}

fn recipe_ref(
    scope: &str,
    workstream_id: &str,
    recipe: &WorkstreamContextPacketRecipe,
) -> EvidencePackRecipeRef {
    EvidencePackRecipeRef {
        scope: scope.to_string(),
        workstream_id: workstream_id.to_string(),
        recipe_id: recipe.id.clone(),
        kind: recipe.kind.clone(),
        summary: recipe.summary.clone(),
    }
}

fn collect_decision_notes(
    packet: &ProgramContextPacket,
    manuscript_target: &Option<ProgramContextPacketEvidenceTarget>,
) -> Vec<EvidencePackDecisionNote> {
    let mut notes = vec![EvidencePackDecisionNote {
        note_kind: "campaign_objective".to_string(),
        summary: packet.objective.clone(),
        related_refs: vec![packet.campaign_id.clone()],
    }];

    if let Some(recipe) = packet.recommended_next_recipe.as_ref() {
        notes.push(EvidencePackDecisionNote {
            note_kind: "recommended_next_recipe".to_string(),
            summary: format!(
                "Continue the active campaign through the bounded recipe {} ({})",
                recipe.id, recipe.kind
            ),
            related_refs: vec![recipe.id.clone(), packet.active_workstream_id.clone()],
        });
    }

    if let Some(target) = manuscript_target.as_ref() {
        notes.push(EvidencePackDecisionNote {
            note_kind: "manuscript_target".to_string(),
            summary: format!("Current campaign evidence remains aligned to {}", target.id),
            related_refs: vec![target.id.clone(), target.path.clone()],
        });
    }

    notes
}

fn build_provenance(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    experiment_refs: &[EvidencePackExperimentRef],
    dataset_refs: &[EvidencePackDatasetRef],
    result_refs: &[EvidencePackResultRef],
    memory_refs: &[EvidencePackMemoryRef],
    physio_refs: &[EvidencePackPhysioRef],
    recipe_refs: &[EvidencePackRecipeRef],
    manuscript_target: &Option<ProgramContextPacketEvidenceTarget>,
) -> EvidencePackProvenance {
    let mut entities = vec![
        EvidencePackProvenanceEntity {
            id: binding.program.id.clone(),
            entity_kind: "program".to_string(),
            location: Some(format!("docs/darwin/hpc/programs/{}.yaml", binding.program.id)),
        },
        EvidencePackProvenanceEntity {
            id: binding.campaign.id.clone(),
            entity_kind: "campaign".to_string(),
            location: Some(format!("docs/darwin/hpc/campaigns/{}.yaml", binding.campaign.id)),
        },
    ];

    entities.extend(experiment_refs.iter().flat_map(|experiment| {
        [
            EvidencePackProvenanceEntity {
                id: format!("experiment:{}", experiment.experiment_id),
                entity_kind: "experiment".to_string(),
                location: Some(experiment.spec_doc.clone()),
            },
            EvidencePackProvenanceEntity {
                id: format!("experiment-results:{}", experiment.experiment_id),
                entity_kind: "experiment-results".to_string(),
                location: Some(experiment.results_doc.clone()),
            },
        ]
    }));
    entities.extend(dataset_refs.iter().map(|dataset| EvidencePackProvenanceEntity {
        id: format!("dataset:{}", dataset.dataset_id),
        entity_kind: "dataset".to_string(),
        location: Some(dataset.artifact_root.clone()),
    }));
    entities.extend(result_refs.iter().filter_map(|result| {
        result.result_reference.as_ref().map(|reference| EvidencePackProvenanceEntity {
            id: reference.clone(),
            entity_kind: "result".to_string(),
            location: result.manifest_object_key.clone().or(result.manifest_key.clone()),
        })
    }));
    entities.extend(memory_refs.iter().filter_map(|memory| {
        memory.memory_id.as_ref().map(|memory_id| EvidencePackProvenanceEntity {
            id: format!("memory:{memory_id}"),
            entity_kind: "memory".to_string(),
            location: memory.conversation_id.clone(),
        })
    }));
    entities.extend(physio_refs.iter().enumerate().map(|(index, physio)| EvidencePackProvenanceEntity {
        id: format!("physio:{}:{}", physio.scope, index),
        entity_kind: "physio".to_string(),
        location: physio.source.clone(),
    }));
    entities.extend(recipe_refs.iter().map(|recipe| EvidencePackProvenanceEntity {
        id: format!("recipe:{}", recipe.recipe_id),
        entity_kind: "recipe".to_string(),
        location: Some(recipe.kind.clone()),
    }));
    if let Some(target) = manuscript_target.as_ref() {
        entities.push(EvidencePackProvenanceEntity {
            id: format!("manuscript-target:{}", target.id),
            entity_kind: "manuscript-target".to_string(),
            location: Some(target.path.clone()),
        });
    }

    let result_ids = result_refs
        .iter()
        .filter_map(|result| result.result_reference.clone())
        .collect::<Vec<_>>();
    let memory_ids = memory_refs
        .iter()
        .filter_map(|memory| memory.memory_id.as_ref().map(|id| format!("memory:{id}")))
        .collect::<Vec<_>>();
    let physio_ids = physio_refs
        .iter()
        .enumerate()
        .map(|(index, physio)| format!("physio:{}:{}", physio.scope, index))
        .collect::<Vec<_>>();
    let recipe_ids = recipe_refs
        .iter()
        .map(|recipe| format!("recipe:{}", recipe.recipe_id))
        .collect::<Vec<_>>();

    EvidencePackProvenance {
        profile: EVIDENCE_PACK_PROVENANCE_PROFILE.to_string(),
        generated_at: Utc::now(),
        generator_component: "beagle-darwin/evidence_pack".to_string(),
        generator_phase: EVIDENCE_PACK_PHASE.to_string(),
        agents: vec![EvidencePackProvenanceAgent {
            id: "beagle-darwin-runtime".to_string(),
            kind: "software-agent".to_string(),
        }],
        activities: vec![
            EvidencePackProvenanceActivity {
                id: "campaign-context-resolution".to_string(),
                kind: "context-resolution".to_string(),
                used: vec![binding.program.id.clone(), binding.campaign.id.clone()],
                generated: vec![format!("campaign-context:{}", packet.campaign_id)],
            },
            EvidencePackProvenanceActivity {
                id: "campaign-evidence-assembly".to_string(),
                kind: "evidence-assembly".to_string(),
                used: {
                    let mut used = vec![
                        format!("campaign-context:{}", packet.campaign_id),
                        binding.program.id.clone(),
                        binding.campaign.id.clone(),
                    ];
                    used.extend(result_ids.clone());
                    used.extend(memory_ids.clone());
                    used.extend(physio_ids.clone());
                    used.extend(recipe_ids.clone());
                    used
                },
                generated: vec![format!("evidence-pack:{}", binding.campaign.id)],
            },
        ],
        entities,
    }
}

fn build_citation(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    experiment_refs: &[EvidencePackExperimentRef],
    manuscript_target: &Option<ProgramContextPacketEvidenceTarget>,
    result_refs: &[EvidencePackResultRef],
) -> EvidencePackCitation {
    let mut related_identifiers = vec![
        EvidencePackRelatedIdentifier {
            relation_type: "IsPartOf".to_string(),
            identifier_type: "ProgramID".to_string(),
            value: binding.program.id.clone(),
        },
        EvidencePackRelatedIdentifier {
            relation_type: "IsDocumentedBy".to_string(),
            identifier_type: "CampaignID".to_string(),
            value: binding.campaign.id.clone(),
        },
    ];
    related_identifiers.extend(experiment_refs.iter().flat_map(|experiment| {
        [
            EvidencePackRelatedIdentifier {
                relation_type: "IsDescribedBy".to_string(),
                identifier_type: "Path".to_string(),
                value: experiment.spec_doc.clone(),
            },
            EvidencePackRelatedIdentifier {
                relation_type: "IsSupplementTo".to_string(),
                identifier_type: "Path".to_string(),
                value: experiment.results_doc.clone(),
            },
        ]
    }));
    related_identifiers.extend(result_refs.iter().filter_map(|result| {
        result.result_reference.as_ref().map(|reference| EvidencePackRelatedIdentifier {
            relation_type: "References".to_string(),
            identifier_type: "ResultRef".to_string(),
            value: reference.clone(),
        })
    }));
    if let Some(target) = manuscript_target.as_ref() {
        related_identifiers.push(EvidencePackRelatedIdentifier {
            relation_type: "IsReferencedBy".to_string(),
            identifier_type: "Path".to_string(),
            value: target.path.clone(),
        });
    }

    EvidencePackCitation {
        profile: EVIDENCE_PACK_CITATION_PROFILE.to_string(),
        title: format!(
            "{} evidence pack for {}",
            binding.campaign.title, binding.program.title
        ),
        creators: vec!["Beagle runtime".to_string()],
        publisher: "Beagle".to_string(),
        publication_year: Utc::now().year(),
        resource_type_general: "Collection".to_string(),
        version: EVIDENCE_PACK_VERSION.to_string(),
        subjects: vec![
            binding.program.id.clone(),
            binding.campaign.id.clone(),
            packet.active_workstream_id.clone(),
        ],
        descriptions: vec![
            binding.program.north_star.statement.clone(),
            binding.campaign.objective.clone(),
        ],
        related_identifiers,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        resolve_campaign_context_binding, ProgramContextPacketLatestResult,
        ProgramContextPacketMemoryHit,
    };

    fn sample_packet() -> ProgramContextPacket {
        ProgramContextPacket {
            packet_version: "test".to_string(),
            program_id: "beagle-physio-symbolic-exocortex".to_string(),
            program_title: "Beagle Physio-Symbolic Exocortex".to_string(),
            program_kind: "research-engineering-program".to_string(),
            north_star: "Make Beagle exocortical.".to_string(),
            campaign_id: "expedition-002-hrv-aware".to_string(),
            campaign_ids: vec![
                "darwin-hpc-governance".to_string(),
                "expedition-002-hrv-aware".to_string(),
            ],
            campaign_title: "Expedition 002 HRV-Aware Campaign".to_string(),
            campaign_kind: "live-experiment".to_string(),
            campaign_status: "canonical-live".to_string(),
            objective: "Run the HRV-aware vs blind line.".to_string(),
            experiment_ids: vec!["beagle_exp_002_hrv_aware_vs_blind".to_string()],
            workstream_ids: vec!["beagle-darwin-hpc-governance".to_string()],
            active_workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            governance_state: "canonical".to_string(),
            latest_results: vec![ProgramContextPacketLatestResult {
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                last_result: WorkstreamContextPacketLastResult {
                    available: true,
                    reference: None,
                    summary: Some(crate::WorkstreamContextPacketResultSummary {
                        job_id: 31,
                        state: "COMPLETED".to_string(),
                        run_label: "exp-run".to_string(),
                        profile_id: "cpu-batch-v1".to_string(),
                        node_list: "t560-proxmox".to_string(),
                        manifest_key: "manifest.json".to_string(),
                        source_phase: Some("B17.4".to_string()),
                        source_run_id: Some("b174".to_string()),
                    }),
                    manifest: Some(crate::WorkstreamContextPacketManifestSummary {
                        job_id: 31,
                        object_bucket: "darwin-hpc-artifacts".to_string(),
                        object_key: "artifact.bin".to_string(),
                        manifest_object_key: "artifact-manifest.json".to_string(),
                        profile_id: Some("cpu-batch-v1".to_string()),
                        run_label: Some("exp-run".to_string()),
                    }),
                    error: None,
                },
            }],
            latest_memory_hits: vec![ProgramContextPacketMemoryHit {
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                memory_id: Some("memory-1".to_string()),
                source: "codex".to_string(),
                conversation_id: Some("session-1".to_string()),
                turn_index: Some(1),
                role: Some("assistant".to_string()),
                snippet: "bounded memory".to_string(),
                timestamp: Some(Utc::now()),
                relevance: 0.9,
                tags: vec!["beagle".to_string()],
                domain: Some("beagle-program-os".to_string()),
                physio_snapshot: Some(WorkstreamContextPacketPhysioSnapshot {
                    hr: Some(76.0),
                    hrv_level: Some("balanced".to_string()),
                    spo2: Some(98.0),
                    timestamp: Some(Utc::now()),
                    source: Some("observer-smoke".to_string()),
                }),
            }],
            retrieval_context: None,
            latest_physio: Some(WorkstreamContextPacketPhysioSnapshot {
                hr: Some(76.0),
                hrv_level: Some("balanced".to_string()),
                spo2: Some(98.0),
                timestamp: Some(Utc::now()),
                source: Some("observer-smoke".to_string()),
            }),
            experiment_flags: Some(crate::WorkstreamContextPacketExperimentFlags {
                hrv_aware: Some(true),
                observer_enabled: Some(true),
                serendipity_enabled: Some(false),
                triad_enabled: Some(false),
                provider: Some("xai".to_string()),
                model: Some("grok-4-1-fast-reasoning".to_string()),
                experiment_id: Some("beagle_exp_002_hrv_aware_vs_blind".to_string()),
                condition: Some("hrv_aware".to_string()),
            }),
            recommended_next_recipe: Some(WorkstreamContextPacketRecipe {
                id: "operator_cpu_loop".to_string(),
                kind: "operator_cpu_loop".to_string(),
                summary: "Continue bounded operator loop".to_string(),
            }),
            evidence_targets: vec![ProgramContextPacketEvidenceTarget {
                scope: "campaign".to_string(),
                scope_id: "expedition-002-hrv-aware".to_string(),
                id: "expedition-002-results".to_string(),
                kind: "manuscript-results-doc".to_string(),
                path: "docs/darwin/hpc/BEAGLE_EXPEDITION_002_RESULTS.md".to_string(),
            }],
            manuscript_targets: vec![ProgramContextPacketEvidenceTarget {
                scope: "campaign".to_string(),
                scope_id: "expedition-002-hrv-aware".to_string(),
                id: "expedition-002-results".to_string(),
                kind: "manuscript-results-doc".to_string(),
                path: "docs/darwin/hpc/BEAGLE_EXPEDITION_002_RESULTS.md".to_string(),
            }],
        }
    }

    #[test]
    fn campaign_evidence_pack_collects_results_memory_physio_and_recipe_refs() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let response = build_campaign_evidence_pack(&binding, &sample_packet()).unwrap();

        assert_eq!(response.pack.program_id, "beagle-physio-symbolic-exocortex");
        assert_eq!(response.pack.campaign_id, "expedition-002-hrv-aware");
        assert_eq!(response.pack.result_refs.len(), 1);
        assert_eq!(response.pack.memory_refs.len(), 1);
        assert_eq!(response.pack.recipe_refs.len(), 1);
        assert!(!response.pack.physio_refs.is_empty());
        assert_eq!(
            response.pack.manuscript_target.as_ref().unwrap().id,
            "expedition-002-results"
        );
    }

    #[test]
    fn campaign_evidence_pack_derives_dataset_and_provenance_blocks() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let response = build_campaign_evidence_pack(&binding, &sample_packet()).unwrap();

        assert_eq!(response.pack.dataset_refs.len(), 1);
        assert!(response.pack.dataset_refs[0]
            .expected_files
            .iter()
            .any(|path| path.ends_with("analysis-summary.json")));
        assert_eq!(response.pack.provenance.profile, EVIDENCE_PACK_PROVENANCE_PROFILE);
        assert!(!response.pack.provenance.activities.is_empty());
        assert!(!response.pack.provenance.entities.is_empty());
        assert_eq!(response.pack.citation.profile, EVIDENCE_PACK_CITATION_PROFILE);
        assert_eq!(response.pack.citation.resource_type_general, "Collection");
    }
}
