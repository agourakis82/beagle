use crate::{
    EvidencePack, EvidencePackCitation, EvidencePackProvenance, EvidencePackProvenanceActivity,
    EvidencePackProvenanceEntity, EvidencePackResponse, ProgramCampaignBinding,
    ProgramContextPacket, ProgramContextPacketEvidenceTarget,
};
use anyhow::anyhow;
use serde::Serialize;

const CLAIM_LAYER_PHASE: &str = "B19.4";
const CLAIM_SCHEMA_VERSION: &str = "beagle-claim-v1";
const MANUSCRIPT_PACK_VERSION: &str = "beagle-manuscript-pack-v1";

#[derive(Debug, Clone, Serialize)]
pub struct CampaignClaimsResponse {
    pub status: String,
    pub phase: String,
    pub schema_version: String,
    pub program_id: String,
    pub campaign_id: String,
    pub manuscript_target: Option<ProgramContextPacketEvidenceTarget>,
    pub claims: Vec<ClaimRecord>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ClaimRecord {
    pub claim_id: String,
    pub campaign_id: String,
    pub manuscript_target: Option<String>,
    pub claim_kind: String,
    pub claim_state: String,
    pub confidence_mode: String,
    pub claim_text: String,
    pub supports: Vec<String>,
    pub contradicts: Vec<String>,
    pub evidence_refs: Vec<String>,
    pub gaps: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ManuscriptPackResponse {
    pub status: String,
    pub phase: String,
    pub pack: ManuscriptPack,
}

#[derive(Debug, Clone, Serialize)]
pub struct ManuscriptPack {
    pub pack_version: String,
    pub pack_id: String,
    pub evidence_pack_ref: String,
    pub program_id: String,
    pub campaign_id: String,
    pub campaign_title: String,
    pub manuscript_target: Option<ProgramContextPacketEvidenceTarget>,
    pub title: String,
    pub hypothesis: String,
    pub active_workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub claim_ids: Vec<String>,
    pub claims: Vec<ClaimRecord>,
    pub interpretive_notes: Vec<String>,
    pub gaps: Vec<String>,
    pub readiness_state: String,
    pub evidence_targets: Vec<ProgramContextPacketEvidenceTarget>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
}

pub fn build_campaign_claims(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
) -> anyhow::Result<CampaignClaimsResponse> {
    validate_alignment(binding, packet, evidence_response)?;

    let claims = assemble_claims(binding, packet, &evidence_response.pack);

    Ok(CampaignClaimsResponse {
        status: "ok".to_string(),
        phase: CLAIM_LAYER_PHASE.to_string(),
        schema_version: CLAIM_SCHEMA_VERSION.to_string(),
        program_id: packet.program_id.clone(),
        campaign_id: packet.campaign_id.clone(),
        manuscript_target: evidence_response.pack.manuscript_target.clone(),
        claims,
    })
}

pub fn build_campaign_manuscript_pack(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
) -> anyhow::Result<ManuscriptPackResponse> {
    validate_alignment(binding, packet, evidence_response)?;

    let claims = assemble_claims(binding, packet, &evidence_response.pack);
    let gaps = collect_manuscript_gaps(&claims, &evidence_response.pack.manuscript_target);
    let readiness_state = manuscript_readiness_state(&gaps);
    let interpretive_notes = collect_interpretive_notes(binding, &claims, &gaps);
    let evidence_pack_ref = format!("campaign:{}:evidence-pack", binding.campaign.id);

    Ok(ManuscriptPackResponse {
        status: "ok".to_string(),
        phase: CLAIM_LAYER_PHASE.to_string(),
        pack: ManuscriptPack {
            pack_version: MANUSCRIPT_PACK_VERSION.to_string(),
            pack_id: format!("{}-manuscript-pack", binding.campaign.id),
            evidence_pack_ref: evidence_pack_ref.clone(),
            program_id: packet.program_id.clone(),
            campaign_id: packet.campaign_id.clone(),
            campaign_title: packet.campaign_title.clone(),
            manuscript_target: evidence_response.pack.manuscript_target.clone(),
            title: manuscript_title(binding),
            hypothesis: manuscript_hypothesis(binding),
            active_workstream_id: packet.active_workstream_id.clone(),
            workspace_id: packet.workspace_id.clone(),
            session_id: packet.session_id.clone(),
            claim_ids: claims.iter().map(|claim| claim.claim_id.clone()).collect(),
            claims: claims.clone(),
            interpretive_notes,
            gaps,
            readiness_state,
            evidence_targets: packet.evidence_targets.clone(),
            provenance: build_manuscript_provenance(&evidence_response.pack, &claims),
            citation: build_manuscript_citation(
                &evidence_response.pack,
                binding,
                &claims,
                &evidence_pack_ref,
            ),
        },
    })
}

fn validate_alignment(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
) -> anyhow::Result<()> {
    if packet.program_id != binding.program.id {
        return Err(anyhow!(
            "program packet {} does not match binding {}",
            packet.program_id,
            binding.program.id
        ));
    }
    if packet.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "campaign packet {} does not match binding {}",
            packet.campaign_id,
            binding.campaign.id
        ));
    }
    if evidence_response.pack.program_id != binding.program.id {
        return Err(anyhow!(
            "evidence pack program {} does not match binding {}",
            evidence_response.pack.program_id,
            binding.program.id
        ));
    }
    if evidence_response.pack.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "evidence pack campaign {} does not match binding {}",
            evidence_response.pack.campaign_id,
            binding.campaign.id
        ));
    }

    Ok(())
}

fn assemble_claims(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_pack: &EvidencePack,
) -> Vec<ClaimRecord> {
    let manuscript_target = evidence_pack.manuscript_target.as_ref().map(|target| target.id.clone());
    let manuscript_ref = manuscript_target
        .as_ref()
        .map(|target| format!("manuscript:{target}"))
        .into_iter()
        .collect::<Vec<_>>();

    let operational_claim_id = format!("{}-operational-evidence-pack", binding.campaign.id);
    let physio_claim_id = format!("{}-physio-context-bound", binding.campaign.id);
    let interpretive_claim_id = format!("{}-campaign-claim-readiness", binding.campaign.id);

    let mut claims = vec![ClaimRecord {
        claim_id: operational_claim_id.clone(),
        campaign_id: binding.campaign.id.clone(),
        manuscript_target: manuscript_target.clone(),
        claim_kind: "operational_evidence_pack".to_string(),
        claim_state: if evidence_pack.result_refs.is_empty()
            || evidence_pack.memory_refs.is_empty()
            || evidence_pack.recipe_refs.is_empty()
        {
            "unsupported".to_string()
        } else {
            "supported".to_string()
        },
        confidence_mode: "operational-evidence".to_string(),
        claim_text: format!(
            "Campaign {} assembles a bounded evidence pack that links results, memory, recipe and provenance under one canonical packet.",
            binding.campaign.id
        ),
        supports: manuscript_ref.clone(),
        contradicts: Vec::new(),
        evidence_refs: operational_evidence_refs(evidence_pack),
        gaps: Vec::new(),
    }];

    if !evidence_pack.physio_refs.is_empty() {
        claims.push(ClaimRecord {
            claim_id: physio_claim_id.clone(),
            campaign_id: binding.campaign.id.clone(),
            manuscript_target: manuscript_target.clone(),
            claim_kind: "physio_context_binding".to_string(),
            claim_state: "supported".to_string(),
            confidence_mode: if packet
                .experiment_flags
                .as_ref()
                .and_then(|flags| flags.hrv_aware)
                == Some(true)
            {
                "operational-plus-physio".to_string()
            } else {
                "operational-evidence".to_string()
            },
            claim_text: format!(
                "Campaign {} keeps physiological context attached to live evidence and available for campaign-level interpretation.",
                binding.campaign.id
            ),
            supports: vec![format!("claim:{operational_claim_id}")],
            contradicts: Vec::new(),
            evidence_refs: physio_evidence_refs(evidence_pack),
            gaps: Vec::new(),
        });
    }

    claims.push(ClaimRecord {
        claim_id: interpretive_claim_id,
        campaign_id: binding.campaign.id.clone(),
        manuscript_target,
        claim_kind: "manuscript_readiness".to_string(),
        claim_state: interpretive_claim_state(binding),
        confidence_mode: interpretive_confidence_mode(binding),
        claim_text: interpretive_claim_text(binding),
        supports: manuscript_ref,
        contradicts: Vec::new(),
        evidence_refs: interpretive_evidence_refs(evidence_pack),
        gaps: interpretive_gaps(binding),
    });

    claims
}

fn operational_evidence_refs(evidence_pack: &EvidencePack) -> Vec<String> {
    let mut refs = vec![format!("evidence-pack:{}", evidence_pack.campaign_id)];
    refs.extend(evidence_pack.result_refs.iter().filter_map(|result| {
        result
            .result_reference
            .clone()
            .or_else(|| result.manifest_key.clone().map(|key| format!("manifest:{key}")))
    }));
    refs.extend(
        evidence_pack
            .memory_refs
            .iter()
            .filter_map(|memory| memory.memory_id.as_ref().map(|id| format!("memory:{id}"))),
    );
    refs.extend(
        evidence_pack
            .recipe_refs
            .iter()
            .map(|recipe| format!("recipe:{}", recipe.recipe_id)),
    );
    refs
}

fn physio_evidence_refs(evidence_pack: &EvidencePack) -> Vec<String> {
    let mut refs = evidence_pack
        .physio_refs
        .iter()
        .enumerate()
        .map(|(index, physio)| {
            format!(
                "physio:{}:{}",
                physio.scope,
                physio
                    .memory_id
                    .clone()
                    .unwrap_or_else(|| index.to_string())
            )
        })
        .collect::<Vec<_>>();
    refs.extend(
        evidence_pack
            .experiment_refs
            .iter()
            .map(|experiment| format!("experiment:{}", experiment.experiment_id)),
    );
    refs
}

fn interpretive_evidence_refs(evidence_pack: &EvidencePack) -> Vec<String> {
    let mut refs = vec![format!("evidence-pack:{}", evidence_pack.campaign_id)];
    refs.extend(
        evidence_pack
            .experiment_refs
            .iter()
            .map(|experiment| format!("experiment:{}", experiment.experiment_id)),
    );
    refs.extend(
        evidence_pack
            .result_refs
            .iter()
            .filter_map(|result| result.result_reference.clone()),
    );
    refs
}

fn interpretive_claim_state(binding: &ProgramCampaignBinding) -> String {
    if binding.campaign.id == "expedition-002-hrv-aware" {
        "partially_supported".to_string()
    } else {
        "supported".to_string()
    }
}

fn interpretive_confidence_mode(binding: &ProgramCampaignBinding) -> String {
    if binding.campaign.id == "expedition-002-hrv-aware" {
        "human-judgment-pending".to_string()
    } else {
        "bounded-review".to_string()
    }
}

fn interpretive_claim_text(binding: &ProgramCampaignBinding) -> String {
    if binding.campaign.id == "expedition-002-hrv-aware" {
        "Expedition 002 has reviewable operational evidence for the HRV-aware versus blind comparison, but a frozen human-judgment layer is still pending.".to_string()
    } else {
        format!(
            "Campaign {} has enough bounded evidence to support a first reviewable manuscript pack.",
            binding.campaign.id
        )
    }
}

fn interpretive_gaps(binding: &ProgramCampaignBinding) -> Vec<String> {
    if binding.campaign.id == "expedition-002-hrv-aware" {
        vec!["human_judgment_layer_pending_go".to_string()]
    } else {
        Vec::new()
    }
}

fn collect_manuscript_gaps(
    claims: &[ClaimRecord],
    manuscript_target: &Option<ProgramContextPacketEvidenceTarget>,
) -> Vec<String> {
    let mut gaps = claims
        .iter()
        .flat_map(|claim| claim.gaps.clone())
        .collect::<Vec<_>>();
    if manuscript_target.is_none() {
        gaps.push("manuscript_target_not_declared".to_string());
    }
    gaps.sort();
    gaps.dedup();
    gaps
}

fn manuscript_readiness_state(gaps: &[String]) -> String {
    if gaps.iter().any(|gap| gap == "human_judgment_layer_pending_go") {
        "claim-linked-human-eval-pending".to_string()
    } else if gaps.is_empty() {
        "reviewable".to_string()
    } else {
        "claim-linked-with-gaps".to_string()
    }
}

fn collect_interpretive_notes(
    binding: &ProgramCampaignBinding,
    claims: &[ClaimRecord],
    gaps: &[String],
) -> Vec<String> {
    let mut notes = vec![format!(
        "Campaign {} is now expressible as explicit reviewable claims linked to bounded evidence.",
        binding.campaign.id
    )];
    if claims.iter().any(|claim| claim.claim_kind == "physio_context_binding") {
        notes.push("Physiological context remains part of the manuscript-facing evidence trail.".to_string());
    }
    if gaps.iter().any(|gap| gap == "human_judgment_layer_pending_go") {
        notes.push("Human judgment remains the main remaining blocker for stronger interpretive claims.".to_string());
    }
    notes
}

fn manuscript_title(binding: &ProgramCampaignBinding) -> String {
    if binding.campaign.id == "expedition-002-hrv-aware" {
        "Expedition 002: HRV-aware versus blind execution in Beagle".to_string()
    } else {
        format!("{} manuscript pack", binding.campaign.title)
    }
}

fn manuscript_hypothesis(binding: &ProgramCampaignBinding) -> String {
    if binding.campaign.id == "expedition-002-hrv-aware" {
        "Physiological awareness can be introduced into the Beagle pipeline without breaking operational coherence, creating a basis for later human-evaluated quality gains.".to_string()
    } else {
        binding.campaign.objective.clone()
    }
}

fn build_manuscript_provenance(
    evidence_pack: &EvidencePack,
    claims: &[ClaimRecord],
) -> EvidencePackProvenance {
    let mut provenance = evidence_pack.provenance.clone();
    provenance.generator_component = "beagle-darwin/claim_layer".to_string();
    provenance.generator_phase = CLAIM_LAYER_PHASE.to_string();
    provenance.activities.push(EvidencePackProvenanceActivity {
        id: "claim-layer-assembly".to_string(),
        kind: "claim-assembly".to_string(),
        used: vec![format!("evidence-pack:{}", evidence_pack.campaign_id)],
        generated: claims
            .iter()
            .map(|claim| format!("claim:{}", claim.claim_id))
            .chain(std::iter::once(format!(
                "manuscript-pack:{}",
                evidence_pack.campaign_id
            )))
            .collect(),
    });
    provenance.entities.extend(claims.iter().map(|claim| EvidencePackProvenanceEntity {
        id: format!("claim:{}", claim.claim_id),
        entity_kind: "claim".to_string(),
        location: claim.manuscript_target.clone(),
    }));
    provenance.entities.push(EvidencePackProvenanceEntity {
        id: format!("manuscript-pack:{}", evidence_pack.campaign_id),
        entity_kind: "manuscript-pack".to_string(),
        location: evidence_pack.manuscript_target.as_ref().map(|target| target.path.clone()),
    });
    provenance
}

fn build_manuscript_citation(
    evidence_pack: &EvidencePack,
    binding: &ProgramCampaignBinding,
    claims: &[ClaimRecord],
    evidence_pack_ref: &str,
) -> EvidencePackCitation {
    let mut citation = evidence_pack.citation.clone();
    citation.title = manuscript_title(binding);
    citation.resource_type_general = "Text".to_string();
    citation.version = MANUSCRIPT_PACK_VERSION.to_string();
    citation.related_identifiers.push(crate::EvidencePackRelatedIdentifier {
        relation_type: "References".to_string(),
        identifier_type: "EvidencePackRef".to_string(),
        value: evidence_pack_ref.to_string(),
    });
    citation.related_identifiers.extend(claims.iter().map(|claim| crate::EvidencePackRelatedIdentifier {
        relation_type: "IsReviewedBy".to_string(),
        identifier_type: "ClaimID".to_string(),
        value: claim.claim_id.clone(),
    }));
    citation
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        build_campaign_evidence_pack, resolve_campaign_context_binding,
        ProgramContextPacketEvidenceTarget,
        ProgramContextPacketLatestResult, ProgramContextPacketMemoryHit,
        WorkstreamContextPacketExperimentFlags, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketManifestSummary, WorkstreamContextPacketPhysioSnapshot,
        WorkstreamContextPacketRecipe, WorkstreamContextPacketResultSummary,
    };
    use chrono::Utc;

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
                    summary: Some(WorkstreamContextPacketResultSummary {
                        job_id: 31,
                        state: "COMPLETED".to_string(),
                        run_label: "exp-run".to_string(),
                        profile_id: "cpu-batch-v1".to_string(),
                        node_list: "t560-proxmox".to_string(),
                        manifest_key: "manifest.json".to_string(),
                        source_phase: Some("B17.4".to_string()),
                        source_run_id: Some("b174".to_string()),
                    }),
                    manifest: Some(WorkstreamContextPacketManifestSummary {
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
    fn campaign_claims_link_evidence_to_reviewable_claims() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let packet = sample_packet();
        let evidence = build_campaign_evidence_pack(&binding, &packet).unwrap();
        let response = build_campaign_claims(&binding, &packet, &evidence).unwrap();

        assert_eq!(response.campaign_id, "expedition-002-hrv-aware");
        assert!(response.claims.len() >= 3);
        assert!(response
            .claims
            .iter()
            .any(|claim| claim.confidence_mode == "human-judgment-pending"));
        assert!(response
            .claims
            .iter()
            .all(|claim| !claim.evidence_refs.is_empty()));
    }

    #[test]
    fn campaign_manuscript_pack_stays_claim_linked_and_gap_explicit() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let packet = sample_packet();
        let evidence = build_campaign_evidence_pack(&binding, &packet).unwrap();
        let response = build_campaign_manuscript_pack(&binding, &packet, &evidence).unwrap();

        assert_eq!(response.pack.campaign_id, "expedition-002-hrv-aware");
        assert_eq!(response.pack.claims.len(), response.pack.claim_ids.len());
        assert_eq!(
            response.pack.readiness_state,
            "claim-linked-human-eval-pending"
        );
        assert!(response
            .pack
            .gaps
            .contains(&"human_judgment_layer_pending_go".to_string()));
        assert_eq!(response.pack.citation.resource_type_general, "Text");
        assert!(response
            .pack
            .provenance
            .activities
            .iter()
            .any(|activity| activity.id == "claim-layer-assembly"));
    }
}
