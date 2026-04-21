use crate::{
    CampaignClaimsResponse, ClaimRecord, EvidencePack, EvidencePackCitation,
    EvidencePackProvenance, EvidencePackResponse, ManuscriptPack, ManuscriptPackResponse,
    ProgramCampaignBinding, ProgramContextPacket, ProgramContextPacketEvidenceTarget,
    ReviewBundleResponse,
};
use anyhow::anyhow;
use serde::Serialize;

const JATS_MANUSCRIPT_PHASE: &str = "B20.1";
const JATS_MANUSCRIPT_VERSION: &str = "beagle-jats-manuscript-pack-v1";
const JATS_PROFILE: &str = "jats-1.4-ready";
const JATS_ARTICLE_TYPE: &str = "research-article";

#[derive(Debug, Clone, Serialize)]
pub struct JatsManuscriptPackResponse {
    pub status: String,
    pub phase: String,
    pub pack: JatsManuscriptPack,
}

#[derive(Debug, Clone, Serialize)]
pub struct JatsManuscriptPack {
    pub pack_version: String,
    pub jats_profile: String,
    pub article_type: String,
    pub pack_id: String,
    pub program_id: String,
    pub campaign_id: String,
    pub campaign_title: String,
    pub active_workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub manuscript_target: Option<ProgramContextPacketEvidenceTarget>,
    pub title: String,
    pub abstract_text: String,
    pub hypothesis: String,
    pub readiness_state: String,
    pub claim_ids: Vec<String>,
    pub evidence_pack_ref: String,
    pub review_bundle_ref: String,
    pub section_map: Vec<JatsManuscriptSection>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
    pub jats_xml: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct JatsManuscriptSection {
    pub section_id: String,
    pub section_type: String,
    pub title: String,
    pub body: String,
    pub claim_refs: Vec<String>,
    pub evidence_refs: Vec<String>,
    pub provenance_refs: Vec<String>,
    pub citation_refs: Vec<String>,
}

pub fn build_campaign_jats_manuscript_pack(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
    claims_response: &CampaignClaimsResponse,
    manuscript_response: &ManuscriptPackResponse,
    review_bundle_response: &ReviewBundleResponse,
) -> anyhow::Result<JatsManuscriptPackResponse> {
    validate_alignment(
        binding,
        packet,
        evidence_response,
        claims_response,
        manuscript_response,
        review_bundle_response,
    )?;

    let review_bundle_ref = format!("campaign:{}:review-bundle", binding.campaign.id);
    let abstract_text = build_abstract(packet, &evidence_response.pack, &manuscript_response.pack);
    let section_map = build_section_map(
        binding,
        packet,
        &evidence_response.pack,
        &claims_response.claims,
        &manuscript_response.pack,
        &review_bundle_ref,
    );

    let mut pack = JatsManuscriptPack {
        pack_version: JATS_MANUSCRIPT_VERSION.to_string(),
        jats_profile: JATS_PROFILE.to_string(),
        article_type: JATS_ARTICLE_TYPE.to_string(),
        pack_id: format!("{}-jats-manuscript-pack", binding.campaign.id),
        program_id: packet.program_id.clone(),
        campaign_id: packet.campaign_id.clone(),
        campaign_title: packet.campaign_title.clone(),
        active_workstream_id: packet.active_workstream_id.clone(),
        workspace_id: packet.workspace_id.clone(),
        session_id: packet.session_id.clone(),
        manuscript_target: manuscript_response.pack.manuscript_target.clone(),
        title: manuscript_response.pack.title.clone(),
        abstract_text,
        hypothesis: manuscript_response.pack.hypothesis.clone(),
        readiness_state: manuscript_response.pack.readiness_state.clone(),
        claim_ids: manuscript_response.pack.claim_ids.clone(),
        evidence_pack_ref: manuscript_response.pack.evidence_pack_ref.clone(),
        review_bundle_ref,
        section_map,
        provenance: manuscript_response.pack.provenance.clone(),
        citation: manuscript_response.pack.citation.clone(),
        jats_xml: String::new(),
    };
    pack.jats_xml = build_jats_xml(&pack);

    Ok(JatsManuscriptPackResponse {
        status: "ok".to_string(),
        phase: JATS_MANUSCRIPT_PHASE.to_string(),
        pack,
    })
}

fn validate_alignment(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_response: &EvidencePackResponse,
    claims_response: &CampaignClaimsResponse,
    manuscript_response: &ManuscriptPackResponse,
    review_bundle_response: &ReviewBundleResponse,
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
            "claim layer campaign {} does not match binding {}",
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
    if review_bundle_response.bundle.campaign_id != binding.campaign.id {
        return Err(anyhow!(
            "review bundle campaign {} does not match binding {}",
            review_bundle_response.bundle.campaign_id,
            binding.campaign.id
        ));
    }

    Ok(())
}

fn build_abstract(
    packet: &ProgramContextPacket,
    evidence_pack: &EvidencePack,
    manuscript_pack: &ManuscriptPack,
) -> String {
    let physio_clause = if evidence_pack.physio_refs.is_empty() {
        "Physiological context was not available in the bounded evidence set.".to_string()
    } else {
        format!(
            "Physiological context was preserved across {} bounded evidence references.",
            evidence_pack.physio_refs.len()
        )
    };
    let experiment_clause = packet
        .experiment_flags
        .as_ref()
        .and_then(|flags| flags.experiment_id.as_ref())
        .map(|experiment_id| format!("The active experimental line is {experiment_id}."))
        .unwrap_or_else(|| "No active experiment flag was attached at packet assembly time.".to_string());

    format!(
        "{} {} {} The current readiness state remains {}.",
        manuscript_pack.hypothesis,
        physio_clause,
        experiment_clause,
        manuscript_pack.readiness_state
    )
}

fn build_section_map(
    binding: &ProgramCampaignBinding,
    packet: &ProgramContextPacket,
    evidence_pack: &EvidencePack,
    claims: &[ClaimRecord],
    manuscript_pack: &ManuscriptPack,
    review_bundle_ref: &str,
) -> Vec<JatsManuscriptSection> {
    let claim_refs = claims
        .iter()
        .map(|claim| format!("claim:{}", claim.claim_id))
        .collect::<Vec<_>>();
    let provenance_refs = manuscript_pack
        .provenance
        .activities
        .iter()
        .map(|activity| format!("prov:activity:{}", activity.id))
        .collect::<Vec<_>>();
    let citation_refs = manuscript_pack
        .citation
        .related_identifiers
        .iter()
        .map(|identifier| identifier.value.clone())
        .collect::<Vec<_>>();

    vec![
        JatsManuscriptSection {
            section_id: "abstract".to_string(),
            section_type: "abstract".to_string(),
            title: "Abstract".to_string(),
            body: build_abstract(packet, evidence_pack, manuscript_pack),
            claim_refs: claim_refs.clone(),
            evidence_refs: vec![manuscript_pack.evidence_pack_ref.clone(), review_bundle_ref.to_string()],
            provenance_refs: provenance_refs.clone(),
            citation_refs: citation_refs.clone(),
        },
        JatsManuscriptSection {
            section_id: "introduction".to_string(),
            section_type: "introduction".to_string(),
            title: "Introduction".to_string(),
            body: format!(
                "This manuscript package serves campaign {} inside program {}. The bounded objective is: {}.",
                binding.campaign.id,
                binding.program.id,
                binding.campaign.objective
            ),
            claim_refs: claim_refs.clone(),
            evidence_refs: vec![manuscript_pack.evidence_pack_ref.clone()],
            provenance_refs: provenance_refs.clone(),
            citation_refs: citation_refs.clone(),
        },
        JatsManuscriptSection {
            section_id: "methods".to_string(),
            section_type: "methods".to_string(),
            title: "Methods".to_string(),
            body: build_methods_body(packet, evidence_pack),
            claim_refs: claim_refs.clone(),
            evidence_refs: methods_evidence_refs(evidence_pack),
            provenance_refs: provenance_refs.clone(),
            citation_refs: citation_refs.clone(),
        },
        JatsManuscriptSection {
            section_id: "results".to_string(),
            section_type: "results".to_string(),
            title: "Results".to_string(),
            body: build_results_body(claims, evidence_pack, manuscript_pack),
            claim_refs: claim_refs.clone(),
            evidence_refs: results_evidence_refs(evidence_pack),
            provenance_refs: provenance_refs.clone(),
            citation_refs: citation_refs.clone(),
        },
        JatsManuscriptSection {
            section_id: "discussion".to_string(),
            section_type: "discussion".to_string(),
            title: "Discussion".to_string(),
            body: build_discussion_body(manuscript_pack),
            claim_refs: claim_refs.clone(),
            evidence_refs: vec![review_bundle_ref.to_string(), manuscript_pack.evidence_pack_ref.clone()],
            provenance_refs: provenance_refs.clone(),
            citation_refs: citation_refs.clone(),
        },
        JatsManuscriptSection {
            section_id: "references".to_string(),
            section_type: "references".to_string(),
            title: "References and Evidence Links".to_string(),
            body: build_references_body(manuscript_pack),
            claim_refs,
            evidence_refs: vec![manuscript_pack.evidence_pack_ref.clone(), review_bundle_ref.to_string()],
            provenance_refs,
            citation_refs,
        },
    ]
}

fn build_methods_body(packet: &ProgramContextPacket, evidence_pack: &EvidencePack) -> String {
    let recipe_summary = if evidence_pack.recipe_refs.is_empty() {
        "No canonical recipe refs were available.".to_string()
    } else {
        format!(
            "Canonical recipes referenced: {}.",
            evidence_pack
                .recipe_refs
                .iter()
                .map(|recipe| format!("{} ({})", recipe.recipe_id, recipe.kind))
                .collect::<Vec<_>>()
                .join(", ")
        )
    };
    let experiment_summary = if evidence_pack.experiment_refs.is_empty() {
        "No experiment refs were carried into this bounded assembly.".to_string()
    } else {
        format!(
            "Experiment refs: {}.",
            evidence_pack
                .experiment_refs
                .iter()
                .map(|experiment| experiment.experiment_id.clone())
                .collect::<Vec<_>>()
                .join(", ")
        )
    };
    let physio_summary = packet
        .latest_physio
        .as_ref()
        .map(|physio| {
            format!(
                "Latest physio snapshot source={} hr={:?} hrv_level={:?} spo2={:?}.",
                physio.source.clone().unwrap_or_else(|| "unknown".to_string()),
                physio.hr,
                physio.hrv_level,
                physio.spo2
            )
        })
        .unwrap_or_else(|| "No latest physio snapshot was attached to the active packet.".to_string());

    format!(
        "The bounded manuscript assembly reuses campaign-aware Beagle packets, canonical evidence packs and claim-linked manuscript metadata. {} {} {}",
        recipe_summary, experiment_summary, physio_summary
    )
}

fn methods_evidence_refs(evidence_pack: &EvidencePack) -> Vec<String> {
    let mut refs = evidence_pack
        .recipe_refs
        .iter()
        .map(|recipe| format!("recipe:{}", recipe.recipe_id))
        .collect::<Vec<_>>();
    refs.extend(
        evidence_pack
            .experiment_refs
            .iter()
            .map(|experiment| format!("experiment:{}", experiment.experiment_id)),
    );
    refs.extend(
        evidence_pack
            .physio_refs
            .iter()
            .enumerate()
            .map(|(index, physio)| format!("physio:{}:{}", physio.scope, index)),
    );
    refs
}

fn build_results_body(
    claims: &[ClaimRecord],
    evidence_pack: &EvidencePack,
    manuscript_pack: &ManuscriptPack,
) -> String {
    let supported_claims = claims
        .iter()
        .filter(|claim| claim.claim_state == "supported")
        .count();
    format!(
        "The current bounded results package contains {} claims ({} supported), {} result refs, {} memory refs and {} physio refs. The current readiness state is {}.",
        claims.len(),
        supported_claims,
        evidence_pack.result_refs.len(),
        evidence_pack.memory_refs.len(),
        evidence_pack.physio_refs.len(),
        manuscript_pack.readiness_state
    )
}

fn results_evidence_refs(evidence_pack: &EvidencePack) -> Vec<String> {
    let mut refs = evidence_pack
        .result_refs
        .iter()
        .filter_map(|result| result.result_reference.clone())
        .collect::<Vec<_>>();
    refs.extend(
        evidence_pack
            .memory_refs
            .iter()
            .filter_map(|memory| memory.memory_id.as_ref().map(|id| format!("memory:{id}"))),
    );
    refs
}

fn build_discussion_body(manuscript_pack: &ManuscriptPack) -> String {
    let mut parts = manuscript_pack.interpretive_notes.clone();
    if !manuscript_pack.gaps.is_empty() {
        parts.push(format!(
            "Bounded remaining gaps: {}.",
            manuscript_pack.gaps.join(", ")
        ));
    }
    parts.join(" ")
}

fn build_references_body(manuscript_pack: &ManuscriptPack) -> String {
    manuscript_pack
        .citation
        .related_identifiers
        .iter()
        .map(|identifier| {
            format!(
                "{} [{}] {}",
                identifier.relation_type, identifier.identifier_type, identifier.value
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn build_jats_xml(pack: &JatsManuscriptPack) -> String {
    let keywords = pack
        .citation
        .subjects
        .iter()
        .map(|subject| format!("<kwd>{}</kwd>", xml_escape(subject)))
        .collect::<String>();
    let body_sections = pack
        .section_map
        .iter()
        .filter(|section| section.section_type != "references")
        .map(|section| {
            format!(
                "<sec id=\"{}\" sec-type=\"{}\"><title>{}</title><p>{}</p></sec>",
                xml_escape(&section.section_id),
                xml_escape(&section.section_type),
                xml_escape(&section.title),
                xml_escape(&section.body),
            )
        })
        .collect::<String>();
    let ref_list = pack
        .citation
        .related_identifiers
        .iter()
        .enumerate()
        .map(|(index, identifier)| {
            format!(
                "<ref id=\"R{}\"><label>R{}</label><mixed-citation>{} [{}] {}</mixed-citation></ref>",
                index + 1,
                index + 1,
                xml_escape(&identifier.relation_type),
                xml_escape(&identifier.identifier_type),
                xml_escape(&identifier.value),
            )
        })
        .collect::<String>();
    let provenance_notes = pack
        .provenance
        .activities
        .iter()
        .map(|activity| {
            format!(
                "<p>{}: used {} and generated {}.</p>",
                xml_escape(&activity.id),
                xml_escape(&activity.used.join(", ")),
                xml_escape(&activity.generated.join(", ")),
            )
        })
        .collect::<String>();
    let manuscript_target = pack
        .manuscript_target
        .as_ref()
        .map(|target| target.id.clone())
        .unwrap_or_else(|| "undeclared".to_string());

    format!(
        concat!(
            "<article article-type=\"{article_type}\" dtd-version=\"1.4\">",
            "<front>",
            "<journal-meta>",
            "<journal-id journal-id-type=\"publisher-id\">beagle</journal-id>",
            "<journal-title-group><journal-title>Beagle Internal Research Objects</journal-title></journal-title-group>",
            "</journal-meta>",
            "<article-meta>",
            "<article-id pub-id-type=\"beagle-pack\">{pack_id}</article-id>",
            "<article-id pub-id-type=\"campaign\">{campaign_id}</article-id>",
            "<title-group><article-title>{title}</article-title></title-group>",
            "<abstract><p>{abstract_text}</p></abstract>",
            "<kwd-group kwd-group-type=\"author-generated-keywords\">{keywords}</kwd-group>",
            "<custom-meta-group>",
            "<custom-meta><meta-name>program_id</meta-name><meta-value>{program_id}</meta-value></custom-meta>",
            "<custom-meta><meta-name>active_workstream_id</meta-name><meta-value>{workstream_id}</meta-value></custom-meta>",
            "<custom-meta><meta-name>readiness_state</meta-name><meta-value>{readiness_state}</meta-value></custom-meta>",
            "<custom-meta><meta-name>manuscript_target</meta-name><meta-value>{manuscript_target}</meta-value></custom-meta>",
            "<custom-meta><meta-name>evidence_pack_ref</meta-name><meta-value>{evidence_pack_ref}</meta-value></custom-meta>",
            "<custom-meta><meta-name>review_bundle_ref</meta-name><meta-value>{review_bundle_ref}</meta-value></custom-meta>",
            "</custom-meta-group>",
            "</article-meta>",
            "</front>",
            "<body>{body_sections}</body>",
            "<back>",
            "<ref-list><title>References</title>{ref_list}</ref-list>",
            "<notes><sec sec-type=\"provenance\"><title>Provenance</title>{provenance_notes}</sec></notes>",
            "</back>",
            "</article>"
        ),
        article_type = xml_escape(&pack.article_type),
        pack_id = xml_escape(&pack.pack_id),
        campaign_id = xml_escape(&pack.campaign_id),
        title = xml_escape(&pack.title),
        abstract_text = xml_escape(&pack.abstract_text),
        keywords = keywords,
        program_id = xml_escape(&pack.program_id),
        workstream_id = xml_escape(&pack.active_workstream_id),
        readiness_state = xml_escape(&pack.readiness_state),
        manuscript_target = xml_escape(&manuscript_target),
        evidence_pack_ref = xml_escape(&pack.evidence_pack_ref),
        review_bundle_ref = xml_escape(&pack.review_bundle_ref),
        body_sections = body_sections,
        ref_list = ref_list,
        provenance_notes = provenance_notes,
    )
}

fn xml_escape(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        build_campaign_claims, build_campaign_evidence_pack, build_campaign_manuscript_pack,
        build_campaign_review_bundle, resolve_campaign_context_binding,
        ProgramContextPacketEvidenceTarget, ProgramContextPacketMemoryHit,
        WorkstreamContextPacketExperimentFlags,
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
            latest_results: vec![crate::ProgramContextPacketLatestResult {
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
    fn campaign_jats_manuscript_pack_assembles_sections_and_links() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let packet = sample_packet();
        let evidence = build_campaign_evidence_pack(&binding, &packet).unwrap();
        let claims = build_campaign_claims(&binding, &packet, &evidence).unwrap();
        let manuscript = build_campaign_manuscript_pack(&binding, &packet, &evidence).unwrap();
        let review =
            build_campaign_review_bundle(&binding, &packet, &evidence, &claims, &manuscript)
                .unwrap();

        let jats = build_campaign_jats_manuscript_pack(
            &binding,
            &packet,
            &evidence,
            &claims,
            &manuscript,
            &review,
        )
        .unwrap();

        assert_eq!(jats.pack.jats_profile, JATS_PROFILE);
        assert_eq!(jats.pack.claim_ids.len(), 3);
        assert!(jats.pack.section_map.iter().any(|section| {
            section.section_type == "methods"
                && section
                    .evidence_refs
                    .iter()
                    .any(|reference| reference.starts_with("recipe:"))
        }));
        assert_eq!(
            jats.pack.readiness_state,
            "claim-linked-human-eval-pending"
        );
    }

    #[test]
    fn campaign_jats_manuscript_pack_derives_jats_ready_xml() {
        let binding = resolve_campaign_context_binding("expedition-002-hrv-aware").unwrap();
        let packet = sample_packet();
        let evidence = build_campaign_evidence_pack(&binding, &packet).unwrap();
        let claims = build_campaign_claims(&binding, &packet, &evidence).unwrap();
        let manuscript = build_campaign_manuscript_pack(&binding, &packet, &evidence).unwrap();
        let review =
            build_campaign_review_bundle(&binding, &packet, &evidence, &claims, &manuscript)
                .unwrap();

        let jats = build_campaign_jats_manuscript_pack(
            &binding,
            &packet,
            &evidence,
            &claims,
            &manuscript,
            &review,
        )
        .unwrap();

        assert!(jats.pack.jats_xml.contains("<article "));
        assert!(jats.pack.jats_xml.contains("<front>"));
        assert!(jats.pack.jats_xml.contains("<abstract><p>"));
        assert!(jats.pack.jats_xml.contains("<body>"));
        assert!(jats.pack.jats_xml.contains("<ref-list>"));
        assert!(jats.pack.jats_xml.contains("claim-linked-human-eval-pending"));
    }
}
