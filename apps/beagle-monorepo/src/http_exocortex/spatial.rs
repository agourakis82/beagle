//! `spatial` exocortex HTTP handlers (split from the former god-file).
//!
//! Pure code movement: handlers call `super::ExocortexRepository` methods and shared
//! DTOs/helpers re-exported from the parent module. Behavior and route paths unchanged.

use super::*;

pub(crate) async fn spatial_world_marble_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateSpatialWorldRequest>,
) -> Result<Json<SpatialWorld>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let world = repo.create_spatial_world(req).map_err(internal_error)?;
    Ok(Json(world))
}

pub(crate) async fn spatial_world_get_handler(
    State(_state): State<AppState>,
    Path(world_id): Path<String>,
) -> Result<Json<SpatialWorld>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.spatial_world(&world_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

pub(crate) async fn spatial_world_assets_handler(
    State(_state): State<AppState>,
    Path(world_id): Path<String>,
) -> Result<Json<SpatialAssetManifest>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.spatial_world(&world_id)
        .map_err(internal_error)?
        .map(|world| Json(world.assets))
        .ok_or(StatusCode::NOT_FOUND)
}

pub(crate) async fn spatial_control_room_handler(
    State(_state): State<AppState>,
    Path(slug): Path<String>,
) -> Result<Json<ControlRoomSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.control_room_snapshot(&slug).map_err(internal_error)?;
    Ok(Json(snapshot))
}

pub(crate) async fn spatial_sounio_evidence_handler(
    State(_state): State<AppState>,
    Path(world_id): Path<String>,
    Json(req): Json<CreateSounioSpatialEvidenceRequest>,
) -> Result<Json<SounioSpatialEvidence>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let evidence = repo
        .create_spatial_evidence(&world_id, req)
        .map_err(internal_error)?;
    Ok(Json(evidence))
}

impl super::ExocortexRepository {
    pub(crate) fn create_spatial_world(
        &self,
        req: CreateSpatialWorldRequest,
    ) -> anyhow::Result<SpatialWorld> {
        self.ensure()?;
        let project_slug = req
            .project_slug
            .as_deref()
            .map(normalize_project_slug)
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let sanitized_prompt = req
            .sanitized_prompt
            .clone()
            .or(req.prompt_summary.clone())
            .unwrap_or_else(|| "Sounio Control Room spatial world".to_string());
        ensure_spatial_prompt_is_safe(&sanitized_prompt)?;
        anyhow::ensure!(
            req.approved.unwrap_or(false),
            "Marble world generation requires explicit approved=true metadata"
        );
        let model = normalize_marble_model(req.model.as_deref());
        let permission = normalize_marble_permission(req.permission.as_deref());
        anyhow::ensure!(
            permission != "public",
            "spatial worlds default to private/non-public Marble permissions"
        );
        let now = Utc::now().to_rfc3339();
        let prompt_hash = format!("sha256:{}", content_hash(sanitized_prompt.as_bytes()));
        let purpose = req
            .purpose
            .as_deref()
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .unwrap_or("control-room");
        let world_id = req.world_id.clone().unwrap_or_else(|| {
            stable_id(
                "spatial-world",
                &[&project_slug, purpose, &prompt_hash, &model],
            )
        });
        let assets = req.assets.unwrap_or_else(default_spatial_assets);
        let display_name = req
            .display_name
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| format!("{} Spatial Control Room", project_slug));
        let tags = dedupe_strings(
            req.tags
                .into_iter()
                .chain([
                    "spatial-control-room".to_string(),
                    "marble".to_string(),
                    format!("project:{}", project_slug),
                    "sounio-spatial-evidence".to_string(),
                ])
                .collect(),
            32,
        );
        let mut provenance = req.provenance.as_object().cloned().unwrap_or_default();
        provenance.insert(
            "schema_version".to_string(),
            serde_json::Value::String(SPATIAL_SCHEMA.to_string()),
        );
        provenance.insert(
            "canonical_truth".to_string(),
            serde_json::Value::String("JSONL/Merkle/Chronoself remains authoritative".to_string()),
        );
        provenance.insert(
            "derived_artifact".to_string(),
            serde_json::Value::Bool(true),
        );
        provenance.insert(
            "sanitized_prompt_only".to_string(),
            serde_json::Value::Bool(true),
        );
        let world = SpatialWorld {
            id: stable_id("spatial", &[&world_id, &prompt_hash]),
            created_at: now.clone(),
            updated_at: now,
            schema_version: SPATIAL_SCHEMA.to_string(),
            project_slug: project_slug.clone(),
            world_id: world_id.clone(),
            operation_id: req.operation_id,
            display_name,
            status: req.status.unwrap_or_else(|| "requested".to_string()),
            world_marble_url: req.world_marble_url,
            assets,
            model,
            permission,
            prompt_hash,
            prompt_summary: truncate_chars(&sanitized_prompt, 280),
            privacy_policy:
                "cluster-private derived artifact; private memory and raw logs are never sent to Marble"
                    .to_string(),
            tags,
            provenance: serde_json::Value::Object(provenance),
        };
        self.append_jsonl(SPATIAL_WORLDS_LOG, &world)?;
        let memory_world = self.spatial_memory_world(&world)?;
        self.append_jsonl(MEMORY_WORLDS_LOG, &memory_world)?;
        let event = MemoryEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: "spatial-control-room".to_string(),
            kind: "spatial_world".to_string(),
            content_ref: Some(format!("spatial_world:{}", world.world_id)),
            summary: format!(
                "Registered {} Marble spatial world for {}.",
                world.model, world.project_slug
            ),
            tags: world.tags.clone(),
            metadata: serde_json::json!({
                "world_id": world.world_id,
                "operation_id": world.operation_id,
                "prompt_hash": world.prompt_hash,
                "permission": world.permission,
                "privacy_policy": world.privacy_policy,
                "memory_world_id": memory_world.id
            }),
            linked_chronoself_commits: Vec::new(),
            confidence: 0.82,
        };
        self.append_jsonl(MEMORY_EVENTS_LOG, &event)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-spatial-api".to_string()),
            action: Some("spatial.world.register".to_string()),
            tool_name: None,
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("success".to_string()),
            source: Some("beagle-core".to_string()),
            target_ref: Some(format!("spatial_world:{}", world.world_id)),
            summary: Some("Registered Marble spatial world metadata.".to_string()),
            metadata: Some(serde_json::json!({
                "model": world.model,
                "permission": world.permission,
                "prompt_hash": world.prompt_hash,
                "sanitized_prompt_only": true
            })),
        })?;
        Ok(world)
    }

    fn spatial_world(&self, world_id: &str) -> anyhow::Result<Option<SpatialWorld>> {
        Ok(self
            .read_recent_jsonl::<SpatialWorld>(SPATIAL_WORLDS_LOG, usize::MAX)?
            .into_iter()
            .find(|world| world.world_id == world_id || world.id == world_id))
    }

    pub(crate) fn control_room_snapshot(&self, slug: &str) -> anyhow::Result<ControlRoomSnapshot> {
        self.ensure()?;
        let project_slug = normalize_project_slug(slug);
        let spatial_world = self
            .read_recent_jsonl::<SpatialWorld>(SPATIAL_WORLDS_LOG, usize::MAX)?
            .into_iter()
            .find(|world| world.project_slug == project_slug && world.permission != "public");
        let memory_worlds = self
            .read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, 24)?
            .into_iter()
            .filter(|world| {
                world
                    .tags
                    .iter()
                    .any(|tag| tag == &format!("project:{}", project_slug))
                    || world.provenance["project_slug"].as_str() == Some(project_slug.as_str())
            })
            .take(8)
            .collect::<Vec<_>>();
        let evidence_refs = self
            .read_recent_jsonl::<SounioSpatialEvidence>(SPATIAL_EVIDENCE_LOG, 24)?
            .into_iter()
            .filter(|evidence| {
                evidence.project_slug == project_slug && evidence.privacy_class != "restricted"
            })
            .map(|evidence| evidence.id)
            .take(8)
            .collect::<Vec<_>>();
        let agent_lanes = vec![
            "Builder: Claude/Codex".to_string(),
            "Code Worker: MiniMax/Qwen".to_string(),
            "Long Thought: Kimi".to_string(),
            "Platform Operator: GLM".to_string(),
            "Shell".to_string(),
        ];
        Ok(ControlRoomSnapshot {
            id: stable_id("control-room", &[&project_slug, SPATIAL_SCHEMA]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SPATIAL_SCHEMA.to_string(),
            project_slug: project_slug.clone(),
            spatial_world,
            memory_worlds,
            agent_lanes,
            pods_wall: vec![
                "beagle-core".to_string(),
                "beagle-mcp-server".to_string(),
                "beagle-workspace-agent".to_string(),
                "world-console".to_string(),
            ],
            incident_corridor: vec![
                "recent audit events".to_string(),
                "failed-write rescue".to_string(),
            ],
            compiler_map: vec![
                "Sounio IR".to_string(),
                "Claim<T>".to_string(),
                "Temporal PaperRun".to_string(),
            ],
            evidence_refs,
            provenance: serde_json::json!({
                "source": "beagle-core-spatial",
                "schema_version": SPATIAL_SCHEMA,
                "canonical_store": "/var/lib/beagle/exocortex",
                "surface": "visionOS"
            }),
        })
    }

    pub(crate) fn create_spatial_evidence(
        &self,
        world_id: &str,
        req: CreateSounioSpatialEvidenceRequest,
    ) -> anyhow::Result<SounioSpatialEvidence> {
        self.ensure()?;
        let world = self
            .spatial_world(world_id)?
            .ok_or_else(|| anyhow::anyhow!("spatial world not found: {}", world_id))?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted spatial evidence requires explicit local review before cluster write"
        );
        let epistemic_status = normalize_epistemic_status(req.epistemic_status.as_deref());
        anyhow::ensure!(
            epistemic_status == "belief" || epistemic_status == "contest",
            "spatial worlds can seed belief/contest claims only"
        );
        let now = Utc::now().to_rfc3339();
        let evidence = SounioSpatialEvidence {
            id: stable_id(
                "spatial-evidence",
                &[&world.world_id, &req.project_slug, &now],
            ),
            created_at: now,
            schema_version: SPATIAL_SCHEMA.to_string(),
            world_id: world.world_id.clone(),
            project_slug: normalize_project_slug(&req.project_slug),
            evidence_type: req
                .evidence_type
                .unwrap_or_else(|| "spatial_memory_world".to_string()),
            claim_seed_refs: dedupe_strings(req.claim_seed_refs, 32),
            memory_world_refs: dedupe_strings(req.memory_world_refs, 32),
            artifact_refs: dedupe_strings(req.artifact_refs, 32),
            epistemic_status,
            privacy_class,
            provenance: serde_json::json!({
                "world_id": world.world_id,
                "spatial_world_ref": world.id,
                "input": req.provenance,
                "claim_policy": "belief_or_contest_only",
                "restricted_leak_check": "passed:no_restricted_spatial_evidence"
            }),
        };
        self.append_jsonl(SPATIAL_EVIDENCE_LOG, &evidence)?;
        let event = MemoryEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: "sounio-spatial-evidence".to_string(),
            kind: "spatial_evidence".to_string(),
            content_ref: Some(evidence.id.clone()),
            summary: format!(
                "Linked spatial world {} as Sounio {} evidence.",
                evidence.world_id, evidence.epistemic_status
            ),
            tags: vec![
                "spatial-evidence".to_string(),
                "sounio".to_string(),
                format!("project:{}", evidence.project_slug),
            ],
            metadata: serde_json::json!({
                "world_id": evidence.world_id,
                "epistemic_status": evidence.epistemic_status,
                "claim_seed_refs": evidence.claim_seed_refs,
                "memory_world_refs": evidence.memory_world_refs
            }),
            linked_chronoself_commits: Vec::new(),
            confidence: 0.78,
        };
        self.append_jsonl(MEMORY_EVENTS_LOG, &event)?;
        Ok(evidence)
    }

    fn spatial_memory_world(&self, world: &SpatialWorld) -> anyhow::Result<MemoryWorld> {
        let material = vec![
            world.world_id.clone(),
            world.prompt_hash.clone(),
            serde_json::to_string(&world.assets)?,
        ];
        Ok(MemoryWorld {
            id: stable_id("world", &[&world.world_id, &world.prompt_hash]),
            created_at: Utc::now().to_rfc3339(),
            world_type: "spatial-control-room".to_string(),
            source_ref: format!("spatial_world:{}", world.world_id),
            title: Some(world.display_name.clone()),
            merkle_root: merkle_hash(&material),
            valid_from: Some(world.created_at.clone()),
            valid_until: None,
            node_count: 6,
            edge_count: 8,
            runtime_hint: "visionOS+Marble".to_string(),
            tags: world.tags.clone(),
            provenance: serde_json::json!({
                "source": "SpatialWorld",
                "schema_version": SPATIAL_SCHEMA,
                "project_slug": world.project_slug,
                "world_id": world.world_id,
                "content_addressed": true,
                "derived_artifact": true,
                "canonical_store": "/var/lib/beagle/exocortex"
            }),
        })
    }
}
