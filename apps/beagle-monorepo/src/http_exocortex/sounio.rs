//! `sounio` exocortex HTTP handlers (split from the former god-file).
//!
//! Pure code movement: handlers call `super::ExocortexRepository` methods and shared
//! DTOs/helpers re-exported from the parent module. Behavior and route paths unchanged.

use super::*;

pub(crate) async fn sounio_program_check_handler(
    State(_state): State<AppState>,
    Json(req): Json<SounioProgramCheckRequest>,
) -> Result<Json<SounioProgramCheckResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.check_sounio_program(req).map_err(internal_error)?;
    Ok(Json(response))
}

pub(crate) async fn sounio_claim_check_handler(
    State(_state): State<AppState>,
    Json(req): Json<SounioClaimCheckRequest>,
) -> Result<Json<SounioClaimCheckResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.check_sounio_claim(req).map_err(internal_error)?;
    Ok(Json(response))
}

pub(crate) async fn sounio_moment_type_handler(
    State(_state): State<AppState>,
    Json(req): Json<SounioMomentTypeRequest>,
) -> Result<Json<SounioMoment>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let moment = repo.type_sounio_moment(req).map_err(internal_error)?;
    Ok(Json(moment))
}

pub(crate) async fn sounio_moments_recent_handler(
    State(_state): State<AppState>,
    Query(query): Query<SounioMomentsQuery>,
) -> Result<Json<SounioMomentListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let moments = repo.sounio_moments_recent(query).map_err(internal_error)?;
    Ok(Json(moments))
}

pub(crate) async fn sounio_moment_review_handler(
    State(_state): State<AppState>,
    Path(moment_id): Path<String>,
    Json(req): Json<SounioMomentReviewRequest>,
) -> Result<Json<SounioMoment>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let moment = repo
        .review_sounio_moment(&moment_id, req)
        .map_err(internal_error)?;
    Ok(Json(moment))
}

pub(crate) async fn sounio_workday_status_handler(
    State(_state): State<AppState>,
    Query(query): Query<SounioWorkdayQuery>,
) -> Result<Json<SounioWorkdaySnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.sounio_workday_status(query).map_err(internal_error)?;
    Ok(Json(snapshot))
}

pub(crate) async fn sounio_paperrun_start_handler(
    State(_state): State<AppState>,
    Json(req): Json<StartPaperRunRequest>,
) -> Result<Json<PaperRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.start_paper_run(req).map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn sounio_paperrun_get_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PaperRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.paper_run(&paper_run_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

pub(crate) async fn sounio_paperrun_approve_step_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
    Json(req): Json<ApprovePaperRunStepRequest>,
) -> Result<Json<PaperRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo
        .approve_paper_run_step(&paper_run_id, req)
        .map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn sounio_paperrun_artifacts_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PaperRunArtifactsResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let artifacts = repo
        .paper_run_artifacts(&paper_run_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(artifacts))
}

pub(crate) async fn sounio_paperrun_add_claim_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
    Json(req): Json<AddPaperRunClaimRequest>,
) -> Result<Json<SounioClaim>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let claim = repo
        .add_paper_run_claim(&paper_run_id, req)
        .map_err(internal_error)?;
    Ok(Json(claim))
}

pub(crate) async fn sounio_claim_review_handler(
    State(_state): State<AppState>,
    Path((paper_run_id, claim_id)): Path<(String, String)>,
    Json(req): Json<ReviewSounioClaimRequest>,
) -> Result<Json<SounioClaim>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let claim = repo
        .review_sounio_claim(&paper_run_id, &claim_id, req)
        .map_err(internal_error)?;
    Ok(Json(claim))
}

pub(crate) async fn sounio_paperrun_theatre_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PaperRunTheatreSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo
        .paper_run_theatre(&paper_run_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(snapshot))
}

pub(crate) async fn sounio_paperrun_public_digest_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PublicDigestArtifact>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let digest = repo
        .paper_run_public_digest(&paper_run_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(digest))
}

pub(crate) async fn sounio_trace_query_handler(
    State(_state): State<AppState>,
    Query(query): Query<SounioTraceQuery>,
) -> Result<Json<SounioTraceListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let events = repo.sounio_trace_events(query).map_err(internal_error)?;
    Ok(Json(SounioTraceListResponse { events }))
}

impl super::ExocortexRepository {
    pub(crate) fn check_sounio_program(
        &self,
        req: SounioProgramCheckRequest,
    ) -> anyhow::Result<SounioProgramCheckResponse> {
        let mut errors = validate_sounio_program(&req.program);
        let privacy_class = normalize_privacy_class(Some(&req.program.governance.privacy_class));
        if privacy_class == "restricted" {
            errors.push(
                "program governance privacy_class=restricted is blocked from PaperRun v2.4"
                    .to_string(),
            );
        }
        let warnings = sounio_program_warnings(&req.program, req.source_format.as_deref());
        let program_hash = sounio_program_hash(&req.program)?;
        Ok(SounioProgramCheckResponse {
            status: if errors.is_empty() {
                "valid".to_string()
            } else {
                "invalid".to_string()
            },
            program_hash,
            schema_version: SOUNIO_WORK_IR_SCHEMA.to_string(),
            errors,
            warnings,
            temporal_spec: sounio_temporal_spec(&req.program),
            memory_projection_preview: sounio_memory_projection_preview(&req.program),
        })
    }

    pub(crate) fn check_sounio_claim(
        &self,
        req: SounioClaimCheckRequest,
    ) -> anyhow::Result<SounioClaimCheckResponse> {
        let (claim, errors, warnings) = materialize_sounio_claim(req.claim, None, None)?;
        Ok(SounioClaimCheckResponse {
            status: if errors.is_empty() {
                "valid".to_string()
            } else {
                "invalid".to_string()
            },
            schema_version: SOUNIO_CLAIM_SCHEMA.to_string(),
            required_evidence: sounio_claim_required_evidence(&claim),
            promotion_gate: sounio_claim_promotion_gate(&claim),
            normalized_claim: claim,
            errors,
            warnings,
        })
    }

    pub(crate) fn type_sounio_moment(
        &self,
        req: SounioMomentTypeRequest,
    ) -> anyhow::Result<SounioMoment> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted payloads require explicit local review before Sounio typing"
        );

        let source_platform = req
            .source_platform
            .as_deref()
            .map(normalize_source_platform)
            .unwrap_or_else(|| "mcp-agent".to_string());
        let source_surface = req
            .source_surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio-ambient-typing".to_string());
        let project_slug = req
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let mut evidence_refs = req.evidence_refs.clone();
        merge_unique(&mut evidence_refs, req.source_event_refs.clone(), 48);
        let intent = req
            .intent_text
            .as_deref()
            .or(req.summary.as_deref())
            .map(|value| truncate_chars(value.trim(), 240))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| {
                "Type this ambient work signal into the Sounio workday.".to_string()
            });
        let summary = req
            .summary
            .as_deref()
            .map(|value| truncate_chars(value.trim(), 360))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| intent.clone());
        let mut claim_seeds = Vec::new();
        let mut claim_warnings = Vec::new();
        for input in req.claim_seeds {
            let (claim, errors, warnings) = materialize_sounio_claim(input, None, None)?;
            anyhow::ensure!(
                errors.is_empty(),
                "Sounio moment claim seed invalid: {}",
                errors.join("; ")
            );
            claim_warnings.extend(warnings);
            claim_seeds.push(claim);
        }
        let id = stable_id(
            "sounio-moment",
            &[
                &project_slug,
                req.session_id.as_deref().unwrap_or("ambient"),
                &source_platform,
                &source_surface,
                &summary,
            ],
        );
        let moment = SounioMoment {
            id,
            created_at: now.clone(),
            updated_at: now.clone(),
            schema_version: SOUNIO_MOMENT_SCHEMA.to_string(),
            project_slug: project_slug.clone(),
            moment_type: infer_sounio_moment_type(&source_platform, &source_surface, &req.tags),
            intent,
            summary,
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            session_id: req.session_id.clone(),
            source_event_refs: req.source_event_refs.clone(),
            evidence_refs: evidence_refs.clone(),
            claim_seeds,
            decision_seeds: req.decision_seeds.clone(),
            next_action: req.next_action.clone(),
            privacy_class: privacy_class.clone(),
            review_state: req.review_state.unwrap_or_else(|| "unreviewed".to_string()),
            restricted_leak_check: "passed:no_restricted_payload_typed".to_string(),
            provenance: merge_json_objects(
                serde_json::json!({
                    "schema_version": SOUNIO_MOMENT_SCHEMA,
                    "beagle_observes": true,
                    "sounio_types": true,
                    "source_platform": source_platform,
                    "source_surface": source_surface,
                    "claim_seed_warnings": claim_warnings,
                    "restricted_policy": "restricted never enters ambient typing automatically"
                }),
                req.provenance,
            ),
            tags: req.tags,
        };
        self.append_jsonl(SOUNIO_MOMENTS_LOG, &moment)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(
                metadata_string(&moment.provenance, "principal")
                    .unwrap_or_else(|| moment.source_surface.clone()),
            ),
            action: Some("sounio.moment_type".to_string()),
            tool_name: Some("beagle_sounio_moment_type".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&moment.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: Some(moment.source_surface.clone()),
            target_ref: Some(format!("sounio_moment:{}", moment.id)),
            summary: Some(format!(
                "Sounio typed ambient moment for {} as {}.",
                moment.project_slug, moment.moment_type
            )),
            metadata: Some(serde_json::json!({
                "moment_id": moment.id,
                "project_slug": moment.project_slug,
                "privacy_class": moment.privacy_class,
                "claim_seed_count": moment.claim_seeds.len(),
                "decision_seed_count": moment.decision_seeds.len(),
                "restricted_leak_check": moment.restricted_leak_check,
                "schema_version": SOUNIO_MOMENT_SCHEMA
            })),
        })?;
        Ok(moment)
    }

    fn sounio_moments_recent(
        &self,
        query: SounioMomentsQuery,
    ) -> anyhow::Result<SounioMomentListResponse> {
        let project_slug = query
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty());
        let mut seen = BTreeSet::new();
        let moments = self
            .read_recent_jsonl::<SounioMoment>(
                SOUNIO_MOMENTS_LOG,
                query.limit.unwrap_or(25).min(100),
            )?
            .into_iter()
            .filter(|moment| moment.privacy_class != "restricted")
            .filter(|moment| {
                project_slug
                    .as_ref()
                    .map(|slug| &moment.project_slug == slug)
                    .unwrap_or(true)
            })
            .filter(|moment| seen.insert(moment.id.clone()))
            .collect::<Vec<_>>();
        Ok(SounioMomentListResponse {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_MOMENT_SCHEMA.to_string(),
            project_slug,
            moments,
        })
    }

    fn review_sounio_moment(
        &self,
        moment_id: &str,
        req: SounioMomentReviewRequest,
    ) -> anyhow::Result<SounioMoment> {
        self.ensure()?;
        let mut moment = self
            .read_recent_jsonl::<SounioMoment>(SOUNIO_MOMENTS_LOG, usize::MAX)?
            .into_iter()
            .find(|moment| moment.id == moment_id)
            .ok_or_else(|| anyhow::anyhow!("Sounio moment not found: {moment_id}"))?;
        anyhow::ensure!(
            moment.privacy_class != "restricted",
            "restricted Sounio moments cannot enter cluster review flow"
        );
        let decision = req.decision.trim().to_lowercase();
        anyhow::ensure!(
            matches!(
                decision.as_str(),
                "approved" | "rejected" | "needs_revision" | "mark_contest" | "promote_claim_seed"
            ),
            "moment review decision must be approved, rejected, needs_revision, mark_contest, or promote_claim_seed"
        );
        let previous_state = moment.review_state.clone();
        for evidence_ref in &req.evidence_refs {
            if !moment.evidence_refs.contains(evidence_ref) {
                moment.evidence_refs.push(evidence_ref.clone());
            }
        }
        moment.review_state = req
            .review_state
            .clone()
            .unwrap_or_else(|| match decision.as_str() {
                "approved" => "approved".to_string(),
                "rejected" => "rejected".to_string(),
                "needs_revision" => "needs_revision".to_string(),
                "mark_contest" => "contest".to_string(),
                _ => "reviewed_claim_seed".to_string(),
            });
        if decision == "mark_contest" {
            for claim in &mut moment.claim_seeds {
                claim.epistemic_status = "contest".to_string();
                claim.review_state = "contested".to_string();
            }
        }
        moment.updated_at = Utc::now().to_rfc3339();
        moment.provenance = merge_json_objects(
            moment.provenance.clone(),
            serde_json::json!({
                "latest_review_decision": decision,
                "latest_reviewer": req.reviewer.clone().unwrap_or_else(|| "demetrios".to_string()),
                "latest_review_rationale": req.rationale.clone()
            }),
        );
        if !req.provenance.is_null() {
            moment.provenance =
                merge_json_objects(moment.provenance.clone(), req.provenance.clone());
        }
        self.append_jsonl(SOUNIO_MOMENTS_LOG, &moment)?;
        let review = SounioMomentReview {
            id: Uuid::new_v4().to_string(),
            created_at: moment.updated_at.clone(),
            moment_id: moment.id.clone(),
            reviewer: req.reviewer.unwrap_or_else(|| "demetrios".to_string()),
            decision: decision.clone(),
            rationale: req.rationale,
            previous_state,
            new_state: moment.review_state.clone(),
            evidence_refs: moment.evidence_refs.clone(),
            provenance: serde_json::json!({
                "schema_version": SOUNIO_MOMENT_SCHEMA,
                "project_slug": moment.project_slug,
                "source_surface": moment.source_surface,
                "restricted_leak_check": moment.restricted_leak_check
            }),
        };
        self.append_jsonl(SOUNIO_MOMENT_REVIEWS_LOG, &review)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(review.reviewer.clone()),
            action: Some("sounio.moment_review".to_string()),
            tool_name: Some("beagle_sounio_moment_review".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("success".to_string()),
            source: Some("sounio-workday-review".to_string()),
            target_ref: Some(format!("sounio_moment:{}", moment.id)),
            summary: Some(format!("Reviewed Sounio moment as {}.", decision)),
            metadata: Some(serde_json::json!({
                "moment_id": moment.id,
                "review_id": review.id,
                "decision": review.decision,
                "new_state": review.new_state,
                "restricted_leak_check": moment.restricted_leak_check
            })),
        })?;
        Ok(moment)
    }

    pub(crate) fn sounio_workday_status(
        &self,
        query: SounioWorkdayQuery,
    ) -> anyhow::Result<SounioWorkdaySnapshot> {
        let project_slug = query
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let moments_response = self.sounio_moments_recent(SounioMomentsQuery {
            limit: query.limit.or(Some(20)),
            project_slug: Some(project_slug.clone()),
        })?;
        let moments = moments_response.moments;
        let latest_moment = moments.first().cloned();
        let mut claim_seeds = Vec::new();
        let mut claim_seen = BTreeSet::new();
        let mut decision_seeds = Vec::new();
        let mut evidence_refs = Vec::new();
        let mut tensions = Vec::new();
        let mut agents = Vec::new();
        for moment in &moments {
            merge_unique(&mut decision_seeds, moment.decision_seeds.clone(), 32);
            merge_unique(&mut evidence_refs, moment.evidence_refs.clone(), 64);
            merge_unique(
                &mut agents,
                vec![
                    moment.source_platform.clone(),
                    moment.source_surface.clone(),
                ],
                24,
            );
            for claim in &moment.claim_seeds {
                if claim_seen.insert(claim.id.clone()) {
                    claim_seeds.push(claim.clone());
                }
                if claim.epistemic_status == "contest" {
                    tensions.push(format!(
                        "Contested claim seed: {}",
                        truncate_chars(&claim.claim_text, 120)
                    ));
                }
            }
            if moment.review_state.contains("revision") || moment.review_state == "contest" {
                tensions.push(format!(
                    "Moment {} needs review: {}",
                    moment.id,
                    truncate_chars(&moment.summary, 120)
                ));
            }
        }
        tensions.truncate(12);
        let review_queue_count = moments
            .iter()
            .filter(|moment| {
                !matches!(
                    moment.review_state.as_str(),
                    "approved" | "rejected" | "reviewed_claim_seed"
                )
            })
            .count();
        let status = if moments.is_empty() {
            "waiting-for-first-sounio-moment".to_string()
        } else if review_queue_count > 0 {
            "active-review-needed".to_string()
        } else {
            "active-audited".to_string()
        };
        let next_action = latest_moment
            .as_ref()
            .and_then(|moment| moment.next_action.clone())
            .or_else(|| {
                if review_queue_count > 0 {
                    Some("Review the latest Sounio moment and decide whether any Claim<T> seed needs evidence.".to_string())
                } else {
                    None
                }
            })
            .unwrap_or_else(|| {
                format!("Capture the next real Sounio work gesture for {}.", project_slug)
            });
        Ok(SounioWorkdaySnapshot {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_WORKDAY_SCHEMA.to_string(),
            project_slug,
            status,
            latest_moment,
            moments,
            claim_seeds,
            decision_seeds,
            evidence_refs,
            tensions,
            agents,
            next_action,
            review_queue_count,
            restricted_leak_check: "passed:restricted_filtered_from_workday".to_string(),
            provenance: serde_json::json!({
                "canonical_source": "/var/lib/beagle/exocortex/sounio_moments.jsonl",
                "cluster_only": true,
                "beagle_observes": true,
                "sounio_types": true
            }),
        })
    }

    pub(crate) fn add_paper_run_claim(
        &self,
        paper_run_id: &str,
        req: AddPaperRunClaimRequest,
    ) -> anyhow::Result<SounioClaim> {
        self.ensure()?;
        let mut run = self
            .paper_run(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun not found: {paper_run_id}"))?;
        let principal = req.principal.unwrap_or_else(|| "mcp-agent".to_string());
        let surface = req
            .surface
            .unwrap_or_else(|| "sounio-paperrun-theatre".to_string());
        let (claim, errors, warnings) =
            materialize_sounio_claim(req.claim, Some(paper_run_id.to_string()), Some(&run))?;
        anyhow::ensure!(
            errors.is_empty(),
            "Sounio claim invalid: {}",
            errors.join("; ")
        );

        self.append_jsonl(SOUNIO_CLAIMS_LOG, &claim)?;
        let claims = self.sounio_claims_for_paper_run(paper_run_id)?;
        run.updated_at = Utc::now().to_rfc3339();
        run.current_stage = Some("claim_check".to_string());
        run.public_digest_status = Some("stale_after_claim_change".to_string());
        run.claim_lifecycle_status = claim_lifecycle_status(&claims);
        run.claim_registry = claims.iter().map(sounio_claim_summary).collect();
        run.interaction_summary = Some(format!(
            "{} claim(s) tracked in the Sounio epistemic claim graph.",
            claims.len()
        ));
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;

        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: claim.created_at.clone(),
            paper_run_id: paper_run_id.to_string(),
            program_id: run.sounio_program_id.clone(),
            step_id: "claim_check".to_string(),
            event_type: "sounio_claim_added".to_string(),
            status: claim.epistemic_status.clone(),
            summary: Some(format!(
                "Added Sounio Claim<T> '{}' as {}.",
                truncate_chars(&claim.claim_text, 160),
                claim.epistemic_status
            )),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "principal": principal,
                "surface": surface,
                "claim_id": claim.id,
                "schema_version": SOUNIO_CLAIM_SCHEMA,
                "warnings": warnings
            }),
            artifact_refs: claim.artifact_refs.clone(),
        })?;
        let _ = self.create_memory_event(CreateMemoryEventRequest {
            source: Some("sounio-claim".to_string()),
            kind: Some("sounio_claim_added".to_string()),
            content_ref: Some(format!("sounio_claim:{}", claim.id)),
            summary: Some(format!(
                "Sounio typed claim {} as {}",
                claim.id, claim.epistemic_status
            )),
            tags: vec![
                "sounio".to_string(),
                "claim".to_string(),
                format!("epistemic:{}", claim.epistemic_status),
                "project:beagle".to_string(),
            ],
            metadata: Some(serde_json::json!({
                "paper_run_id": paper_run_id,
                "claim_id": claim.id,
                "epistemic_status": claim.epistemic_status,
                "privacy_class": claim.privacy_class,
                "beagle_observes": true,
                "sounio_types": true
            })),
            linked_chronoself_commits: Vec::new(),
            confidence: Some(claim.confidence),
        })?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-core".to_string()),
            action: Some("sounio.claim_add".to_string()),
            tool_name: Some("beagle_sounio_claim_check".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["research:run".to_string()],
            granted_scopes: vec!["research:run".to_string()],
            status: Some("success".to_string()),
            source: Some("sounio-paperrun-theatre".to_string()),
            target_ref: Some(format!("sounio_claim:{}", claim.id)),
            summary: Some("Added epistemically typed Sounio claim.".to_string()),
            metadata: Some(serde_json::json!({
                "paper_run_id": paper_run_id,
                "claim_id": claim.id,
                "epistemic_status": claim.epistemic_status,
                "schema_version": SOUNIO_CLAIM_SCHEMA
            })),
        })?;
        Ok(claim)
    }

    pub(crate) fn review_sounio_claim(
        &self,
        paper_run_id: &str,
        claim_id: &str,
        req: ReviewSounioClaimRequest,
    ) -> anyhow::Result<SounioClaim> {
        self.ensure()?;
        let mut run = self
            .paper_run(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun not found: {paper_run_id}"))?;
        let mut claim = self
            .sounio_claim(paper_run_id, claim_id)?
            .ok_or_else(|| anyhow::anyhow!("Sounio claim not found: {claim_id}"))?;
        let previous_status = claim.epistemic_status.clone();
        let decision = req.decision.trim().to_lowercase();
        anyhow::ensure!(
            matches!(
                decision.as_str(),
                "approved"
                    | "rejected"
                    | "needs_evidence"
                    | "contest"
                    | "promote_to_knowledge"
                    | "promote_to_robust"
            ),
            "claim review decision must be approved, rejected, needs_evidence, contest, promote_to_knowledge, or promote_to_robust"
        );

        for evidence_ref in req.evidence_refs {
            if !claim.evidence_refs.contains(&evidence_ref) {
                claim.evidence_refs.push(evidence_ref);
            }
        }
        if !req.provenance.is_null() {
            claim.provenance = merge_json_objects(claim.provenance.clone(), req.provenance.clone());
        }
        if let Some(readiness) = req.publication_readiness {
            claim.publication_readiness = readiness;
        }
        if let Some(status) = req.epistemic_status {
            claim.epistemic_status = normalize_epistemic_status(Some(&status));
        }

        match decision.as_str() {
            "rejected" => {
                claim.review_state = "rejected".to_string();
                claim.publication_readiness = "excluded".to_string();
            }
            "needs_evidence" => {
                claim.review_state = "needs_evidence".to_string();
                claim.epistemic_status = "contest".to_string();
                claim.publication_readiness = "not_ready".to_string();
            }
            "contest" => {
                claim.review_state = "contested".to_string();
                claim.epistemic_status = "contest".to_string();
            }
            "promote_to_knowledge" => {
                anyhow::ensure!(
                    sounio_claim_can_be_knowledge(&claim),
                    "knowledge claims require evidence_refs and non-empty provenance"
                );
                claim.review_state = "approved".to_string();
                claim.epistemic_status = "knowledge".to_string();
                claim.publication_readiness = "section_ready_with_provenance".to_string();
            }
            "promote_to_robust" => {
                anyhow::ensure!(
                    sounio_claim_can_be_robust(&claim),
                    "robust claims require multiple evidence refs and independent verification/replication provenance"
                );
                claim.review_state = "approved".to_string();
                claim.epistemic_status = "robust".to_string();
                claim.publication_readiness = "public_digest_ready".to_string();
            }
            _ => {
                claim.review_state = "approved".to_string();
                if claim.epistemic_status == "belief" && sounio_claim_can_be_knowledge(&claim) {
                    claim.epistemic_status = "knowledge".to_string();
                }
            }
        }
        claim.updated_at = Utc::now().to_rfc3339();
        claim.rationale = req.rationale.clone().or(claim.rationale.clone());
        let (errors, warnings) = validate_materialized_sounio_claim(&claim);
        anyhow::ensure!(
            errors.is_empty(),
            "Sounio claim review invalid: {}",
            errors.join("; ")
        );

        self.append_jsonl(SOUNIO_CLAIMS_LOG, &claim)?;
        let review = SounioClaimReview {
            id: Uuid::new_v4().to_string(),
            created_at: claim.updated_at.clone(),
            paper_run_id: paper_run_id.to_string(),
            claim_id: claim.id.clone(),
            reviewer: req.reviewer.unwrap_or_else(|| "demetrios".to_string()),
            decision: decision.clone(),
            rationale: req.rationale.clone(),
            previous_status,
            new_status: claim.epistemic_status.clone(),
            evidence_refs: claim.evidence_refs.clone(),
            provenance: serde_json::json!({
                "schema_version": SOUNIO_CLAIM_SCHEMA,
                "warnings": warnings,
                "publication_readiness": claim.publication_readiness
            }),
        };
        self.append_jsonl(SOUNIO_CLAIM_REVIEWS_LOG, &review)?;

        let claims = self.sounio_claims_for_paper_run(paper_run_id)?;
        run.updated_at = claim.updated_at.clone();
        run.current_stage = Some("claim_review".to_string());
        run.public_digest_status = Some("stale_after_claim_review".to_string());
        run.claim_lifecycle_status = claim_lifecycle_status(&claims);
        run.claim_registry = claims.iter().map(sounio_claim_summary).collect();
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;
        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: claim.updated_at.clone(),
            paper_run_id: paper_run_id.to_string(),
            program_id: run.sounio_program_id.clone(),
            step_id: "claim_review".to_string(),
            event_type: "sounio_claim_review".to_string(),
            status: claim.epistemic_status.clone(),
            summary: review.rationale.clone().or_else(|| {
                Some(format!(
                    "Claim {} reviewed as {}.",
                    claim.id, claim.epistemic_status
                ))
            }),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "review_id": review.id,
                "claim_id": claim.id,
                "decision": review.decision,
                "reviewer": review.reviewer
            }),
            artifact_refs: claim.artifact_refs.clone(),
        })?;
        Ok(claim)
    }

    fn sounio_claims_for_paper_run(&self, paper_run_id: &str) -> anyhow::Result<Vec<SounioClaim>> {
        let mut seen = BTreeSet::<String>::new();
        let mut claims = Vec::new();
        for claim in self.read_recent_jsonl::<SounioClaim>(SOUNIO_CLAIMS_LOG, usize::MAX)? {
            if claim.paper_run_id.as_deref() != Some(paper_run_id) {
                continue;
            }
            if seen.insert(claim.id.clone()) {
                claims.push(claim);
            }
        }
        claims.reverse();
        Ok(claims)
    }

    fn sounio_claim(
        &self,
        paper_run_id: &str,
        claim_id: &str,
    ) -> anyhow::Result<Option<SounioClaim>> {
        Ok(self
            .read_recent_jsonl::<SounioClaim>(SOUNIO_CLAIMS_LOG, usize::MAX)?
            .into_iter()
            .find(|claim| {
                claim.paper_run_id.as_deref() == Some(paper_run_id) && claim.id == claim_id
            }))
    }

    pub(crate) fn paper_run_theatre(
        &self,
        paper_run_id: &str,
    ) -> anyhow::Result<Option<PaperRunTheatreSnapshot>> {
        let run = match self.paper_run(paper_run_id)? {
            Some(run) => run,
            None => return Ok(None),
        };
        let claims = self.sounio_claims_for_paper_run(paper_run_id)?;
        let claim_graph = build_sounio_claim_graph(paper_run_id, claims);
        let trace_events = self.sounio_trace_events(SounioTraceQuery {
            paper_run_id: Some(paper_run_id.to_string()),
            limit: Some(100),
        })?;
        let artifacts = self
            .paper_run_artifacts(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun artifacts unavailable: {paper_run_id}"))?;
        let agent_contributions = sounio_agent_contributions(&trace_events, &claim_graph.claims);
        let approvals = sounio_approval_events(&trace_events);
        let evidence_table = sounio_evidence_table(&claim_graph.claims);
        let current_stage = run
            .current_stage
            .clone()
            .or_else(|| run.pending_approval_step.clone())
            .unwrap_or_else(|| run.status.clone());
        let next_action = if let Some(pending) = &run.pending_approval_step {
            format!("Review and approve PaperRun step '{pending}'.")
        } else if !claim_graph.unsupported_claim_ids.is_empty() {
            "Resolve unsupported Sounio claims before public digest export.".to_string()
        } else {
            "Generate public digest and draft the next manuscript section.".to_string()
        };
        Ok(Some(PaperRunTheatreSnapshot {
            paper_run_id: paper_run_id.to_string(),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_THEATRE_SCHEMA.to_string(),
            paper_run: run.clone(),
            manuscript_markdown: artifacts.manuscript_markdown,
            claim_graph: claim_graph.clone(),
            trace_events,
            agent_contributions,
            approvals,
            evidence_table,
            sounio_score: sounio_score(&claim_graph),
            current_stage,
            next_action,
            public_digest_status: run
                .public_digest_status
                .clone()
                .unwrap_or_else(|| "not_generated".to_string()),
            private_trace_ref: format!(
                "/orangefs/beagle-memory-lab/paperruns/{paper_run_id}/private_trace_pack.jsonl"
            ),
        }))
    }

    pub(crate) fn paper_run_public_digest(
        &self,
        paper_run_id: &str,
    ) -> anyhow::Result<Option<PublicDigestArtifact>> {
        let run = match self.paper_run(paper_run_id)? {
            Some(run) => run,
            None => return Ok(None),
        };
        let claims = self
            .sounio_claims_for_paper_run(paper_run_id)?
            .into_iter()
            .filter(|claim| claim.privacy_class != "restricted")
            .collect::<Vec<_>>();
        let trace_events = self.sounio_trace_events(SounioTraceQuery {
            paper_run_id: Some(paper_run_id.to_string()),
            limit: Some(40),
        })?;
        let digest = PublicDigestArtifact {
            paper_run_id: paper_run_id.to_string(),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_PUBLIC_DIGEST_SCHEMA.to_string(),
            title: run.title.clone(),
            thesis: "Beagle observes the agentic research process; Sounio types claims, evidence, provenance, and publication gates.".to_string(),
            sanitized_claims: claims.iter().map(sounio_public_claim_digest).collect(),
            sedenion_ssm_case: sedenion_ssm_public_case(&claims),
            public_trace_digest: trace_events
                .iter()
                .filter(|event| !event.provenance.to_string().to_lowercase().contains("restricted"))
                .take(12)
                .map(sounio_public_trace_digest)
                .collect(),
            disclosure:
                "AI agents are disclosed as instruments in the research workflow, not as authors. Human approval governs claims and publication."
                    .to_string(),
            excluded_private_trace_policy:
                "Full private traces, private corpus content, and restricted payloads remain cluster-only and are excluded from public exports."
                    .to_string(),
            manuscript_excerpt: truncate_chars(&paper_run_markdown(&run), 2_000),
        };
        let mut updated = run.clone();
        updated.updated_at = digest.generated_at.clone();
        updated.public_digest_status = Some("generated_sanitized".to_string());
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &updated)?;
        Ok(Some(digest))
    }

    pub(crate) fn start_paper_run(&self, req: StartPaperRunRequest) -> anyhow::Result<PaperRun> {
        self.ensure()?;
        let program = req
            .program
            .unwrap_or_else(default_beagle_self_writing_program);
        let check = self.check_sounio_program(SounioProgramCheckRequest {
            source_format: Some("json".to_string()),
            program: program.clone(),
        })?;
        anyhow::ensure!(
            check.status == "valid",
            "Sounio program invalid: {}",
            check.errors.join("; ")
        );
        let paper_id = req
            .paper_id
            .unwrap_or_else(|| "beagle-self-writing-systems-paper".to_string());
        let title = req.title.unwrap_or_else(default_beagle_paper_title);
        let principal = req.principal.unwrap_or_else(|| "demetrios".to_string());
        let surface = req
            .surface
            .unwrap_or_else(|| "beagle-sounio-paperrun".to_string());
        let temporal_namespace = req
            .temporal_namespace
            .or_else(|| env::var("SOUNIO_TEMPORAL_NAMESPACE").ok())
            .unwrap_or_else(|| "beagle".to_string());
        let temporal_task_queue = req
            .temporal_task_queue
            .or_else(|| env::var("SOUNIO_TEMPORAL_TASK_QUEUE").ok())
            .unwrap_or_else(|| "sounio-paperrun".to_string());
        let now = Utc::now().to_rfc3339();
        let run_id = Uuid::new_v4().to_string();
        let temporal_workflow_id = format!("sounio-paperrun-{}", run_id);
        let context_pack = self.context_compile(ContextCompileRequest {
            query: format!(
                "Beagle self-writing systems paper using Sounio Work IR, Temporal PaperRun, MCP, GraphRAG++, ContextPack, Apple surfaces: {}",
                title
            ),
            scope: Some("sounio-paperrun".to_string()),
            surface: Some(surface.clone()),
            task: Some("self-writing-systems-paper".to_string()),
            max_items: Some(8),
            mode: Some(memory_hot_path_mode()),
            token_budget: Some(16_000),
            agent: Some(principal.clone()),
            session_id: Some(run_id.clone()),
        })?;
        self.append_jsonl(SOUNIO_PROGRAMS_LOG, &program)?;
        let mut section_status = BTreeMap::new();
        for section in default_beagle_paper_sections() {
            section_status.insert(section.to_string(), "planned".to_string());
        }
        let pending_approval_step = program
            .plan
            .iter()
            .find(|step| step.requires_human_approval)
            .map(|step| step.id.clone());
        let artifact_refs = vec![
            format!("/orangefs/beagle-memory-lab/paperruns/{run_id}/manuscript.md"),
            format!("/orangefs/beagle-memory-lab/paperruns/{run_id}/provenance.json"),
            format!("/orangefs/beagle-memory-lab/paperruns/{run_id}/trace.jsonl"),
        ];
        let run = PaperRun {
            id: run_id.clone(),
            created_at: now.clone(),
            updated_at: now.clone(),
            schema_version: SOUNIO_PAPERRUN_SCHEMA.to_string(),
            paper_id,
            title,
            status: if pending_approval_step.is_some() {
                "human_approval_pending".to_string()
            } else {
                "queued".to_string()
            },
            temporal_workflow_id,
            temporal_namespace,
            temporal_task_queue,
            temporal_status: if req.dry_run.unwrap_or(false) {
                "dry_run_not_started".to_string()
            } else {
                "start_requested".to_string()
            },
            sounio_program_id: program.id.clone(),
            sounio_program_hash: check.program_hash.clone(),
            manuscript_version: "draft-0.1".to_string(),
            section_status,
            claim_registry: default_beagle_paper_claims(),
            citation_registry: default_beagle_paper_citations(),
            approval_state: if pending_approval_step.is_some() {
                "waiting_for_human".to_string()
            } else {
                "not_required".to_string()
            },
            pending_approval_step: pending_approval_step.clone(),
            context_pack_id: Some(context_pack.id.clone()),
            artifact_refs,
            provenance: serde_json::json!({
                "canonical_source": "/var/lib/beagle/exocortex",
                "artifact_root": "/orangefs/beagle-memory-lab/paperruns",
                "sounio_schema": SOUNIO_WORK_IR_SCHEMA,
                "temporal_worker": "sounio-runner",
                "context_pack_id": context_pack.id,
                "human_approval_required": true,
                "publication": "arxiv systems preprint, no automatic submission"
            }),
            interaction_summary: Some(
                "Beagle observes the paper process; Sounio types claims, evidence, and gates."
                    .to_string(),
            ),
            claim_lifecycle_status: default_beagle_paper_claims()
                .into_iter()
                .filter_map(|claim| {
                    let id = claim.get("id")?.as_str()?.to_string();
                    let status = claim
                        .get("status")
                        .and_then(|value| value.as_str())
                        .unwrap_or("needs_evidence")
                        .to_string();
                    Some((id, status))
                })
                .collect(),
            public_digest_status: Some("not_generated".to_string()),
            current_stage: Some(
                pending_approval_step
                    .clone()
                    .unwrap_or_else(|| "retrieve_state".to_string()),
            ),
        };
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;
        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: now.clone(),
            paper_run_id: run.id.clone(),
            program_id: program.id.clone(),
            step_id: "paperrun_start".to_string(),
            event_type: "workflow_start_requested".to_string(),
            status: run.temporal_status.clone(),
            summary: Some(
                "Sounio PaperRun created for Beagle self-writing systems paper.".to_string(),
            ),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "temporal_workflow_id": run.temporal_workflow_id,
                "program_hash": run.sounio_program_hash,
                "principal": principal,
                "surface": surface
            }),
            artifact_refs: run.artifact_refs.clone(),
        })?;
        let _ = self.create_memory_event(CreateMemoryEventRequest {
            source: Some("sounio-paperrun".to_string()),
            kind: Some("self_writing_paper_run".to_string()),
            content_ref: Some(format!("sounio_paperrun:{}", run.id)),
            summary: Some(format!("Started Sounio PaperRun for {}", run.title)),
            tags: vec![
                "sounio".to_string(),
                "paperrun".to_string(),
                "self-writing-paper".to_string(),
                "project:beagle".to_string(),
            ],
            metadata: Some(serde_json::json!({
                "paper_run_id": run.id,
                "temporal_workflow_id": run.temporal_workflow_id,
                "sounio_program_hash": run.sounio_program_hash,
                "context_pack_id": run.context_pack_id,
                "privacy_class": "sensitive"
            })),
            linked_chronoself_commits: Vec::new(),
            confidence: Some(0.88),
        })?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-core".to_string()),
            action: Some("sounio.paperrun_start".to_string()),
            tool_name: Some("beagle_sounio_paperrun_start".to_string()),
            risk_level: Some("run".to_string()),
            required_scopes: vec!["research:run".to_string()],
            granted_scopes: vec!["research:run".to_string()],
            status: Some("success".to_string()),
            source: Some("sounio-paperrun".to_string()),
            target_ref: Some(format!("sounio_paperrun:{}", run.id)),
            summary: Some("Started durable Sounio PaperRun scaffold.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": SOUNIO_PAPERRUN_SCHEMA,
                "temporal_workflow_id": run.temporal_workflow_id,
                "sounio_program_hash": run.sounio_program_hash,
                "context_pack_id": run.context_pack_id,
            })),
        })?;
        Ok(run)
    }

    pub(crate) fn paper_run(&self, paper_run_id: &str) -> anyhow::Result<Option<PaperRun>> {
        Ok(self
            .read_recent_jsonl::<PaperRun>(SOUNIO_PAPERRUNS_LOG, usize::MAX)?
            .into_iter()
            .find(|run| run.id == paper_run_id))
    }

    pub(crate) fn approve_paper_run_step(
        &self,
        paper_run_id: &str,
        req: ApprovePaperRunStepRequest,
    ) -> anyhow::Result<PaperRun> {
        self.ensure()?;
        let mut run = self
            .paper_run(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun not found: {paper_run_id}"))?;
        let decision = req.decision.unwrap_or_else(|| "approved".to_string());
        anyhow::ensure!(
            matches!(
                decision.as_str(),
                "approved" | "rejected" | "needs_revision"
            ),
            "approval decision must be approved, rejected, or needs_revision"
        );
        run.updated_at = Utc::now().to_rfc3339();
        run.approval_state = decision.clone();
        run.pending_approval_step = None;
        run.status = match decision.as_str() {
            "approved" => "approved_for_temporal_execution".to_string(),
            "needs_revision" => "revision_requested".to_string(),
            _ => "rejected".to_string(),
        };
        run.temporal_status = if decision == "approved" {
            "signal_approved".to_string()
        } else {
            "paused".to_string()
        };
        run.section_status
            .insert(req.step_id.clone(), decision.clone());
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;
        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: run.updated_at.clone(),
            paper_run_id: run.id.clone(),
            program_id: run.sounio_program_id.clone(),
            step_id: req.step_id.clone(),
            event_type: "human_approval".to_string(),
            status: decision.clone(),
            summary: req.rationale.clone(),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "reviewer": req.reviewer.unwrap_or_else(|| "demetrios".to_string()),
                "temporal_workflow_id": run.temporal_workflow_id,
                "approval_state": run.approval_state
            }),
            artifact_refs: run.artifact_refs.clone(),
        })?;
        Ok(run)
    }

    pub(crate) fn paper_run_artifacts(
        &self,
        paper_run_id: &str,
    ) -> anyhow::Result<Option<PaperRunArtifactsResponse>> {
        let run = match self.paper_run(paper_run_id)? {
            Some(run) => run,
            None => return Ok(None),
        };
        Ok(Some(PaperRunArtifactsResponse {
            paper_run_id: run.id.clone(),
            generated_at: Utc::now().to_rfc3339(),
            manuscript_markdown: paper_run_markdown(&run),
            provenance_pack: serde_json::json!({
                "paper_run": run,
                "source": "beagle-core-sounio-paperrun",
                "restricted_policy": "restricted content is excluded from manuscript/export",
                "publication_policy": "human approval required before external submission"
            }),
            artifact_refs: run.artifact_refs,
        }))
    }

    pub(crate) fn sounio_trace_events(
        &self,
        query: SounioTraceQuery,
    ) -> anyhow::Result<Vec<SounioTraceEvent>> {
        let limit = query.limit.unwrap_or(50).clamp(1, 500);
        let mut events =
            self.read_recent_jsonl::<SounioTraceEvent>(SOUNIO_TRACE_EVENTS_LOG, limit)?;
        if let Some(paper_run_id) = query.paper_run_id {
            events.retain(|event| event.paper_run_id == paper_run_id);
        }
        Ok(events)
    }
}
