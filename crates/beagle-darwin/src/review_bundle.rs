use crate::{
    CampaignClaimsResponse, ClaimRecord, EvidencePack, EvidencePackCitation,
    EvidencePackProvenance, EvidencePackProvenanceActivity, EvidencePackProvenanceEntity,
    EvidencePackRelatedIdentifier, EvidencePackResponse, ManuscriptPack, ManuscriptPackResponse,
    ProgramCampaignBinding, ProgramContextPacket, ProgramContextPacketEvidenceTarget,
};
use anyhow::anyhow;
use serde::Serialize;
use serde_json::{json, Value};

const REVIEW_BUNDLE_PHASE: &str = "B19.5";
const REVIEW_BUNDLE_VERSION: &str = "beagle-review-bundle-v1";
const REVIEW_BUNDLE_EXPORT_PROFILE: &str = "ro-crate-1.2-bounded";
const REVIEW_BUNDLE_ROOT_CONTEXT: &str = "https://w3id.org/ro/crate/1.1/context";

#[derive(Debug, Clone, Serialize)]
pub struct ReviewBundleResponse {
    pub status: String,
    pub phase: String,
    pub bundle: ReviewBundle,
}

#[derive(Debug, Clone, Serialize)]
pub struct ReviewBundle {
    pub bundle_version: String,
    pub export_profile: String,
    pub bundle_id: String,
    pub program_id: String,
    pub campaign_id: String,
    pub campaign_title: String,
    pub active_workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub readiness_state: String,
    pub manuscript_target: Option<ProgramContextPacketEvidenceTarget>,
    pub claim_ids: Vec<String>,
    pub claims: Vec<ClaimRecord>,
    pub evidence_pack_ref: String,
    pub manuscript_pack_ref: String,
    pub evidence_targets: Vec<ProgramContextPacketEvidenceTarget>,
    pub payload_manifest: Vec<ReviewBundlePayloadItem>,
    pub review_notes: Vec<String>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
    pub ro_crate_metadata: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct ReviewBundlePayloadItem {
    pub logical_path: String,
    pub payload_kind: String,
    pub reference: String,
    pub media_type: String,
}

pub fn build_campaign_review_bundle(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
    claims_response: &CampaignClaimsResponse,
    manuscript_response: &ManuscriptPackResponse,
) -> anyhow::Result<ReviewBundleResponse> {
    validate_alignment(
        binding,
        packet,
        evidence_response,
        claims_response,
        manuscript_response,
    )?;

    let evidence_pack_ref = format!("campaign:{}:evidence-pack", binding.campaign.id);
    let manuscript_pack_ref = format!("campaign:{}:manuscript-pack", binding.campaign.id);
    let claim_ref = format!("campaign:{}:claims", binding.campaign.id);
    let payload_manifest = build_payload_manifest(
        &evidence_pack_ref,
        &claim_ref,
        &manuscript_pack_ref,
        &evidence_response.pack,
        &claims_response.claims,
    );
    let review_notes = build_review_notes(binding, manuscript_response, &claims_response.claims);
    let provenance = build_review_bundle_provenance(
        &evidence_response.pack,
        &claims_response.claims,
        &payload_manifest,
    );
    let citation = build_review_bundle_citation(
        binding,
        &manuscript_response.pack,
        &payload_manifest,
        &claim_ref,
        &manuscript_pack_ref,
    );
    let bundle_id = format!("{}-review-bundle", binding.campaign.id);
    let ro_crate_metadata = build_ro_crate_metadata(
        binding,
        packet,
        &bundle_id,
        &evidence_pack_ref,
        &claim_ref,
        &manuscript_pack_ref,
        &payload_manifest,
        &citation,
        &manuscript_response.pack,
    );

    Ok(ReviewBundleResponse {
        status: "ok".to_string(),
        phase: REVIEW_BUNDLE_PHASE.to_string(),
        bundle: ReviewBundle {
            bundle_version: REVIEW_BUNDLE_VERSION.to_string(),
            export_profile: REVIEW_BUNDLE_EXPORT_PROFILE.to_string(),
            bundle_id,
            program_id: packet.program_id.clone(),
            campaign_id: packet.campaign_id.clone(),
            campaign_title: packet.campaign_title.clone(),
            active_workstream_id: packet.active_workstream_id.clone(),
            workspace_id: packet.workspace_id.clone(),
            session_id: packet.session_id.clone(),
            readiness_state: manuscript_response.pack.readiness_state.clone(),
            manuscript_target: manuscript_response.pack.manuscript_target.clone(),
            claim_ids: manuscript_response.pack.claim_ids.clone(),
            claims: claims_response.claims.clone(),
            evidence_pack_ref,
            manuscript_pack_ref,
            evidence_targets: packet.evidence_targets.clone(),
            payload_manifest,
            review_notes,
            provenance,
            citation,
            ro_crate_metadata,
        },
    })
}

fn validate_alignment(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
    claims_response: &CampaignClaimsResponse,
    manuscript_response: &ManuscriptPackResponse,
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
    if evidence_response.pack.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "evidence pack campaign {} does not match binding {}",
            evidence_response.pack.campaign_id,
            binding.campaign.id
        ));
    }
    if claims_response.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "claims campaign {} does not match binding {}",
            claims_response.campaign_id,
            binding.campaign.id
        ));
    }
    if manuscript_response.pack.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "manuscript pack campaign {} does not match binding {}",
            manuscript_response.pack.campaign_id,
            binding.campaign.id
        ));
    }

    Ok(())
}

fn build_payload_manifest(
    evidence_pack_ref: &str,
    claim_ref: &str,
    manuscript_pack_ref: &str,
    evidence_pack: &EvidencePack,
    claims: &[ClaimRecord],
) -> Vec<ReviewBundlePayloadItem> {
    let mut manifest = vec![
        ReviewBundlePayloadItem {
            logical_path: "ro-crate-metadata.json".to_string(),
            payload_kind: "ro-crate-metadata".to_string(),
            reference: "campaign:review-bundle:ro-crate-metadata".to_string(),
            media_type: "application/ld+json".to_string(),
        },
        ReviewBundlePayloadItem {
            logical_path: "evidence-pack.json".to_string(),
            payload_kind: "evidence-pack".to_string(),
            reference: evidence_pack_ref.to_string(),
            media_type: "application/json".to_string(),
        },
        ReviewBundlePayloadItem {
            logical_path: "claims.json".to_string(),
            payload_kind: "claim-layer".to_string(),
            reference: claim_ref.to_string(),
            media_type: "application/json".to_string(),
        },
        ReviewBundlePayloadItem {
            logical_path: "manuscript-pack.json".to_string(),
            payload_kind: "manuscript-pack".to_string(),
            reference: manuscript_pack_ref.to_string(),
            media_type: "application/json".to_string(),
        },
    ];

    manifest.extend(
        evidence_pack
            .dataset_refs
            .iter()
            .map(|dataset| ReviewBundlePayloadItem {
                logical_path: format!("datasets/{}/", dataset.dataset_id),
                payload_kind: "dataset-root".to_string(),
                reference: format!("dataset:{}", dataset.dataset_id),
                media_type: "inode/directory".to_string(),
            }),
    );
    manifest.extend(
        claims
            .iter()
            .map(|claim| ReviewBundlePayloadItem {
                logical_path: format!("claims/{}.json", claim.claim_id),
                payload_kind: "claim-record".to_string(),
                reference: format!("claim:{}", claim.claim_id),
                media_type: "application/json".to_string(),
            }),
    );

    manifest
}

fn build_review_notes(
    binding: &ProgramCampaignBinding,
    manuscript_response: &ManuscriptPackResponse,
    claims: &[ClaimRecord],
) -> Vec<String> {
    let mut notes = manuscript_response.pack.interpretive_notes.clone();
    notes.push(format!(
        "Campaign {} now exports a bounded review bundle that keeps claims, evidence and manuscript material together.",
        binding.campaign.id
    ));
    if claims
        .iter()
        .any(|claim| claim.confidence_mode == "human-judgment-pending")
    {
        notes.push(
            "The review bundle remains standards-grade in packaging, but human judgment is still pending for stronger manuscript claims."
                .to_string(),
        );
    }
    notes
}

fn build_review_bundle_provenance(
    evidence_pack: &EvidencePack,
    claims: &[ClaimRecord],
    payload_manifest: &[ReviewBundlePayloadItem],
) -> EvidencePackProvenance {
    let mut provenance = evidence_pack.provenance.clone();
    provenance.generator_component = "beagle-darwin/review_bundle".to_string();
    provenance.generator_phase = REVIEW_BUNDLE_PHASE.to_string();
    provenance.activities.push(EvidencePackProvenanceActivity {
        id: "review-bundle-export".to_string(),
        kind: "review-bundle-export".to_string(),
        used: vec![
            format!("evidence-pack:{}", evidence_pack.campaign_id),
            format!("campaign:{}:claims", evidence_pack.campaign_id),
            format!("campaign:{}:manuscript-pack", evidence_pack.campaign_id),
        ],
        generated: vec![
            format!("review-bundle:{}", evidence_pack.campaign_id),
            "ro-crate-metadata.json".to_string(),
        ],
    });
    provenance
        .entities
        .push(EvidencePackProvenanceEntity {
            id: format!("review-bundle:{}", evidence_pack.campaign_id),
            entity_kind: "review-bundle".to_string(),
            location: Some("review-bundle.json".to_string()),
        });
    provenance
        .entities
        .push(EvidencePackProvenanceEntity {
            id: "ro-crate-metadata.json".to_string(),
            entity_kind: "ro-crate-metadata".to_string(),
            location: Some("ro-crate-metadata.json".to_string()),
        });
    provenance.entities.extend(claims.iter().map(|claim| {
        EvidencePackProvenanceEntity {
            id: format!("claim:{}", claim.claim_id),
            entity_kind: "claim".to_string(),
            location: Some(format!("claims/{}.json", claim.claim_id)),
        }
    }));
    provenance.entities.extend(payload_manifest.iter().map(|payload| {
        EvidencePackProvenanceEntity {
            id: payload.reference.clone(),
            entity_kind: payload.payload_kind.clone(),
            location: Some(payload.logical_path.clone()),
        }
    }));
    provenance
}

fn build_review_bundle_citation(
    binding: &ProgramCampaignBinding,
    manuscript_pack: &ManuscriptPack,
    payload_manifest: &[ReviewBundlePayloadItem],
    claim_ref: &str,
    manuscript_pack_ref: &str,
) -> EvidencePackCitation {
    let mut citation = manuscript_pack.citation.clone();
    citation.title = format!("{} review bundle", binding.campaign.title);
    citation.resource_type_general = "Dataset".to_string();
    citation.version = REVIEW_BUNDLE_VERSION.to_string();
    citation.related_identifiers.push(EvidencePackRelatedIdentifier {
        relation_type: "HasMetadata".to_string(),
        identifier_type: "Path".to_string(),
        value: "ro-crate-metadata.json".to_string(),
    });
    citation.related_identifiers.push(EvidencePackRelatedIdentifier {
        relation_type: "IsSupplementTo".to_string(),
        identifier_type: "ClaimLayerRef".to_string(),
        value: claim_ref.to_string(),
    });
    citation.related_identifiers.push(EvidencePackRelatedIdentifier {
        relation_type: "IsSupplementTo".to_string(),
        identifier_type: "ManuscriptPackRef".to_string(),
        value: manuscript_pack_ref.to_string(),
    });
    citation.related_identifiers.extend(payload_manifest.iter().map(|payload| {
        EvidencePackRelatedIdentifier {
            relation_type: "HasPart".to_string(),
            identifier_type: "Path".to_string(),
            value: payload.logical_path.clone(),
        }
    }));
    citation
}

#[allow(clippy::too_many_arguments)]
fn build_ro_crate_metadata(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    bundle_id: &str,
    evidence_pack_ref: &str,
    claim_ref: &str,
    manuscript_pack_ref: &str,
    payload_manifest: &[ReviewBundlePayloadItem],
    citation: &EvidencePackCitation,
    manuscript_pack: &ManuscriptPack,
) -> Value {
    let payload_graph = payload_manifest
        .iter()
        .filter(|payload| {
            !matches!(
                payload.logical_path.as_str(),
                "ro-crate-metadata.json"
                    | "evidence-pack.json"
                    | "claims.json"
                    | "manuscript-pack.json"
            )
        })
        .map(|payload| {
            json!({
                "@id": payload.logical_path,
                "@type": "File",
                "encodingFormat": payload.media_type,
                "name": payload.payload_kind,
                "identifier": payload.reference,
            })
        })
        .collect::<Vec<_>>();

    let mut graph = vec![
        json!({
            "@id": "ro-crate-metadata.json",
            "@type": "CreativeWork",
            "about": { "@id": "./" },
            "encodingFormat": "application/ld+json"
        }),
        json!({
            "@id": "./",
            "@type": "Dataset",
            "name": format!("{} review bundle", binding.campaign.title),
            "identifier": bundle_id,
            "mainEntity": { "@id": "#review-bundle" },
            "about": { "@id": "#campaign" },
            "hasPart": payload_manifest.iter().map(|payload| json!({ "@id": payload.logical_path })).collect::<Vec<_>>(),
            "keywords": citation.subjects,
            "description": format!("Bounded review bundle export for campaign {} within program {}.", binding.campaign.id, binding.program.id),
        }),
        json!({
            "@id": "#review-bundle",
            "@type": "CreativeWork",
            "name": format!("{} review bundle", binding.campaign.title),
            "identifier": bundle_id,
            "version": REVIEW_BUNDLE_VERSION,
            "isPartOf": { "@id": "#program" },
            "about": { "@id": "#campaign" },
            "subjectOf": { "@id": "manuscript-pack.json" },
            "creativeWorkStatus": manuscript_pack.readiness_state,
            "mentions": manuscript_pack.claim_ids.iter().map(|claim_id| json!({ "@id": format!("#claim:{claim_id}") })).collect::<Vec<_>>(),
        }),
        json!({
            "@id": "#program",
            "@type": "ResearchProject",
            "name": binding.program.title,
            "identifier": binding.program.id,
            "description": binding.program.north_star.statement,
        }),
        json!({
            "@id": "#campaign",
            "@type": "Project",
            "name": binding.campaign.title,
            "identifier": binding.campaign.id,
            "description": binding.campaign.objective,
            "keywords": [packet.active_workstream_id, manuscript_pack.readiness_state],
        }),
        json!({
            "@id": "evidence-pack.json",
            "@type": "Dataset",
            "name": "Beagle evidence pack",
            "identifier": evidence_pack_ref,
            "encodingFormat": "application/json"
        }),
        json!({
            "@id": "claims.json",
            "@type": "CreativeWork",
            "name": "Beagle claim layer",
            "identifier": claim_ref,
            "encodingFormat": "application/json"
        }),
        json!({
            "@id": "manuscript-pack.json",
            "@type": "CreativeWork",
            "name": "Beagle manuscript pack",
            "identifier": manuscript_pack_ref,
            "encodingFormat": "application/json"
        }),
    ];

    graph.extend(
        manuscript_pack
            .claims
            .iter()
            .map(|claim| {
                json!({
                    "@id": format!("#claim:{}", claim.claim_id),
                    "@type": "CreativeWork",
                    "name": claim.claim_text,
                    "identifier": claim.claim_id,
                    "creativeWorkStatus": claim.claim_state,
                    "about": { "@id": "#campaign" },
                    "subjectOf": { "@id": "manuscript-pack.json" },
                })
            }),
    );
    graph.extend(payload_graph);
    if let Some(target) = manuscript_pack.manuscript_target.as_ref() {
        graph.push(json!({
            "@id": format!("#target:{}", target.id),
            "@type": "CreativeWork",
            "name": target.id,
            "identifier": target.id,
            "url": target.path,
        }));
    }

    json!({
        "@context": [
            REVIEW_BUNDLE_ROOT_CONTEXT,
            {
                "beagle": "https://beagle.local/schema#",
                "creativeWorkStatus": "https://schema.org/creativeWorkStatus"
            }
        ],
        "@graph": graph
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        build_campaign_claims, build_campaign_evidence_pack, build_campaign_manuscript_pack,
        resolve_campaign_context_binding, ProgramContextPacketLatestResult,
        ProgramContextPacketMemoryHit, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketLastResult, WorkstreamContextPacketManifestSummary,
        WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
        WorkstreamContextPacketResultSummary,
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
    fn campaign_review_bundle_keeps_claims_evidence_and_manuscript_linked() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let packet = sample_packet();
        let evidence = build_campaign_evidence_pack(&binding, &packet).unwrap();
        let claims = build_campaign_claims(&binding, &packet, &evidence).unwrap();
        let manuscript = build_campaign_manuscript_pack(&binding, &packet, &evidence).unwrap();

        let review =
            build_campaign_review_bundle(&binding, &packet, &evidence, &claims, &manuscript)
                .unwrap();

        assert_eq!(review.bundle.program_id, "beagle-physio-symbolic-exocortex");
        assert_eq!(review.bundle.campaign_id, "expedition-002-hrv-aware");
        assert_eq!(review.bundle.claims.len(), 3);
        assert_eq!(
            review.bundle.readiness_state,
            "claim-linked-human-eval-pending"
        );
        assert_eq!(
            review.bundle.evidence_pack_ref,
            "campaign:expedition-002-hrv-aware:evidence-pack"
        );
        assert_eq!(
            review.bundle.manuscript_pack_ref,
            "campaign:expedition-002-hrv-aware:manuscript-pack"
        );
    }

    #[test]
    fn campaign_review_bundle_derives_rocrate_and_citation_ready_blocks() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let packet = sample_packet();
        let evidence = build_campaign_evidence_pack(&binding, &packet).unwrap();
        let claims = build_campaign_claims(&binding, &packet, &evidence).unwrap();
        let manuscript = build_campaign_manuscript_pack(&binding, &packet, &evidence).unwrap();

        let review =
            build_campaign_review_bundle(&binding, &packet, &evidence, &claims, &manuscript)
                .unwrap();

        assert_eq!(review.bundle.export_profile, REVIEW_BUNDLE_EXPORT_PROFILE);
        assert!(review.bundle.payload_manifest.iter().any(|payload| {
            payload.logical_path == "ro-crate-metadata.json"
                && payload.media_type == "application/ld+json"
        }));
        assert_eq!(review.bundle.citation.profile, "datacite-4.7-ready");
        assert_eq!(review.bundle.provenance.profile, "w3c-prov-bounded");
        let graph = review.bundle.ro_crate_metadata["@graph"].as_array().unwrap();
        assert!(graph.len() >= 8);
        assert_eq!(
            graph.iter()
                .filter(|node| node["@id"] == "ro-crate-metadata.json")
                .count(),
            1
        );
        assert_eq!(
            graph.iter().filter(|node| node["@id"] == "evidence-pack.json").count(),
            1
        );
    }
}
