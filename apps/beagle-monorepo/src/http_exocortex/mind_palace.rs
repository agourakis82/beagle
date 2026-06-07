//! `mind_palace` exocortex HTTP handlers (split from the former god-file).
//!
//! Pure code movement: handlers call `super::ExocortexRepository` methods and shared
//! DTOs/helpers re-exported from the parent module. Behavior and route paths unchanged.

use super::*;

pub(crate) async fn mind_palace_handler(
    State(_state): State<AppState>,
) -> Result<Json<MindPalaceSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot))
}

pub(crate) async fn mind_palace_rooms_handler(
    State(_state): State<AppState>,
) -> Result<Json<Vec<MindPalaceRoom>>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.rooms))
}

pub(crate) async fn mind_palace_desk_handler(
    State(_state): State<AppState>,
) -> Result<Json<SpatialDeskSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.desk))
}

pub(crate) async fn mind_palace_next_best_place_handler(
    State(_state): State<AppState>,
) -> Result<Json<NextBestPlaceDecision>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.next_best_place))
}

pub(crate) async fn mind_palace_action_menu_handler(
    State(_state): State<AppState>,
) -> Result<Json<SpatialActionMenu>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.action_menu))
}

pub(crate) async fn conversation_portal_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateConversationPortalRequest>,
) -> Result<Json<ConversationPortal>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let portal = repo
        .create_conversation_portal(req)
        .map_err(internal_error)?;
    Ok(Json(portal))
}

pub(crate) async fn conversation_portal_promote_handler(
    State(_state): State<AppState>,
    Path(portal_id): Path<String>,
    Json(req): Json<PromoteConversationPortalRequest>,
) -> Result<Json<PromotedConversationClip>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let clip = repo
        .promote_conversation_portal_clip(&portal_id, req)
        .map_err(internal_error)?;
    Ok(Json(clip))
}

pub(crate) async fn focus_coach_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<FocusCoachState>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let state = repo.focus_coach_status().map_err(internal_error)?;
    Ok(Json(state))
}

pub(crate) async fn focus_coach_event_handler(
    State(_state): State<AppState>,
    Json(req): Json<FocusCoachEventRequest>,
) -> Result<Json<FocusCoachState>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let state = repo.record_focus_coach_event(req).map_err(internal_error)?;
    Ok(Json(state))
}

impl super::ExocortexRepository {
    pub(crate) fn mind_palace_snapshot(&self) -> anyhow::Result<MindPalaceSnapshot> {
        self.ensure()?;
        let rooms = self.derive_mind_palace_rooms()?;
        let focus_coach = self.focus_coach_status()?;
        let portals = self.conversation_portals_recent(8)?;
        let desk = self.spatial_desk_snapshot(&rooms, portals, &focus_coach)?;
        let next_best_place = self.next_best_place_decision(&rooms, &focus_coach)?;
        let action_menu = self.spatial_action_menu(&rooms, &next_best_place, &focus_coach)?;
        Ok(MindPalaceSnapshot {
            id: stable_id("mind-palace", &[MIND_PALACE_SCHEMA, "memory-derived"]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MIND_PALACE_SCHEMA.to_string(),
            rooms,
            desk,
            next_best_place,
            action_menu,
            focus_coach,
            provenance: serde_json::json!({
                "source": "cluster-jsonl-derived",
                "canonical_store": "/var/lib/beagle/exocortex",
                "surface": "ipad+visionos",
                "policy": "Mission Control + Spatial Desk + Portal Promote",
                "sounio_is_one_room_not_the_whole_palace": true
            }),
        })
    }

    fn derive_mind_palace_rooms(&self) -> anyhow::Result<Vec<MindPalaceRoom>> {
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 96)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 96)?;
        let moments = self.read_recent_jsonl::<SounioMoment>(SOUNIO_MOMENTS_LOG, 48)?;
        let worlds = self.read_recent_jsonl::<SpatialWorld>(SPATIAL_WORLDS_LOG, 24)?;
        let paper_runs = self.read_recent_jsonl::<PaperRun>(SOUNIO_PAPERRUNS_LOG, 12)?;
        let portals = self.conversation_portals_recent(24)?;
        let mut rooms: BTreeMap<String, MindPalaceRoom> = BTreeMap::new();

        for event in memory_events.iter().filter(|event| {
            metadata_string(&event.metadata, "privacy_class").as_deref() != Some("restricted")
        }) {
            for tag in event
                .tags
                .iter()
                .filter_map(|tag| tag.strip_prefix("project:"))
            {
                let slug = normalize_project_slug(tag);
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_project_room(
                        &slug,
                        "memory-events",
                        Some(format!("memory_event:{}", event.id)),
                        if event.source.contains("work") || event.kind.contains("import") {
                            0.86
                        } else {
                            0.68
                        },
                    ),
                );
            }
            if event.source.contains("codex")
                || event.source.contains("claude")
                || event.source.contains("workbench")
                || event.tags.iter().any(|tag| tag.contains("agent:"))
            {
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_room(
                        "parallel-work",
                        "Parallel Workbench",
                        "workspace",
                        "active",
                        None,
                        "agent work memory",
                        "Many agents can make progress while conversation continues elsewhere.",
                        "Open the Workbench drawer and inspect the latest remembered block.",
                        0.91,
                        Some(format!("memory_event:{}", event.id)),
                        vec!["workbench".to_string(), "agents".to_string()],
                    ),
                );
            }
        }

        for import in imports
            .iter()
            .filter(|import| import.privacy_class != "restricted")
        {
            for project in &import.extracted.projects_mentioned {
                let slug = normalize_project_slug(project);
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_project_room(
                        &slug,
                        &format!("{} import", import.source_platform),
                        Some(format!("omnimemory:{}", import.id)),
                        0.74,
                    ),
                );
            }
            if import.tags.iter().any(|tag| {
                tag.contains("claude") || tag.contains("chatgpt") || tag.contains("grok")
            }) {
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_room(
                        "free-thought",
                        "Free Thought",
                        "conversation",
                        "open",
                        None,
                        "conversation imports",
                        "Not every useful thought belongs to a project immediately.",
                        "Keep the thread available, then promote only the useful clips.",
                        0.73,
                        Some(format!("omnimemory:{}", import.id)),
                        vec!["free_thought".to_string(), "conversation".to_string()],
                    ),
                );
            }
        }

        for moment in moments
            .iter()
            .filter(|moment| moment.privacy_class != "restricted")
        {
            let slug = normalize_project_slug(&moment.project_slug);
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_project_room(
                    &slug,
                    "Sounio moments",
                    Some(format!("sounio_moment:{}", moment.id)),
                    0.88,
                ),
            );
        }

        for world in worlds.iter().filter(|world| world.permission != "public") {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "spatial-forge",
                    "Spatial Forge",
                    "spatial",
                    &world.status,
                    Some(world.project_slug.clone()),
                    "spatial worlds",
                    "Worlds are powerful evidence surfaces, but they are still derived artifacts.",
                    "Review generated assets and link only sanitized spatial evidence.",
                    0.79,
                    Some(format!("spatial_world:{}", world.world_id)),
                    vec![
                        "spatial".to_string(),
                        "world-console".to_string(),
                        format!("project:{}", world.project_slug),
                    ],
                ),
            );
        }

        for run in paper_runs {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "paper-theatre",
                    "Paper Theatre",
                    "paper",
                    run.status.as_str(),
                    Some("beagle".to_string()),
                    "PaperRun",
                    "The paper should be a living trace of the system, not a detached artifact.",
                    run.pending_approval_step
                        .as_deref()
                        .or(run.current_stage.as_deref())
                        .unwrap_or("Open PaperRun Theatre and review unsupported claims."),
                    0.7,
                    Some(format!("paperrun:{}", run.id)),
                    vec!["paperrun".to_string(), "sounio".to_string()],
                ),
            );
        }

        if !portals.is_empty() {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "conversation-portals",
                    "Conversation Portals",
                    "portal",
                    "available",
                    None,
                    "Claude/GPT desktop portals",
                    "Portals are reference windows until you explicitly promote a clip.",
                    "Promote only the useful selected idea, not the whole external conversation.",
                    0.84,
                    portals
                        .first()
                        .map(|portal| format!("portal:{}", portal.id)),
                    vec!["portal".to_string(), "promote".to_string()],
                ),
            );
        }

        if rooms.is_empty() {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "free-thought",
                    "Free Thought",
                    "conversation",
                    "seed",
                    None,
                    "declared seed",
                    "The palace starts open until live memory supplies stronger rooms.",
                    "Capture or promote the next useful thought.",
                    0.62,
                    None,
                    vec!["free_thought".to_string()],
                ),
            );
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_project_room("beagle", "declared seed", None, 0.6),
            );
        }

        let mut out = rooms.into_values().collect::<Vec<_>>();
        out.sort_by(|a, b| {
            b.priority
                .partial_cmp(&a.priority)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.title.cmp(&b.title))
        });
        out.truncate(12);
        Ok(out)
    }

    fn spatial_desk_snapshot(
        &self,
        rooms: &[MindPalaceRoom],
        portals: Vec<ConversationPortal>,
        focus: &FocusCoachState,
    ) -> anyhow::Result<SpatialDeskSnapshot> {
        let mut items = Vec::new();
        for room in rooms.iter().take(6) {
            items.push(DeskItem {
                id: stable_id("desk-item", &[&room.id, &room.state]),
                kind: room.room_type.clone(),
                title: room.title.clone(),
                detail: room.tension.clone(),
                state: room.state.clone(),
                priority: room.priority,
                room_id: Some(room.id.clone()),
                source_ref: room.evidence_refs.first().cloned(),
                actions: vec![
                    "open".to_string(),
                    "prove".to_string(),
                    "promote".to_string(),
                ],
                provenance: serde_json::json!({
                    "source": "mind_palace_room",
                    "truth_mode": room.truth_mode
                }),
            });
        }
        for portal in portals.iter().take(4) {
            items.push(DeskItem {
                id: stable_id("desk-portal", &[&portal.id, &portal.updated_at]),
                kind: "conversation_portal".to_string(),
                title: portal.title.clone(),
                detail: format!(
                    "{} portal via {}; promote explicit clips only.",
                    portal.provider, portal.source_mode
                ),
                state: portal.status.clone(),
                priority: 0.78,
                room_id: Some("conversation-portals".to_string()),
                source_ref: Some(format!("conversation_portal:{}", portal.id)),
                actions: vec!["open_portal".to_string(), "promote_clip".to_string()],
                provenance: serde_json::json!({
                    "provider": portal.provider,
                    "privacy_class": portal.privacy_class,
                    "no_scraping": true
                }),
            });
        }
        Ok(SpatialDeskSnapshot {
            id: stable_id("spatial-desk", &[MIND_PALACE_SCHEMA, "mission-control"]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MIND_PALACE_SCHEMA.to_string(),
            active_items: items,
            pinned_room_ids: rooms.iter().take(4).map(|room| room.id.clone()).collect(),
            portals,
            agent_lanes: spatial_desk_agent_lanes(),
            focus_strip: focus
                .interventions
                .iter()
                .take(3)
                .map(|intervention| intervention.title.clone())
                .collect(),
            proof_panels: vec![
                "Memory provenance".to_string(),
                "Portal promotions".to_string(),
                "Spatial artifact policy".to_string(),
            ],
            provenance: serde_json::json!({
                "source": "beagle-core",
                "layout": "Spatial Desk",
                "entry": "Command First",
                "cluster_only": true
            }),
        })
    }

    fn next_best_place_decision(
        &self,
        rooms: &[MindPalaceRoom],
        focus: &FocusCoachState,
    ) -> anyhow::Result<NextBestPlaceDecision> {
        let selected = rooms
            .iter()
            .find(|room| room.id == "parallel-work" || room.state == "active")
            .or_else(|| rooms.first())
            .cloned()
            .unwrap_or_else(|| {
                mind_palace_room(
                    "free-thought",
                    "Free Thought",
                    "conversation",
                    "seed",
                    None,
                    "fallback",
                    "No live room has enough evidence yet.",
                    "Capture the next useful thought.",
                    0.5,
                    None,
                    vec!["free_thought".to_string()],
                )
            });
        Ok(NextBestPlaceDecision {
            id: stable_id("next-best-place", &[&selected.id, &selected.state]),
            generated_at: Utc::now().to_rfc3339(),
            room_id: selected.id.clone(),
            title: selected.title.clone(),
            reason: format!(
                "{} Continuity says this room is live; readiness says {}.",
                selected.next_action, focus.mode
            ),
            source_mode: "continuity+readiness".to_string(),
            confidence: (selected.priority * 0.92).clamp(0.0, 0.96),
            candidate_room_ids: rooms.iter().take(5).map(|room| room.id.clone()).collect(),
            readiness_context: serde_json::json!({
                "focus_mode": focus.mode,
                "hydration_due": focus.hydration_due,
                "session_minutes": focus.session_minutes,
                "can_override": focus.can_override
            }),
        })
    }

    fn spatial_action_menu(
        &self,
        rooms: &[MindPalaceRoom],
        next: &NextBestPlaceDecision,
        focus: &FocusCoachState,
    ) -> anyhow::Result<SpatialActionMenu> {
        let portal_enabled = rooms.iter().any(|room| room.id == "conversation-portals");
        Ok(SpatialActionMenu {
            id: stable_id("spatial-action-menu", &[MIND_PALACE_SCHEMA, &next.room_id]),
            generated_at: Utc::now().to_rfc3339(),
            mode: "parallel-spaces".to_string(),
            actions: vec![
                SpatialAction {
                    id: "continue-place".to_string(),
                    title: "Continue".to_string(),
                    kind: "open_room".to_string(),
                    target_ref: Some(next.room_id.clone()),
                    reason: next.reason.clone(),
                    enabled: true,
                },
                SpatialAction {
                    id: "open-workbench".to_string(),
                    title: "Open Workbench".to_string(),
                    kind: "open_workbench".to_string(),
                    target_ref: Some("workspace:sounio".to_string()),
                    reason: "Keep coding agents visible while planning and chatting elsewhere."
                        .to_string(),
                    enabled: true,
                },
                SpatialAction {
                    id: "reflect".to_string(),
                    title: "Reflect".to_string(),
                    kind: "open_memory_lens".to_string(),
                    target_ref: None,
                    reason: "Open Memory Lens / proof panels without stopping the workspace."
                        .to_string(),
                    enabled: true,
                },
                SpatialAction {
                    id: "promote-portal".to_string(),
                    title: "Promote Portal".to_string(),
                    kind: "promote_conversation_clip".to_string(),
                    target_ref: Some("conversation-portals".to_string()),
                    reason: "Turn a selected Claude/GPT idea into memory explicitly.".to_string(),
                    enabled: portal_enabled,
                },
                SpatialAction {
                    id: "generate-space".to_string(),
                    title: "Generate Space".to_string(),
                    kind: "spatial_generation_draft".to_string(),
                    target_ref: Some("spatial-forge".to_string()),
                    reason:
                        "Draft a sanitized spatial world or asset request before any paid generation."
                            .to_string(),
                    enabled: true,
                },
                SpatialAction {
                    id: "focus-coach".to_string(),
                    title: "Focus Coach".to_string(),
                    kind: "focus_intervention".to_string(),
                    target_ref: focus.interventions.first().map(|item| item.id.clone()),
                    reason: "Calendar, hydration, breaks, and closure keep the exocortex humane."
                        .to_string(),
                    enabled: true,
                },
            ],
        })
    }

    fn conversation_portals_recent(&self, limit: usize) -> anyhow::Result<Vec<ConversationPortal>> {
        let mut seen = BTreeSet::new();
        Ok(self
            .read_recent_jsonl::<ConversationPortal>(CONVERSATION_PORTALS_LOG, limit.max(32))?
            .into_iter()
            .filter(|portal| portal.privacy_class != "restricted")
            .filter(|portal| seen.insert(portal.id.clone()))
            .take(limit)
            .collect())
    }

    pub(crate) fn create_conversation_portal(
        &self,
        req: CreateConversationPortalRequest,
    ) -> anyhow::Result<ConversationPortal> {
        self.ensure()?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted portals must stay local/review-only and cannot be written to cluster"
        );
        let title = truncate_chars(req.title.trim(), 120);
        anyhow::ensure!(!title.is_empty(), "conversation portal title is required");
        let provider = normalize_provider_label(&req.provider);
        let surface = req
            .surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "desktop-portal".to_string());
        let now = Utc::now().to_rfc3339();
        let portal = ConversationPortal {
            id: stable_id("portal", &[&title, &provider, &surface, &now]),
            created_at: now.clone(),
            updated_at: now,
            schema_version: CONVERSATION_PORTAL_SCHEMA.to_string(),
            title,
            provider,
            surface,
            status: req.status.unwrap_or_else(|| "reference_only".to_string()),
            source_mode: req
                .source_mode
                .unwrap_or_else(|| "portal+promote".to_string()),
            privacy_class,
            source_ref: req.source_ref,
            promoted_clip_refs: Vec::new(),
            tags: dedupe_strings(
                req.tags
                    .into_iter()
                    .chain([
                        "conversation-portal".to_string(),
                        "portal-promote".to_string(),
                    ])
                    .collect(),
                32,
            ),
            provenance: merge_json_objects(
                serde_json::json!({
                    "schema_version": CONVERSATION_PORTAL_SCHEMA,
                    "no_scraping": true,
                    "promotion_required_for_memory": true
                }),
                req.provenance,
            ),
        };
        self.append_jsonl(CONVERSATION_PORTALS_LOG, &portal)?;
        Ok(portal)
    }

    pub(crate) fn promote_conversation_portal_clip(
        &self,
        portal_id: &str,
        req: PromoteConversationPortalRequest,
    ) -> anyhow::Result<PromotedConversationClip> {
        self.ensure()?;
        let mut portal = self
            .read_recent_jsonl::<ConversationPortal>(CONVERSATION_PORTALS_LOG, usize::MAX)?
            .into_iter()
            .find(|portal| portal.id == portal_id)
            .ok_or_else(|| anyhow::anyhow!("conversation portal not found: {portal_id}"))?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted portal clips require local review and cannot be promoted automatically"
        );
        ensure_promoted_clip_is_safe(&req.selected_text)?;
        let content_hash = format!("sha256:{}", content_hash(req.selected_text.as_bytes()));
        let summary = req
            .summary
            .as_deref()
            .map(|value| truncate_chars(value.trim(), 360))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| truncate_chars(&req.selected_text, 240));
        let project_ref = req
            .project_ref
            .as_deref()
            .map(normalize_project_slug)
            .filter(|value| !value.is_empty())
            .or_else(|| Some("free_thought".to_string()));
        let mut tags = dedupe_strings(
            req.tags
                .clone()
                .into_iter()
                .chain(portal.tags.clone())
                .chain([
                    "conversation-portal".to_string(),
                    "promoted-clip".to_string(),
                    format!("provider:{}", portal.provider),
                    format!("privacy:{}", privacy_class),
                ])
                .collect(),
            32,
        );
        if let Some(project) = &project_ref {
            merge_unique(&mut tags, vec![format!("project:{}", project)], 32);
        }
        let import = self.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: portal.provider.clone(),
            source_surface: portal.surface.clone(),
            import_scope: "promoted_conversation_clip".to_string(),
            session_id: format!("portal-{}", portal.id),
            project_ref: project_ref.clone(),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "user".to_string(),
                content: req.selected_text.clone(),
                timestamp: Some(Utc::now().to_rfc3339()),
                model: None,
            }],
            tags: tags.clone(),
            metadata: merge_json_objects(
                serde_json::json!({
                    "principal": "demetrios",
                    "surface_observed": "portal+promote",
                    "portal_id": portal.id,
                    "content_hash": content_hash.clone(),
                    "explicit_selection": true,
                    "no_window_scraping": true
                }),
                req.provenance.clone(),
            ),
            coverage: serde_json::json!({
                "portal_promote": true,
                "selected_clip_only": true
            }),
            extracted: Some(OmniExtraction {
                key_insights: vec![summary.clone()],
                decisions: Vec::new(),
                hypotheses: Vec::new(),
                belief_changes: Vec::new(),
                emotional_state: None,
                identity_signals: None,
                projects_mentioned: project_ref.clone().into_iter().collect(),
                unresolved_questions: Vec::new(),
            }),
            privacy_class: Some(privacy_class.clone()),
            title: Some(format!("Promoted {} portal clip", portal.provider)),
            original_date: Some(Utc::now().to_rfc3339()),
            confidence_score: Some(0.82),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })?;
        let now = Utc::now().to_rfc3339();
        let clip = PromotedConversationClip {
            id: stable_id("portal-clip", &[&portal.id, &content_hash]),
            created_at: now.clone(),
            schema_version: CONVERSATION_PORTAL_SCHEMA.to_string(),
            portal_id: portal.id.clone(),
            content_hash,
            summary,
            project_ref,
            privacy_class,
            memory_event_id: import.memory_event.as_ref().map(|event| event.id.clone()),
            sounio_moment_id: import
                .sounio_moment
                .as_ref()
                .map(|moment| moment.id.clone()),
            tags,
            provenance: serde_json::json!({
                "portal": portal,
                "assisted_import_status": import.status,
                "explicit_selection_only": true,
                "restricted_leak_check": "passed:no_restricted_portal_clip"
            }),
        };
        self.append_jsonl(PROMOTED_CONVERSATION_CLIPS_LOG, &clip)?;
        portal.updated_at = now;
        portal.status = "promoted".to_string();
        merge_unique(
            &mut portal.promoted_clip_refs,
            vec![format!("promoted_clip:{}", clip.id)],
            48,
        );
        self.append_jsonl(CONVERSATION_PORTALS_LOG, &portal)?;
        Ok(clip)
    }

    fn focus_coach_status(&self) -> anyhow::Result<FocusCoachState> {
        self.ensure()?;
        let events = self.read_recent_jsonl::<FocusCoachEvent>(FOCUS_COACH_EVENTS_LOG, 48)?;
        let active_start = events
            .iter()
            .find(|event| event.event_kind == "start_focus" && event.status != "ended");
        let session_minutes = active_start
            .and_then(|event| chrono::DateTime::parse_from_rfc3339(&event.created_at).ok())
            .map(|started| {
                (Utc::now() - started.with_timezone(&Utc))
                    .num_minutes()
                    .max(0) as u32
            })
            .unwrap_or(0);
        let latest_snooze = events
            .iter()
            .find(|event| event.event_kind == "snooze")
            .and_then(|event| event.snoozed_minutes)
            .unwrap_or(0);
        let hydration_due = session_minutes >= 35 && latest_snooze == 0;
        let mut interventions = Vec::new();
        if session_minutes >= 75 {
            interventions.push(FocusIntervention {
                id: "close-loop-break".to_string(),
                kind: "break".to_string(),
                title: "Close loop, then pause".to_string(),
                reason: "This focus block is long enough that memory quality and body state benefit from a short closure.".to_string(),
                priority: 0.94,
                status: "suggested".to_string(),
                due_at: None,
                actions: vec!["summarize".to_string(), "hydrate".to_string(), "pause".to_string()],
            });
        } else if hydration_due {
            interventions.push(FocusIntervention {
                id: "hydrate".to_string(),
                kind: "hydration".to_string(),
                title: "Water + posture check".to_string(),
                reason: "Gentle physiological upkeep while agents keep running.".to_string(),
                priority: 0.72,
                status: "suggested".to_string(),
                due_at: None,
                actions: vec!["drink_water".to_string(), "snooze".to_string()],
            });
        }
        interventions.push(FocusIntervention {
            id: "calendar-guard".to_string(),
            kind: "calendar".to_string(),
            title: "Calendar guard".to_string(),
            reason: "Keep commitments visible while parallel workspaces run.".to_string(),
            priority: 0.64,
            status: "available".to_string(),
            due_at: None,
            actions: vec!["open_calendar".to_string(), "snooze".to_string()],
        });
        let mode = if session_minutes >= 75 {
            "recovering"
        } else if session_minutes >= 25 {
            "focused"
        } else {
            "available"
        };
        Ok(FocusCoachState {
            id: stable_id("focus-coach", &[FOCUS_COACH_SCHEMA, mode]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: FOCUS_COACH_SCHEMA.to_string(),
            mode: mode.to_string(),
            active_session: active_start.map(|event| FocusSession {
                id: stable_id(
                    "focus-session",
                    &[
                        &event.created_at,
                        event.project_slug.as_deref().unwrap_or("free"),
                    ],
                ),
                started_at: event.created_at.clone(),
                ended_at: None,
                mode: "focus".to_string(),
                project_slug: event.project_slug.clone(),
                status: "active".to_string(),
                notes: event.notes.clone().into_iter().collect(),
                provenance: event.provenance.clone(),
            }),
            interventions,
            hydration_due,
            calendar_nudge: Some("Keep real commitments visible beside agent work.".to_string()),
            session_minutes,
            can_override: true,
            provenance: serde_json::json!({
                "schema_version": FOCUS_COACH_SCHEMA,
                "not_medical_advice": true,
                "operator_can_override": true,
                "source": "focus_coach_events.jsonl"
            }),
        })
    }

    pub(crate) fn record_focus_coach_event(
        &self,
        req: FocusCoachEventRequest,
    ) -> anyhow::Result<FocusCoachState> {
        self.ensure()?;
        let event_kind = req.event_kind.trim().to_lowercase().replace('-', "_");
        anyhow::ensure!(!event_kind.is_empty(), "focus coach event_kind is required");
        let event = FocusCoachEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: FOCUS_COACH_SCHEMA.to_string(),
            event_kind,
            status: req.status.unwrap_or_else(|| "recorded".to_string()),
            intervention_id: req.intervention_id,
            project_slug: req.project_slug.map(|value| normalize_project_slug(&value)),
            notes: req.notes.map(|value| truncate_chars(value.trim(), 500)),
            snoozed_minutes: req.snoozed_minutes,
            provenance: merge_json_objects(
                serde_json::json!({
                    "source": "beagle-focus-coach",
                    "operator_can_override": true
                }),
                req.provenance,
            ),
        };
        self.append_jsonl(FOCUS_COACH_EVENTS_LOG, &event)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-focus-coach".to_string()),
            action: Some("focus_coach.event".to_string()),
            tool_name: None,
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("success".to_string()),
            source: Some("focus-coach".to_string()),
            target_ref: Some(format!("focus_event:{}", event.id)),
            summary: Some(format!("Recorded focus coach event {}.", event.event_kind)),
            metadata: Some(serde_json::json!({
                "schema_version": FOCUS_COACH_SCHEMA,
                "event_kind": event.event_kind,
                "project_slug": event.project_slug,
                "snoozed_minutes": event.snoozed_minutes
            })),
        })?;
        self.focus_coach_status()
    }
}
