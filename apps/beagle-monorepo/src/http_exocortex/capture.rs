//! `capture` exocortex HTTP handlers (split from the former god-file).
//!
//! Pure code movement: handlers call `super::ExocortexRepository` methods and shared
//! DTOs/helpers re-exported from the parent module. Behavior and route paths unchanged.

use super::*;

pub(crate) async fn capture_session_start_handler(
    State(_state): State<AppState>,
    Json(req): Json<CaptureSessionStartRequest>,
) -> Result<Json<CaptureSession>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let session = repo.start_capture_session(req).map_err(internal_error)?;
    Ok(Json(session))
}

pub(crate) async fn capture_session_status_handler(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<Json<CaptureSession>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.capture_session(&session_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

pub(crate) async fn capture_session_event_handler(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
    Json(req): Json<CaptureSessionEventRequest>,
) -> Result<Json<CaptureSessionEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo
        .append_capture_session_event(&session_id, req)
        .map_err(internal_error)?;
    Ok(Json(event))
}

pub(crate) async fn capture_visual_artifact_handler(
    State(_state): State<AppState>,
    Json(req): Json<VisualEvidenceArtifactRequest>,
) -> Result<Json<VisualEvidenceArtifact>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let artifact = repo
        .create_visual_evidence_artifact(req)
        .map_err(internal_error)?;
    Ok(Json(artifact))
}

pub(crate) async fn capture_visual_analyze_handler(
    State(_state): State<AppState>,
    Json(req): Json<VisualEvidenceAnalyzeRequest>,
) -> Result<Json<VisualEvidenceAnalysis>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let analysis = repo.analyze_visual_evidence(req).map_err(internal_error)?;
    Ok(Json(analysis))
}

pub(crate) async fn capture_review_handler(
    State(_state): State<AppState>,
    Json(req): Json<CaptureReviewRequest>,
) -> Result<Json<CaptureReviewResult>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let result = repo
        .review_capture_candidates(req)
        .map_err(internal_error)?;
    Ok(Json(result))
}

impl super::ExocortexRepository {
    fn start_capture_session(
        &self,
        req: CaptureSessionStartRequest,
    ) -> anyhow::Result<CaptureSession> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted capture sessions must stay local until explicit review"
        );
        let mode = req
            .mode
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "thinking_aloud".to_string());
        let surface = req
            .surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "beagle-apple-composer".to_string());
        let project_slug = req
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let principal = req
            .principal
            .as_deref()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "beagle-apple-app".to_string());
        let id = stable_id("capture-session", &[&project_slug, &surface, &mode, &now]);
        let session = CaptureSession {
            id: id.clone(),
            created_at: now.clone(),
            updated_at: now,
            schema_version: CAPTURE_SESSION_SCHEMA.to_string(),
            project_slug,
            mode,
            surface: surface.clone(),
            principal: principal.clone(),
            title: req.title,
            privacy_class: privacy_class.clone(),
            status: "active".to_string(),
            raw_audio_policy: "local_ttl_short_discard_after_transcription".to_string(),
            raw_image_policy: "private_cluster_artifact_hash_merkle_provenance".to_string(),
            transcription_segments: Vec::new(),
            artifact_refs: Vec::new(),
            evidence_refs: Vec::new(),
            review_state: "open".to_string(),
            provenance: merge_json_objects(
                serde_json::json!({
                    "beagle_observes": true,
                    "sounio_types": false,
                    "anti_creepy_policy": "user_initiated_visible_session_only",
                    "ambient_listening": false,
                    "surface": surface,
                    "principal": principal,
                    "privacy_class": privacy_class
                }),
                req.metadata,
            ),
        };
        self.append_jsonl(CAPTURE_SESSIONS_LOG, &session)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(session.principal.clone()),
            action: Some("capture.session_start".to_string()),
            tool_name: Some("beagle_capture_session_start".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&session.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: Some(session.surface.clone()),
            target_ref: Some(format!("capture_session:{}", session.id)),
            summary: Some(format!(
                "Started explicit {} capture session for {}.",
                session.mode, session.project_slug
            )),
            metadata: Some(serde_json::json!({
                "capture_session_id": session.id.clone(),
                "project_slug": session.project_slug.clone(),
                "mode": session.mode.clone(),
                "privacy_class": session.privacy_class.clone(),
                "anti_creepy_policy": "no_ambient_adtech_capture"
            })),
        })?;
        Ok(session)
    }

    fn capture_session(&self, session_id: &str) -> anyhow::Result<Option<CaptureSession>> {
        self.ensure()?;
        Ok(self
            .read_recent_jsonl::<CaptureSession>(CAPTURE_SESSIONS_LOG, usize::MAX)?
            .into_iter()
            .find(|session| session.id == session_id))
    }

    fn append_capture_session_event(
        &self,
        session_id: &str,
        req: CaptureSessionEventRequest,
    ) -> anyhow::Result<CaptureSessionEvent> {
        self.ensure()?;
        anyhow::ensure!(
            self.capture_session(session_id)?.is_some(),
            "capture session not found"
        );
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted capture events must stay in local review-only outbox"
        );
        let now = Utc::now().to_rfc3339();
        let event_type = if req.event_type.trim().is_empty() {
            "note".to_string()
        } else {
            req.event_type.trim().to_lowercase()
        };
        let id = stable_id(
            "capture-event",
            &[
                session_id,
                &event_type,
                req.text.as_deref().unwrap_or(""),
                &now,
            ],
        );
        let event = CaptureSessionEvent {
            id: id.clone(),
            created_at: now,
            session_id: session_id.to_string(),
            event_type,
            text: req.text.map(|value| truncate_chars(value.trim(), 4000)),
            transcription_segments: req
                .transcription_segments
                .into_iter()
                .map(normalize_transcription_segment)
                .collect(),
            artifact_refs: dedupe_strings(req.artifact_refs, 32),
            evidence_refs: dedupe_strings(req.evidence_refs, 48),
            privacy_class,
            metadata: req.metadata,
        };
        self.append_jsonl(CAPTURE_EVENTS_LOG, &event)?;
        Ok(event)
    }

    fn create_visual_evidence_artifact(
        &self,
        req: VisualEvidenceArtifactRequest,
    ) -> anyhow::Result<VisualEvidenceArtifact> {
        self.ensure()?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted visual artifacts require explicit local review before cluster storage"
        );
        anyhow::ensure!(
            req.content_hash.trim().starts_with("sha256:"),
            "visual artifact content_hash must be sha256:<hex>"
        );
        let now = Utc::now().to_rfc3339();
        let project_slug = req
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let source_surface = req
            .source_surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "beagle-apple-visual-capture".to_string());
        let source_kind = req
            .source_kind
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "image".to_string());
        let media_type = req
            .media_type
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "image".to_string());
        let requested_content_ref = req.content_ref.clone();
        let id = stable_id(
            "visual-artifact",
            &[
                &project_slug,
                &source_surface,
                &source_kind,
                &req.content_hash,
            ],
        );
        let mut content_ref = requested_content_ref;
        let mut artifact_byte_count = req.artifact_byte_count;
        if let Some(encoded) = req
            .artifact_data_base64
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let encoded = encoded
                .split_once(',')
                .map(|(_, payload)| payload)
                .unwrap_or(encoded);
            let bytes = BASE64_STANDARD
                .decode(encoded)
                .map_err(|err| anyhow::anyhow!("invalid visual artifact base64: {err}"))?;
            anyhow::ensure!(
                bytes.len() <= 24 * 1024 * 1024,
                "visual artifact payload exceeds 24MB safety limit"
            );
            let computed_hash = sha256_content_hash(&bytes);
            anyhow::ensure!(
                computed_hash == req.content_hash.trim(),
                "visual artifact content_hash does not match payload"
            );
            if let Some(expected_count) = artifact_byte_count {
                anyhow::ensure!(
                    expected_count == bytes.len(),
                    "visual artifact byte count does not match payload"
                );
            }
            let artifact_dir = self.root.join(CAPTURE_VISUAL_ARTIFACTS_DIR).join(&id);
            fs::create_dir_all(&artifact_dir)?;
            let filename = format!("artifact.{}", media_type_extension(&media_type));
            fs::write(artifact_dir.join(&filename), &bytes)?;
            content_ref = Some(format!(
                "cluster-private://exocortex/{CAPTURE_VISUAL_ARTIFACTS_DIR}/{id}/{filename}"
            ));
            artifact_byte_count = Some(bytes.len());
        }
        let artifact = VisualEvidenceArtifact {
            id: id.clone(),
            created_at: now.clone(),
            schema_version: VISUAL_EVIDENCE_SCHEMA.to_string(),
            session_id: req.session_id,
            project_slug,
            source_surface,
            source_kind,
            media_type,
            content_hash: req.content_hash.trim().to_string(),
            content_ref,
            artifact_byte_count,
            local_summary: req
                .local_summary
                .map(|value| truncate_chars(value.trim(), 1000)),
            extracted_text: req
                .extracted_text
                .map(|value| truncate_chars(value.trim(), 6000)),
            local_hints: dedupe_strings(req.local_hints, 48),
            privacy_class,
            confirmation_state: req
                .confirmation_state
                .unwrap_or_else(|| "local_preview_only".to_string()),
            private_artifact_policy:
                "raw_image_private_cluster_artifact_public_digest_uses_sanitized_derivatives"
                    .to_string(),
            provenance: merge_json_objects(
                serde_json::json!({
                    "schema_version": VISUAL_EVIDENCE_SCHEMA,
                    "local_first": true,
                    "external_model_requires_confirmation": true,
                    "raw_artifact_stored": artifact_byte_count.is_some(),
                    "created_at": now
                }),
                req.metadata,
            ),
        };
        self.append_jsonl(CAPTURE_VISUAL_ARTIFACTS_LOG, &artifact)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: metadata_string(&artifact.provenance, "principal")
                .or_else(|| Some(artifact.source_surface.clone())),
            action: Some("capture.visual_artifact".to_string()),
            tool_name: Some("beagle_visual_evidence_artifact_create".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&artifact.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: Some(artifact.source_surface.clone()),
            target_ref: Some(format!("visual_artifact:{}", artifact.id)),
            summary: Some("Stored private visual evidence artifact metadata.".to_string()),
            metadata: Some(serde_json::json!({
                "artifact_id": artifact.id.clone(),
                "content_hash": artifact.content_hash.clone(),
                "artifact_byte_count": artifact.artifact_byte_count,
                "content_ref": artifact.content_ref.clone(),
                "privacy_class": artifact.privacy_class.clone(),
                "confirmation_state": artifact.confirmation_state.clone(),
                "restricted_leak_check": "passed:no_restricted_artifact"
            })),
        })?;
        Ok(artifact)
    }

    fn analyze_visual_evidence(
        &self,
        req: VisualEvidenceAnalyzeRequest,
    ) -> anyhow::Result<VisualEvidenceAnalysis> {
        self.ensure()?;
        let artifact = self
            .read_recent_jsonl::<VisualEvidenceArtifact>(CAPTURE_VISUAL_ARTIFACTS_LOG, usize::MAX)?
            .into_iter()
            .find(|artifact| artifact.id == req.artifact_id)
            .ok_or_else(|| anyhow::anyhow!("visual artifact not found"))?;
        anyhow::ensure!(
            artifact.privacy_class != "restricted",
            "restricted visual artifacts cannot be analyzed automatically"
        );
        let now = Utc::now().to_rfc3339();
        let allow_external = req.allow_external_model.unwrap_or(false);
        let provider = if allow_external {
            req.preferred_provider
                .clone()
                .unwrap_or_else(|| "openai-responses-vision".to_string())
        } else {
            "apple-vision-local-preview".to_string()
        };
        let prompt = req.prompt.clone().unwrap_or_else(|| {
            "Identify conceptual claims, evidence, tensions, and missing evidence.".to_string()
        });
        let local_text = [
            artifact.local_summary.clone(),
            artifact.extracted_text.clone(),
            metadata_string(&req.local_analysis, "summary"),
            Some(prompt.clone()),
        ]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join("\n");
        let summary = if local_text.trim().is_empty() {
            "Visual evidence captured; local preview has no extracted text yet.".to_string()
        } else {
            truncate_chars(local_text.trim(), 500)
        };
        let evidence_refs = vec![
            format!("visual_artifact:{}", artifact.id),
            artifact.content_hash.clone(),
        ];
        let candidate = CaptureReviewCandidate {
            id: stable_id("capture-candidate", &[&artifact.id, &summary]),
            kind: "claim_seed".to_string(),
            title: "Visual claim seed".to_string(),
            summary: summary.clone(),
            evidence_refs: evidence_refs.clone(),
            claim_text: Some(format!("Visual evidence suggests: {}", summary)),
            decision_text: None,
            next_action: Some(
                "Review the claim seed and attach missing evidence before promotion.".to_string(),
            ),
            epistemic_status: Some("belief".to_string()),
            confidence: Some(if allow_external { 0.72 } else { 0.54 }),
            privacy_class: artifact.privacy_class.clone(),
            provenance: serde_json::json!({
                "artifact_id": artifact.id,
                "provider": provider,
                "local_first": true,
                "external_model_allowed": allow_external,
                "redaction_summary": req.redaction_summary
            }),
        };
        let analysis = VisualEvidenceAnalysis {
            id: stable_id(
                "visual-analysis",
                &[&artifact.id, &provider, if allow_external { "external" } else { "local" }],
            ),
            created_at: now.clone(),
            schema_version: VISUAL_EVIDENCE_SCHEMA.to_string(),
            artifact_id: artifact.id.clone(),
            mode: if allow_external {
                "confirmed_external_multimodal".to_string()
            } else {
                "local_preview".to_string()
            },
            provider: provider.clone(),
            status: "analysis_ready".to_string(),
            summary,
            claim_map: vec![candidate],
            evidence_refs,
            tensions: vec![
                "visual evidence can support claim seeds but cannot promote them to knowledge without provenance review"
                    .to_string(),
            ],
            missing_evidence: vec![
                "human review of image redaction and claim relevance".to_string(),
                "source context for the diagram/photo/document".to_string(),
            ],
            restricted_leak_check: "passed:no_restricted_visual_content_indexed".to_string(),
            requires_confirmation: !allow_external,
            provenance: serde_json::json!({
                "principal": req.principal.unwrap_or_else(|| "beagle-apple-app".to_string()),
                "surface": req.surface.unwrap_or_else(|| artifact.source_surface.clone()),
                "artifact_id": artifact.id,
                "provider": provider,
                "allow_external_model": allow_external,
                "external_model_call": if allow_external { "provider_config_required" } else { "not_requested" },
                "analysis_is_derivative": true
            }),
            degraded_reason: if allow_external {
                Some(
                    "Core recorded confirmed visual analysis intent; provider execution is delegated to configured multimodal worker."
                        .to_string(),
                )
            } else {
                Some("External multimodal model requires explicit user confirmation.".to_string())
            },
        };
        self.append_jsonl(CAPTURE_VISUAL_ANALYSES_LOG, &analysis)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: metadata_string(&analysis.provenance, "principal"),
            action: Some("capture.visual_analyze".to_string()),
            tool_name: Some("beagle_visual_evidence_analyze".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&analysis.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: metadata_string(&analysis.provenance, "surface"),
            target_ref: Some(format!("visual_analysis:{}", analysis.id)),
            summary: Some("Created VisualEvidenceAnalysis claim map.".to_string()),
            metadata: Some(serde_json::json!({
                "analysis_id": analysis.id.clone(),
                "artifact_id": analysis.artifact_id.clone(),
                "provider": analysis.provider.clone(),
                "requires_confirmation": analysis.requires_confirmation,
                "restricted_leak_check": analysis.restricted_leak_check.clone()
            })),
        })?;
        Ok(analysis)
    }

    fn review_capture_candidates(
        &self,
        req: CaptureReviewRequest,
    ) -> anyhow::Result<CaptureReviewResult> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted capture reviews require local-only explicit handling"
        );
        let project_slug = req
            .project_slug
            .clone()
            .unwrap_or_else(|| "sounio".to_string());
        let source_surface = req
            .source_surface
            .clone()
            .unwrap_or_else(|| "beagle-apple-capture-review".to_string());
        let reviewer = req
            .reviewer
            .clone()
            .unwrap_or_else(|| "demetrios".to_string());
        let promote = req.promote.unwrap_or(false);
        let mut moments = Vec::new();
        if promote {
            for candidate in req.candidates.iter().filter(|candidate| {
                normalize_privacy_class(Some(&candidate.privacy_class)) != "restricted"
            }) {
                let evidence_refs = candidate.evidence_refs.clone();
                let claim_seeds = candidate
                    .claim_text
                    .as_ref()
                    .map(|claim_text| {
                        vec![SounioClaimInput {
                            id: None,
                            claim_text: claim_text.clone(),
                            subject: Some(project_slug.clone()),
                            value_type: Some("Claim<T>".to_string()),
                            epistemic_status: Some(
                                candidate
                                    .epistemic_status
                                    .clone()
                                    .unwrap_or_else(|| "belief".to_string()),
                            ),
                            evidence_refs: evidence_refs.clone(),
                            provenance: serde_json::json!({
                                "source": "capture_review",
                                "candidate_id": candidate.id,
                                "reviewer": reviewer,
                            }),
                            confidence: candidate.confidence,
                            contestation: serde_json::Value::Null,
                            review_state: Some("unreviewed".to_string()),
                            promotion_rule: None,
                            publication_readiness: Some("not_ready".to_string()),
                            section_id: None,
                            agent_refs: vec![source_surface.clone()],
                            contract_refs: Vec::new(),
                            artifact_refs: req
                                .artifact_id
                                .clone()
                                .map(|value| vec![value])
                                .unwrap_or_default(),
                            chronoself_commit_refs: Vec::new(),
                            privacy_class: Some(candidate.privacy_class.clone()),
                            rationale: Some(
                                "Capture review promotes a conservative Sounio Claim<T> seed."
                                    .to_string(),
                            ),
                        }]
                    })
                    .unwrap_or_default();
                let moment = self.type_sounio_moment(SounioMomentTypeRequest {
                    source_event_refs: [
                        req.session_id
                            .clone()
                            .map(|value| format!("capture_session:{value}")),
                        req.artifact_id
                            .clone()
                            .map(|value| format!("visual_artifact:{value}")),
                    ]
                    .into_iter()
                    .flatten()
                    .collect(),
                    source_platform: Some("beagle-apple".to_string()),
                    source_surface: Some(source_surface.clone()),
                    project_slug: Some(project_slug.clone()),
                    session_id: req.session_id.clone(),
                    intent_text: Some(candidate.title.clone()),
                    summary: Some(candidate.summary.clone()),
                    evidence_refs,
                    claim_seeds,
                    decision_seeds: candidate
                        .decision_text
                        .clone()
                        .map(|value| vec![value])
                        .unwrap_or_default(),
                    next_action: candidate.next_action.clone(),
                    privacy_class: Some(candidate.privacy_class.clone()),
                    review_state: Some("reviewed".to_string()),
                    provenance: merge_json_objects(
                        serde_json::json!({
                            "reviewer": reviewer,
                            "capture_review": true,
                            "candidate_id": candidate.id,
                            "decision": req.decision.clone().unwrap_or_else(|| "promote".to_string())
                        }),
                        candidate.provenance.clone(),
                    ),
                    tags: vec![
                        "multimodal-composer".to_string(),
                        "sounio-moment".to_string(),
                        format!("project:{project_slug}"),
                    ],
                })?;
                moments.push(moment);
            }
        }
        let id = stable_id(
            "capture-review",
            &[
                req.session_id.as_deref().unwrap_or("no-session"),
                req.artifact_id.as_deref().unwrap_or("no-artifact"),
                &reviewer,
                &now,
            ],
        );
        let memory_event = if promote {
            Some(self.create_memory_event(CreateMemoryEventRequest {
                source: Some(source_surface.clone()),
                kind: Some("capture_review".to_string()),
                content_ref: Some(format!("capture_review:{id}")),
                summary: Some(format!(
                    "Reviewed {} multimodal capture candidate(s); promoted {}.",
                    req.candidates.len(),
                    moments.len()
                )),
                tags: vec![
                    "multimodal-composer".to_string(),
                    "capture-review".to_string(),
                    format!("project:{project_slug}"),
                ],
                metadata: Some(serde_json::json!({
                    "capture_review_id": id.clone(),
                    "capture_session_id": req.session_id.clone(),
                    "artifact_id": req.artifact_id.clone(),
                    "promoted_moment_ids": moments.iter().map(|moment| moment.id.clone()).collect::<Vec<_>>(),
                    "privacy_class": privacy_class,
                    "restricted_leak_check": "passed:no_restricted_candidate_promoted"
                })),
                linked_chronoself_commits: Vec::new(),
                confidence: Some(0.78),
            })?)
        } else {
            None
        };
        let audit = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(reviewer.clone()),
            action: Some("capture.review".to_string()),
            tool_name: Some("beagle_capture_review_promote".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&req.provenance, "scopes").unwrap_or_default(),
            status: Some(if promote { "success" } else { "reviewed" }.to_string()),
            source: Some(source_surface.clone()),
            target_ref: Some(format!("capture_review:{id}")),
            summary: Some("Reviewed multimodal capture candidates.".to_string()),
            metadata: Some(serde_json::json!({
                "capture_review_id": id.clone(),
                "promote": promote,
                "candidate_count": req.candidates.len(),
                "promoted_count": moments.len(),
                "privacy_class": privacy_class,
                "restricted_leak_check": "passed:no_restricted_candidate_promoted"
            })),
        })?;
        let result = CaptureReviewResult {
            id,
            created_at: now,
            schema_version: CAPTURE_REVIEW_SCHEMA.to_string(),
            status: if promote {
                "promoted".to_string()
            } else {
                "reviewed_without_promotion".to_string()
            },
            promoted_count: moments.len(),
            sounio_moments: moments,
            memory_event,
            audit_event: Some(audit),
            candidates: req.candidates,
        };
        self.append_jsonl(CAPTURE_REVIEWS_LOG, &result)?;
        Ok(result)
    }
}
