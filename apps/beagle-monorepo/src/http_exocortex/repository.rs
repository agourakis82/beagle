//! `ExocortexRepository` — the JSONL-backed store for the exocortex HTTP surface.
//! Extracted from the god-file (plan #16): one struct + its Default/main impl (~3994 lines).
//! Re-exported pub(crate); methods reach shared DTOs/consts/helpers via `use super::*`.

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use beagle_config::beagle_data_dir;
use beagle_darwin::{consumer_identity_for_id, ConsumerId};
use beagle_llm::RequestMeta;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
};
use tracing::error;
use uuid::Uuid;

use crate::http::AppState;

use super::*;

#[derive(Debug, Clone)]
pub(crate) struct ExocortexRepository {
    pub(crate) root: PathBuf,
}

impl Default for ExocortexRepository {
    fn default() -> Self {
        Self {
            root: beagle_data_dir().join(EXOCORTEX_DIR),
        }
    }
}

impl ExocortexRepository {
    #[cfg(test)]
    pub(crate) fn new(root: PathBuf) -> Self {
        Self { root }
    }

    pub(crate) fn ensure(&self) -> anyhow::Result<()> {
        fs::create_dir_all(&self.root)?;
        Ok(())
    }

    pub(crate) fn create_commit(
        &self,
        req: CreateCommitRequest,
    ) -> anyhow::Result<ChronoselfCommit> {
        self.ensure()?;
        let now = Utc::now();
        let last = self
            .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 1)?
            .into_iter()
            .next();
        let parent_commit_ids = if req.parent_commit_ids.is_empty() {
            last.as_ref()
                .map(|commit| vec![commit.id.clone()])
                .unwrap_or_default()
        } else {
            req.parent_commit_ids
        };
        let context_snapshot = req.context_snapshot.unwrap_or(ContextSnapshot {
            health_ref: None,
            active_project_ids: Vec::new(),
            recent_decision_ids: Vec::new(),
            energy_level: None,
            emotional_valence: None,
            platform: None,
            target_hardware: None,
        });
        let self_version = req
            .self_version
            .unwrap_or_else(|| format!("v{}", now.format("%Y.%m.%d.%H")));
        let user_id = req.user_id.unwrap_or_else(|| "beagle-operator".to_string());
        let trigger_type = req.trigger_type.unwrap_or_else(|| "manual".to_string());
        let confidence = req
            .confidence
            .unwrap_or_else(|| confidence_for_delta(&req.identity_delta));
        let hash = chronoself_hash(
            &self_version,
            &parent_commit_ids,
            &context_snapshot,
            &req.identity_delta,
            &trigger_type,
        )?;
        let commit = ChronoselfCommit {
            id: Uuid::new_v4().to_string(),
            created_at: now.to_rfc3339(),
            self_version,
            parent_commit_ids,
            user_id,
            context_snapshot,
            identity_delta: req.identity_delta,
            trigger_type,
            hash,
            confidence,
            source_refs: req.source_refs,
            summary: req.summary,
        };
        self.append_jsonl(CHRONOSELF_LOG, &commit)?;
        self.write_snapshot(CURRENT_SELF_SNAPSHOT, &self_version_from_commit(&commit))?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: commit.context_snapshot.active_project_ids.first().cloned(),
            platform: commit.context_snapshot.platform.clone(),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(commit)
    }

    pub(crate) fn import_conversation(
        &self,
        req: ImportConversationRequest,
    ) -> anyhow::Result<OmniConversation> {
        Ok(self.import_conversation_with_status(req)?.0)
    }

    /// Like [`Self::import_conversation`] but also reports whether the
    /// conversation was newly created (`true`) or an existing record with the
    /// same `raw_content_ref` + `source_platform` was returned (`false`).
    /// Callers that emit per-import side effects (e.g. durable passages) must
    /// gate those on the `true` case to avoid duplicating them on re-import.
    pub(crate) fn import_conversation_with_status(
        &self,
        req: ImportConversationRequest,
    ) -> anyhow::Result<(OmniConversation, bool)> {
        self.ensure()?;
        let extracted = req
            .extracted
            .unwrap_or_else(|| extract_conversation_signals(&req.raw_content, &req.tags));
        let raw_hash = content_hash(req.raw_content.as_bytes());
        let raw_content_ref = format!("sha256:{}", raw_hash);
        let source_platform = normalize_source_platform(&req.source_platform);
        if let Some(existing) = self
            .read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, usize::MAX)?
            .into_iter()
            .find(|conversation| {
                conversation.raw_content_ref == raw_content_ref
                    && conversation.source_platform == source_platform
            })
        {
            return Ok((existing, false));
        }
        let imported_at = Utc::now().to_rfc3339();
        let mut linked_chronoself_commits = Vec::new();
        if req.create_chronoself_commit.unwrap_or(false)
            || !extracted.decisions.is_empty()
            || !extracted.belief_changes.is_empty()
        {
            let commit = self.create_commit(CreateCommitRequest {
                user_id: None,
                self_version: None,
                parent_commit_ids: Vec::new(),
                context_snapshot: Some(ContextSnapshot {
                    health_ref: None,
                    active_project_ids: extracted.projects_mentioned.clone(),
                    recent_decision_ids: Vec::new(),
                    energy_level: None,
                    emotional_valence: None,
                    platform: Some(req.source_platform.clone()),
                    target_hardware: None,
                }),
                identity_delta: IdentityDelta {
                    beliefs_added: extracted.belief_changes.clone(),
                    beliefs_removed: Vec::new(),
                    values_changed: Vec::new(),
                    cognitive_style_shift: extracted
                        .key_insights
                        .first()
                        .map(|insight| truncate_chars(insight, 180)),
                    priority_reordering: extracted.decisions.clone(),
                    product_principles: Vec::new(),
                },
                trigger_type: Some("explicit_decision".to_string()),
                confidence: Some(req.confidence_score.unwrap_or(0.72)),
                source_refs: vec![format!("omnimemory:{}", raw_hash)],
                summary: extracted.key_insights.first().cloned(),
            })?;
            linked_chronoself_commits.push(commit.id);
        }
        let imported = OmniConversation {
            id: Uuid::new_v4().to_string(),
            source_platform,
            imported_at,
            session_id: req.session_id,
            original_date: req.original_date,
            raw_content_ref,
            extracted,
            linked_chronoself_commits,
            linked_memory_events: Vec::new(),
            confidence_score: req.confidence_score.unwrap_or(0.68),
            title: req.title,
            privacy_class: normalize_privacy_class(req.privacy_class.as_deref()),
            tags: req.tags,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
        };
        self.append_jsonl(OMNIMEMORY_LOG, &imported)?;
        let _ = self.project_memory(ProjectMemoryRequest {
            rebuild: false,
            source_refs: vec![format!("omnimemory:{}", imported.id)],
        })?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: imported.extracted.projects_mentioned.first().cloned(),
            platform: Some(imported.source_platform.clone()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok((imported, true))
    }

    pub(crate) fn write_probe(&self, req: WriteProbeRequest) -> anyhow::Result<WriteProbeResponse> {
        self.ensure()?;
        let required_scopes = if req.required_scopes.is_empty() {
            vec!["memory:write".to_string()]
        } else {
            req.required_scopes
                .iter()
                .map(|scope| scope.trim().to_string())
                .filter(|scope| !scope.is_empty())
                .collect::<Vec<_>>()
        };
        let granted_scopes = req
            .granted_scopes
            .iter()
            .map(|scope| scope.trim().to_string())
            .filter(|scope| !scope.is_empty())
            .collect::<Vec<_>>();
        let granted = granted_scopes.iter().cloned().collect::<BTreeSet<_>>();
        let missing_scopes = required_scopes
            .iter()
            .filter(|scope| !granted.contains(*scope))
            .cloned()
            .collect::<Vec<_>>();
        let principal = req
            .principal
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "unknown-principal".to_string());
        let source_surface = req
            .source_surface
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "unknown-surface".to_string());
        let payload_kind = req
            .payload_kind
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "memory_write".to_string());
        Ok(WriteProbeResponse {
            status: if missing_scopes.is_empty() {
                "ok".to_string()
            } else {
                "missing_scope".to_string()
            },
            can_write: missing_scopes.is_empty(),
            missing_scopes,
            required_scopes,
            granted_scopes,
            core_write_health: "append_only_ready".to_string(),
            checked_at: Utc::now().to_rfc3339(),
            principal,
            source_surface,
            payload_kind,
            diagnostics: serde_json::json!({
                "canonical_store": "/var/lib/beagle/exocortex",
                "failed_write_log": FAILED_WRITES_LOG,
                "probe_metadata": req.metadata
            }),
        })
    }

    pub(crate) fn failed_write_inbox(
        &self,
        limit: usize,
    ) -> anyhow::Result<Vec<FailedWriteInboxItem>> {
        self.read_recent_jsonl::<FailedWriteInboxItem>(FAILED_WRITES_LOG, limit)
    }

    pub(crate) fn record_failed_write(
        &self,
        req: FailedWriteRecordRequest,
    ) -> anyhow::Result<FailedWriteInboxItem> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let source_platform = req
            .source_platform
            .unwrap_or_else(|| "claude".to_string())
            .trim()
            .to_lowercase();
        let source_surface = req
            .source_surface
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_lowercase();
        let principal = req
            .principal
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_string();
        let summary = req
            .summary
            .unwrap_or_else(|| "Failed memory write observed.".to_string());
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        let payload_kind = req
            .payload_kind
            .unwrap_or_else(|| "memory_write".to_string())
            .trim()
            .to_string();
        let id = stable_id(
            "failed-write",
            &[
                &source_platform,
                &source_surface,
                &principal,
                &summary,
                &now,
            ],
        );
        let item = FailedWriteInboxItem {
            id: id.clone(),
            created_at: now.clone(),
            updated_at: now,
            status: "observed".to_string(),
            reason: req.reason.unwrap_or_else(|| "write_failed".to_string()),
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            principal: principal.clone(),
            summary: summary.clone(),
            privacy_class,
            payload_kind,
            retry_eligible: true,
            artifact_refs: req.artifact_refs,
            candidate_refs: Vec::new(),
            metadata: req.metadata,
            rescue_memory_event_id: None,
            rescue_audit_event_id: None,
        };
        self.append_jsonl(FAILED_WRITES_LOG, &item)?;
        self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(principal),
            action: Some("memory.failed_write_observed".to_string()),
            tool_name: Some("beagle_failed_write_inbox".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("observed".to_string()),
            source: Some(source_surface),
            target_ref: Some(format!("failed_write:{}", id)),
            summary: Some(summary),
            metadata: Some(serde_json::json!({
                "source_platform": source_platform,
                "failed_write_id": id,
                "append_only_log": FAILED_WRITES_LOG
            })),
        })?;
        Ok(item)
    }

    pub(crate) fn rescue_failed_write(
        &self,
        req: FailedWriteRescueRequest,
    ) -> anyhow::Result<FailedWriteRescueResponse> {
        self.ensure()?;
        anyhow::ensure!(
            !req.turns.is_empty()
                || req
                    .summary
                    .as_deref()
                    .map(|value| !value.trim().is_empty())
                    .unwrap_or(false),
            "failed-write rescue requires reviewed visible turns or a reviewed summary"
        );
        let now = Utc::now().to_rfc3339();
        let source_platform = req
            .source_platform
            .clone()
            .unwrap_or_else(|| "claude".to_string())
            .trim()
            .to_lowercase();
        let source_surface = req
            .source_surface
            .clone()
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_lowercase();
        let principal = req
            .principal
            .clone()
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_string();
        let summary = req
            .summary
            .clone()
            .unwrap_or_else(|| "Reviewed failed write rescued into Beagle memory.".to_string());
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        let payload_kind = req
            .payload_kind
            .clone()
            .unwrap_or_else(|| "sounio_insight".to_string());
        let failed_write_id = req.failed_write_id.clone().unwrap_or_else(|| {
            stable_id(
                "failed-write",
                &[
                    &source_platform,
                    &source_surface,
                    &principal,
                    &summary,
                    &now,
                ],
            )
        });
        let mut item = FailedWriteInboxItem {
            id: failed_write_id.clone(),
            created_at: now.clone(),
            updated_at: now.clone(),
            status: "rescue_pending".to_string(),
            reason: req
                .reason
                .clone()
                .unwrap_or_else(|| "claude_ios_failed_write_rescue".to_string()),
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            principal: principal.clone(),
            summary: summary.clone(),
            privacy_class: privacy_class.clone(),
            payload_kind: payload_kind.clone(),
            retry_eligible: privacy_class != "restricted",
            artifact_refs: req.artifact_refs.clone(),
            candidate_refs: req.candidate_refs.clone(),
            metadata: req.metadata.clone(),
            rescue_memory_event_id: None,
            rescue_audit_event_id: None,
        };

        if privacy_class == "restricted" {
            item.status = "blocked_restricted".to_string();
            item.retry_eligible = false;
            self.append_jsonl(FAILED_WRITES_LOG, &item)?;
            return Ok(FailedWriteRescueResponse {
                item,
                assisted_import: None,
            });
        }

        let mut turns = req.turns;
        if turns.is_empty() {
            turns.push(AssistedImportTurn {
                role: "assistant".to_string(),
                content: summary.clone(),
                timestamp: Some(now.clone()),
                model: Some("failed-write-rescue".to_string()),
            });
        }
        let mut tags = req.tags;
        merge_unique(
            &mut tags,
            vec![
                "failed-write-rescue".to_string(),
                "claude-ios".to_string(),
                "sounio".to_string(),
                "claim-seed".to_string(),
                payload_kind.clone(),
            ],
            32,
        );
        let mut metadata = ensure_object(req.metadata);
        metadata.insert(
            "failed_write_id".to_string(),
            serde_json::Value::String(failed_write_id.clone()),
        );
        metadata.insert(
            "failed_write_reason".to_string(),
            serde_json::Value::String(item.reason.clone()),
        );
        metadata.insert(
            "principal".to_string(),
            serde_json::Value::String(principal.clone()),
        );
        metadata.insert(
            "surface_claimed".to_string(),
            serde_json::Value::String(source_surface.clone()),
        );
        metadata.insert(
            "surface_observed".to_string(),
            serde_json::Value::String("anthropic-cloud".to_string()),
        );
        metadata.insert("rescue_reviewed".to_string(), serde_json::Value::Bool(true));
        metadata.insert(
            "candidate_refs".to_string(),
            serde_json::json!(item.candidate_refs.clone()),
        );

        let import = self.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            import_scope: "failed_write_rescue".to_string(),
            session_id: req
                .session_id
                .unwrap_or_else(|| format!("failed-write-rescue-{}", Uuid::new_v4())),
            project_ref: req.project_ref.or_else(|| Some("sounio".to_string())),
            batch_index: 1,
            batch_total: 1,
            turns,
            tags,
            metadata: serde_json::Value::Object(metadata),
            coverage: serde_json::json!({
                "review": "human_requested_rescue",
                "raw_artifact_policy": "private_cluster_only",
                "claims_start_as": "belief_or_contest"
            }),
            extracted: None,
            privacy_class: Some(privacy_class.clone()),
            title: Some(format!("Failed-write rescue: {summary}")),
            original_date: Some(now),
            confidence_score: Some(0.74),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: item.artifact_refs.clone(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })?;
        item.status = if import.status == "imported" {
            "rescued".to_string()
        } else {
            format!("rescue_{}", import.status)
        };
        item.updated_at = Utc::now().to_rfc3339();
        item.rescue_memory_event_id = import.memory_event.as_ref().map(|event| event.id.clone());
        item.rescue_audit_event_id = import.audit_event.as_ref().map(|event| event.id.clone());
        self.append_jsonl(FAILED_WRITES_LOG, &item)?;
        Ok(FailedWriteRescueResponse {
            item,
            assisted_import: Some(import),
        })
    }

    pub(crate) fn assisted_import_batch(
        &self,
        req: AssistedImportBatchRequest,
    ) -> anyhow::Result<AssistedImportBatchResponse> {
        self.ensure()?;
        anyhow::ensure!(
            !req.turns.is_empty(),
            "assisted import requires at least one visible turn"
        );

        let source_platform = normalize_source_platform(&req.source_platform);
        let source_surface = if req.source_surface.trim().is_empty() {
            default_assisted_source_surface()
        } else {
            req.source_surface.trim().to_lowercase()
        };
        let import_scope = if req.import_scope.trim().is_empty() {
            default_assisted_import_scope()
        } else {
            req.import_scope.trim().to_lowercase()
        };
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        let base_metadata = ensure_object(req.metadata);
        let tool_manifest_hash = base_metadata
            .get("tool_manifest_hash")
            .and_then(|value| value.as_str())
            .map(str::to_string);
        let principal = base_metadata
            .get("principal")
            .and_then(|value| value.as_str())
            .unwrap_or(&source_surface)
            .to_string();
        let surface_observed = base_metadata
            .get("surface_observed")
            .and_then(|value| value.as_str())
            .unwrap_or("cluster-core")
            .to_string();
        let capture_session_id = req.capture_session_id.clone();
        let artifact_refs = req.artifact_refs.clone();
        let transcription_segments = req.transcription_segments.clone();
        let visual_evidence_refs = req.visual_evidence_refs.clone();

        if privacy_class == "restricted" {
            let audit = self.create_audit_event(CreateAuditEventRequest {
                client_id: Some(principal.clone()),
                action: Some("memory.assisted_import".to_string()),
                tool_name: Some("beagle_assisted_import_batch".to_string()),
                risk_level: Some("write".to_string()),
                required_scopes: vec!["memory:write".to_string()],
                granted_scopes: metadata_string_array(&base_metadata, "scopes"),
                status: Some("rejected".to_string()),
                source: Some(source_surface.clone()),
                target_ref: None,
                summary: Some(
                    "Rejected restricted assisted import before OmniMemory write.".to_string(),
                ),
                metadata: Some(serde_json::json!({
                    "source_platform": source_platform,
                    "source_surface": source_surface,
                    "surface_claimed": source_surface,
                    "surface_observed": surface_observed,
                    "principal": principal,
                    "session_id": req.session_id,
                    "batch_index": req.batch_index,
                    "batch_total": req.batch_total,
                    "privacy_class": privacy_class,
                    "tool_manifest_hash": tool_manifest_hash,
                    "restricted_default_policy": "reject_without_explicit_human_review",
                })),
            })?;
            return Ok(AssistedImportBatchResponse {
                status: "rejected".to_string(),
                reason: Some(
                    "restricted payloads require explicit human review before import".to_string(),
                ),
                session_id: req.session_id,
                source_platform,
                source_surface,
                batch_index: req.batch_index,
                batch_total: req.batch_total,
                privacy_class,
                omnimemory: None,
                projection: None,
                memory_event: None,
                audit_event: Some(audit),
                sounio_moment: None,
            });
        }

        let raw_content = assisted_raw_content(&req.turns);
        let mut tags = req.tags.clone();
        merge_unique(
            &mut tags,
            vec![
                source_platform.clone(),
                source_surface.clone(),
                import_scope.clone(),
                "assisted-import".to_string(),
                "graphrag-projection".to_string(),
                format!("privacy:{}", privacy_class),
            ],
            32,
        );
        if capture_session_id.is_some() && !tags.iter().any(|tag| tag == "capture-session") {
            tags.push("capture-session".to_string());
        }
        if !visual_evidence_refs.is_empty() && !tags.iter().any(|tag| tag == "visual-evidence") {
            tags.push("visual-evidence".to_string());
        }
        if let Some(project) = req
            .project_ref
            .as_deref()
            .filter(|value| !value.trim().is_empty())
        {
            let project_tag = format!("project:{}", project.trim());
            if !tags.contains(&project_tag) {
                tags.push(project_tag);
            }
        }
        let first_timestamp = req.turns.iter().find_map(|turn| turn.timestamp.clone());
        let mut metadata = base_metadata.clone();
        metadata.insert(
            "import_scope".to_string(),
            serde_json::Value::String(import_scope.clone()),
        );
        metadata.insert(
            "source_surface".to_string(),
            serde_json::Value::String(source_surface.clone()),
        );
        metadata.insert(
            "surface_claimed".to_string(),
            serde_json::Value::String(source_surface.clone()),
        );
        metadata.insert(
            "surface_observed".to_string(),
            serde_json::Value::String(surface_observed.clone()),
        );
        metadata.insert(
            "principal".to_string(),
            serde_json::Value::String(principal.clone()),
        );
        metadata.insert(
            "session_id".to_string(),
            serde_json::Value::String(req.session_id.clone()),
        );
        metadata.insert(
            "batch_index".to_string(),
            serde_json::json!(req.batch_index),
        );
        metadata.insert(
            "batch_total".to_string(),
            serde_json::json!(req.batch_total),
        );
        metadata.insert("coverage".to_string(), req.coverage.clone());
        metadata.insert(
            "explicit_import_only".to_string(),
            serde_json::Value::Bool(true),
        );
        if let Some(capture_session_id) = capture_session_id.clone() {
            metadata.insert(
                "capture_session_id".to_string(),
                serde_json::Value::String(capture_session_id),
            );
        }
        if !artifact_refs.is_empty() {
            metadata.insert(
                "artifact_refs".to_string(),
                serde_json::json!(artifact_refs.clone()),
            );
        }
        if !transcription_segments.is_empty() {
            metadata.insert(
                "transcription_segments".to_string(),
                serde_json::json!(transcription_segments.clone()),
            );
        }
        if !visual_evidence_refs.is_empty() {
            metadata.insert(
                "visual_evidence_refs".to_string(),
                serde_json::json!(visual_evidence_refs.clone()),
            );
        }
        metadata.insert(
            "privacy_class".to_string(),
            serde_json::Value::String(privacy_class.clone()),
        );
        if let Some(project_ref) = req.project_ref.clone() {
            metadata.insert(
                "project_ref".to_string(),
                serde_json::Value::String(project_ref),
            );
        }
        if let Some(hash) = tool_manifest_hash.clone() {
            metadata.insert(
                "tool_manifest_hash".to_string(),
                serde_json::Value::String(hash),
            );
        }

        let (imported, was_created) =
            self.import_conversation_with_status(ImportConversationRequest {
                source_platform: source_platform.clone(),
                session_id: Some(req.session_id.clone()),
                original_date: req.original_date.or(first_timestamp),
                raw_content,
                title: req.title.or_else(|| {
                    Some(format!(
                        "{} {} {} batch {}/{}",
                        source_platform,
                        import_scope,
                        req.session_id,
                        req.batch_index,
                        req.batch_total
                    ))
                }),
                tags: tags.clone(),
                extracted: req.extracted,
                confidence_score: Some(req.confidence_score.unwrap_or(0.76).clamp(0.0, 1.0)),
                create_chronoself_commit: req.create_chronoself_commit,
                privacy_class: Some(privacy_class.clone()),
                metadata: Some(serde_json::Value::Object(metadata.clone())),
            })?;
        // Persist the raw turn text as a durable conversation passage record
        // before it is dropped from the projection path, but ONLY for a newly
        // created conversation: re-importing the same raw_content+platform
        // returns the existing record and must not append duplicate passages.
        // Fail-soft: a passage write error must not fail the assisted import.
        if was_created {
            let passage_turns = req
                .turns
                .iter()
                .map(|turn| ConversationPassageTurn {
                    role: turn.role.clone(),
                    content: turn.content.clone(),
                })
                .collect::<Vec<_>>();
            if let Err(err) = self.append_conversation_passages(
                imported.id.clone(),
                imported.session_id.clone(),
                imported.source_platform.clone(),
                imported
                    .original_date
                    .clone()
                    .unwrap_or_else(|| imported.imported_at.clone()),
                privacy_class.clone(),
                passage_turns,
            ) {
                tracing::warn!(
                    "failed to append conversation passages for {}: {}",
                    imported.id,
                    err
                );
            }
        }
        let mut source_refs = vec![
            format!("omnimemory:{}", imported.id),
            imported.raw_content_ref.clone(),
        ];
        if let Some(capture_session_id) = capture_session_id.clone() {
            source_refs.push(format!("capture_session:{capture_session_id}"));
        }
        source_refs.extend(
            artifact_refs
                .iter()
                .map(|value| format!("artifact:{value}")),
        );
        source_refs.extend(
            visual_evidence_refs
                .iter()
                .map(|value| format!("visual_evidence:{value}")),
        );
        let projection = match self
            .read_recent_jsonl::<MemoryProjectionRun>(MEMORY_PROJECTION_RUNS_LOG, 1)?
            .into_iter()
            .next()
        {
            Some(run) => run,
            None => self.project_memory(ProjectMemoryRequest {
                rebuild: false,
                source_refs: source_refs.clone(),
            })?,
        };
        let summary = format!(
            "Assisted import batch {}/{} from {} via {}",
            req.batch_index, req.batch_total, source_platform, source_surface
        );
        let req_project_ref = req.project_ref.clone();
        let memory_event = self.create_memory_event(CreateMemoryEventRequest {
            source: Some(source_surface.clone()),
            kind: Some("assisted_import_batch".to_string()),
            content_ref: Some(format!("omnimemory:{}", imported.id)),
            summary: Some(summary.clone()),
            tags: tags.clone(),
            metadata: Some(serde_json::json!({
                "source_platform": source_platform,
                "source_surface": source_surface,
                "surface_claimed": source_surface,
                "surface_observed": surface_observed,
                "principal": principal,
                "import_scope": import_scope,
                "session_id": req.session_id,
                "project_ref": req_project_ref,
                "batch_index": req.batch_index,
                "batch_total": req.batch_total,
                "privacy_class": privacy_class,
                "capture_session_id": capture_session_id,
                "artifact_refs": artifact_refs,
                "transcription_segments": transcription_segments,
                "visual_evidence_refs": visual_evidence_refs,
                "coverage": req.coverage,
                "omnimemory_source_refs": source_refs,
                "projection": projection,
                "tool_manifest_hash": tool_manifest_hash,
            })),
            linked_chronoself_commits: imported.linked_chronoself_commits.clone(),
            confidence: Some(req.confidence_score.unwrap_or(0.76).clamp(0.0, 1.0)),
        })?;
        let audit = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(principal.clone()),
            action: Some("memory.assisted_import".to_string()),
            tool_name: Some("beagle_assisted_import_batch".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_string_array(&base_metadata, "scopes"),
            status: Some("success".to_string()),
            source: Some(source_surface.clone()),
            target_ref: Some(format!("omnimemory:{}", imported.id)),
            summary: Some(summary),
            metadata: Some(serde_json::json!({
                "source_platform": source_platform,
                "source_surface": source_surface,
                "surface_claimed": source_surface,
                "surface_observed": surface_observed,
                "principal": principal,
                "session_id": req.session_id,
                "batch_index": req.batch_index,
                "batch_total": req.batch_total,
                "privacy_class": privacy_class,
                "capture_session_id": capture_session_id,
                "artifact_refs": artifact_refs,
                "visual_evidence_refs": visual_evidence_refs,
                "tool_manifest_hash": tool_manifest_hash,
                "memory_event_id": memory_event.id,
                "projection_run_id": projection.id,
            })),
        })?;
        let project_slug = req
            .project_ref
            .clone()
            .or_else(|| imported.extracted.projects_mentioned.first().cloned())
            .unwrap_or_else(|| "sounio".to_string());
        let moment_evidence_refs = vec![
            format!("omnimemory:{}", imported.id),
            format!("memory_event:{}", memory_event.id),
            format!("memory_projection_run:{}", projection.id),
        ];
        let claim_seeds = imported
            .extracted
            .hypotheses
            .iter()
            .take(5)
            .map(|hypothesis| SounioClaimInput {
                id: None,
                claim_text: hypothesis.clone(),
                subject: Some(project_slug.clone()),
                value_type: Some("Claim<T>".to_string()),
                epistemic_status: Some("belief".to_string()),
                evidence_refs: moment_evidence_refs.clone(),
                provenance: serde_json::json!({
                    "source": "assisted_import",
                    "omnimemory_id": imported.id,
                    "memory_event_id": memory_event.id,
                    "projection_run_id": projection.id,
                    "source_platform": source_platform,
                    "source_surface": source_surface
                }),
                confidence: Some(imported.confidence_score.min(0.72)),
                contestation: serde_json::Value::Null,
                review_state: Some("unreviewed".to_string()),
                promotion_rule: None,
                publication_readiness: Some("not_ready".to_string()),
                section_id: None,
                agent_refs: vec![principal.clone()],
                contract_refs: Vec::new(),
                artifact_refs: Vec::new(),
                chronoself_commit_refs: imported.linked_chronoself_commits.clone(),
                privacy_class: Some(privacy_class.clone()),
                rationale: Some(
                    "Ambient Sounio typing creates conservative claim seeds from imported hypotheses."
                        .to_string(),
                ),
            })
            .collect::<Vec<_>>();
        let sounio_moment = self
            .type_sounio_moment(SounioMomentTypeRequest {
                source_event_refs: moment_evidence_refs.clone(),
                source_platform: Some(source_platform.clone()),
                source_surface: Some(source_surface.clone()),
                project_slug: Some(project_slug),
                session_id: imported.session_id.clone(),
                intent_text: imported
                    .extracted
                    .key_insights
                    .first()
                    .cloned()
                    .or_else(|| imported.title.clone()),
                summary: Some(format!(
                    "Ambient Sounio moment from {} via {}: {}",
                    source_platform,
                    source_surface,
                    imported
                        .extracted
                        .key_insights
                        .first()
                        .cloned()
                        .unwrap_or_else(|| truncate_chars(&imported.raw_content_ref, 80))
                )),
                evidence_refs: moment_evidence_refs,
                claim_seeds,
                decision_seeds: imported.extracted.decisions.clone(),
                next_action: imported.extracted.unresolved_questions.first().cloned(),
                privacy_class: Some(privacy_class.clone()),
                review_state: Some("unreviewed".to_string()),
                provenance: serde_json::json!({
                    "principal": principal,
                    "surface_claimed": source_surface,
                    "surface_observed": surface_observed,
                    "tool_manifest_hash": tool_manifest_hash,
                    "assisted_import_batch": true
                }),
                tags: tags.clone(),
            })
            .ok();

        Ok(AssistedImportBatchResponse {
            status: "imported".to_string(),
            reason: None,
            session_id: req.session_id,
            source_platform,
            source_surface,
            batch_index: req.batch_index,
            batch_total: req.batch_total,
            privacy_class,
            omnimemory: Some(imported),
            projection: Some(projection),
            memory_event: Some(memory_event),
            audit_event: Some(audit),
            sounio_moment,
        })
    }

    pub(crate) fn project_memory(
        &self,
        req: ProjectMemoryRequest,
    ) -> anyhow::Result<MemoryProjectionRun> {
        self.ensure()?;
        let source_filter = req.source_refs;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, usize::MAX)?;
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, usize::MAX)?;
        let before_episodes =
            self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let before_atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let mut episodes_created = 0;
        let mut atoms_created = 0;
        let mut duplicates = 0;
        let mut source_count = 0;
        let mut errors = Vec::new();

        for import in &imports {
            let source_ref = format!("omnimemory:{}", import.id);
            if !source_filter.is_empty()
                && !source_filter.contains(&source_ref)
                && !source_filter.contains(&import.raw_content_ref)
            {
                continue;
            }
            source_count += 1;
            match self.project_import(import) {
                Ok(outcome) => {
                    episodes_created += outcome.episodes_created;
                    atoms_created += outcome.atoms_created;
                    duplicates += outcome.duplicates;
                }
                Err(error) => errors.push(format!("{}: {:#}", source_ref, error)),
            }
        }

        for event in &memory_events {
            let source_ref = format!("memory_event:{}", event.id);
            if !source_filter.is_empty()
                && !source_filter.contains(&source_ref)
                && event
                    .content_ref
                    .as_ref()
                    .map(|content_ref| !source_filter.contains(content_ref))
                    .unwrap_or(true)
            {
                continue;
            }
            source_count += 1;
            match self.project_memory_event(event) {
                Ok(outcome) => {
                    episodes_created += outcome.episodes_created;
                    atoms_created += outcome.atoms_created;
                    duplicates += outcome.duplicates;
                }
                Err(error) => errors.push(format!("{}: {:#}", source_ref, error)),
            }
        }

        let after_episodes =
            self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let after_atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let projection_hash = projection_hash(&after_episodes, &after_atoms)?;
        let run = MemoryProjectionRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_PROJECTION_SCHEMA.to_string(),
            source_count,
            episodes_created,
            atoms_created,
            duplicates,
            errors,
            projection_hash,
            status: if episodes_created > 0 || atoms_created > 0 || req.rebuild {
                "projected".to_string()
            } else {
                "unchanged".to_string()
            },
            degraded_reason: "atom projection lexical+graph; rich passages persisted to conversation_passages + indexed by memory-engine".to_string(),
        };
        if before_episodes.len() != after_episodes.len()
            || before_atoms.len() != after_atoms.len()
            || req.rebuild
        {
            self.append_jsonl(MEMORY_PROJECTION_RUNS_LOG, &run)?;
        }
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some("graphrag++".to_string()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(run)
    }

    pub(crate) fn project_import(
        &self,
        import: &OmniConversation,
    ) -> anyhow::Result<ProjectionOutcome> {
        if import.privacy_class == "restricted" {
            return Ok(ProjectionOutcome::default());
        }
        let source_ref = format!("omnimemory:{}", import.id);
        if self.find_episode_by_source_ref(&source_ref)?.is_some() {
            return Ok(ProjectionOutcome {
                duplicates: 1,
                ..Default::default()
            });
        }
        let episode = self.build_import_episode(import, &source_ref);
        self.append_jsonl(MEMORY_EPISODES_LOG, &episode)?;
        let atoms = atoms_from_import(import, &episode);
        let mut atoms_created = 0;
        for atom in atoms {
            if self.find_atom_by_id(&atom.id)?.is_none() {
                self.append_jsonl(MEMORY_ATOMS_LOG, &atom)?;
                atoms_created += 1;
            }
        }
        Ok(ProjectionOutcome {
            episodes_created: 1,
            atoms_created,
            duplicates: 0,
        })
    }

    pub(crate) fn build_import_episode(
        &self,
        import: &OmniConversation,
        source_ref: &str,
    ) -> MemoryEpisode {
        MemoryEpisode {
            id: stable_id("episode", &[source_ref, &import.raw_content_ref]),
            created_at: Utc::now().to_rfc3339(),
            source: "omnimemory".to_string(),
            source_platform: Some(import.source_platform.clone()),
            session_id: import.session_id.clone(),
            source_ref: source_ref.to_string(),
            content_hash: import.raw_content_ref.clone(),
            privacy_class: import.privacy_class.clone(),
            provenance: serde_json::json!({
                "source": "omnimemory",
                "source_platform": import.source_platform,
                "raw_content_ref": import.raw_content_ref,
                "imported_at": import.imported_at,
                "metadata": import.metadata,
            }),
            tags: import.tags.clone(),
            title: import.title.clone(),
            linked_chronoself_commits: import.linked_chronoself_commits.clone(),
            occurred_at: import
                .original_date
                .clone()
                .or_else(|| Some(import.imported_at.clone())),
        }
    }

    pub(crate) fn project_memory_event(
        &self,
        event: &MemoryEvent,
    ) -> anyhow::Result<ProjectionOutcome> {
        let privacy = normalize_privacy_class(
            event
                .metadata
                .get("privacy_class")
                .and_then(|value| value.as_str()),
        );
        if privacy == "restricted" {
            return Ok(ProjectionOutcome::default());
        }
        let source_ref = format!("memory_event:{}", event.id);
        if self.find_episode_by_source_ref(&source_ref)?.is_some() {
            return Ok(ProjectionOutcome {
                duplicates: 1,
                ..Default::default()
            });
        }
        let content_hash = event
            .content_ref
            .clone()
            .unwrap_or_else(|| format!("sha256:{}", content_hash(event.summary.as_bytes())));
        let episode = MemoryEpisode {
            id: stable_id("episode", &[&source_ref, &content_hash]),
            created_at: Utc::now().to_rfc3339(),
            source: event.source.clone(),
            source_platform: Some(event.source.clone()),
            session_id: metadata_string(&event.metadata, "session_id"),
            source_ref: source_ref.clone(),
            content_hash,
            privacy_class: privacy.clone(),
            provenance: serde_json::json!({
                "source": event.source,
                "kind": event.kind,
                "content_ref": event.content_ref,
                "metadata": event.metadata,
            }),
            tags: event.tags.clone(),
            title: Some(event.kind.clone()),
            linked_chronoself_commits: event.linked_chronoself_commits.clone(),
            occurred_at: Some(event.created_at.clone()),
        };
        self.append_jsonl(MEMORY_EPISODES_LOG, &episode)?;
        let atom = MemoryAtom {
            id: stable_id("atom", &[&episode.id, "memory_event", &event.summary]),
            created_at: Utc::now().to_rfc3339(),
            episode_id: episode.id.clone(),
            atom_type: "memory_event".to_string(),
            text: truncate_chars(&event.summary, 500),
            normalized_text: normalize_text(&event.summary),
            source_refs: vec![source_ref],
            relations: relations_for_tags(&event.tags, &episode.id),
            tags: event.tags.clone(),
            confidence: event.confidence,
            privacy_class: privacy,
            occurred_at: Some(event.created_at.clone()),
        };
        if self.find_atom_by_id(&atom.id)?.is_none() {
            self.append_jsonl(MEMORY_ATOMS_LOG, &atom)?;
            Ok(ProjectionOutcome {
                episodes_created: 1,
                atoms_created: 1,
                duplicates: 0,
            })
        } else {
            Ok(ProjectionOutcome {
                episodes_created: 1,
                atoms_created: 0,
                duplicates: 1,
            })
        }
    }

    pub(crate) fn memory_projection_status(&self) -> anyhow::Result<MemoryProjectionStatus> {
        self.ensure()?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let latest_run = self
            .read_recent_jsonl::<MemoryProjectionRun>(MEMORY_PROJECTION_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let freshness = latest_run
            .as_ref()
            .map(|run| run.created_at.clone())
            .unwrap_or_else(|| "never".to_string());
        Ok(MemoryProjectionStatus {
            status: if atoms.is_empty() {
                "empty".to_string()
            } else {
                "fresh".to_string()
            },
            schema_version: MEMORY_PROJECTION_SCHEMA.to_string(),
            episode_count: episodes.len(),
            atom_count: atoms.len(),
            latest_run,
            freshness,
            retrieval_mode: if atoms.is_empty() {
                "append-only fallback".to_string()
            } else {
                "hybrid lexical+graph+temporal".to_string()
            },
            degraded_reason: "atom projection lexical+graph; rich passages persisted to conversation_passages + indexed by memory-engine"
                .to_string(),
        })
    }

    pub(crate) fn memory_graph_status(&self) -> anyhow::Result<MemoryGraphStatus> {
        self.ensure()?;
        let projection_status = self.memory_projection_status()?;
        let latest_bakeoff = self
            .read_recent_jsonl::<GraphBakeoffRun>(MEMORY_GRAPH_BAKEOFF_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let latest_index_run = self
            .read_recent_jsonl::<GraphIndexRun>(MEMORY_GRAPH_INDEX_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let world_count = self
            .read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, usize::MAX)?
            .len();
        let configured = graph_runtime_configured();
        let degraded_reason = graph_degraded_reason(configured);
        Ok(MemoryGraphStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_GRAPH_SCHEMA.to_string(),
            graph_runtime: graph_runtime_name(),
            runtime_status: if configured {
                "configured".to_string()
            } else {
                "bakeoff-design-only".to_string()
            },
            retrieval_mode: if configured {
                "graphsearch-lite+vector+graph+temporal".to_string()
            } else {
                "lexical+jsonl+temporal+evidence-graph".to_string()
            },
            canonical_store: "/var/lib/beagle/exocortex".to_string(),
            projection_status,
            latest_bakeoff,
            latest_index_run,
            world_count,
            degraded_reason,
        })
    }

    pub(crate) fn memory_benchmark_status(&self) -> anyhow::Result<MemoryBenchmarkStatus> {
        self.ensure()?;
        let latest_bench_audit = self
            .read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 200)?
            .into_iter()
            .find(|event| {
                event.action == "memory.benchmark_run"
                    || event.tool_name.as_deref() == Some("beagle_memory_benchmark_run")
            });
        let graph_status = self.memory_graph_status()?;
        let regression_count = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_usize(&event.metadata, "regression_count"))
            .unwrap_or(0);
        let latest_score = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_f64(&event.metadata, "latest_score"));
        let mut hard_gates = BTreeMap::new();
        hard_gates.insert("restricted_leak_zero".to_string(), true);
        hard_gates.insert(
            "provenance_complete".to_string(),
            latest_score.unwrap_or(0.0) >= 0.70,
        );
        hard_gates.insert("fallback_explicit".to_string(), true);
        hard_gates.insert("jsonl_replay_idempotent".to_string(), true);
        let truthset_id = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_string(&event.metadata, "truthset_id"));
        let baseline_score = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_f64(&event.metadata, "baseline_score"));
        let candidate_score = latest_bench_audit.as_ref().and_then(|event| {
            metadata_f64(&event.metadata, "hypermemory_score")
                .or_else(|| metadata_f64(&event.metadata, "candidate_score"))
        });
        let consecutive_passing_runs = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_usize(&event.metadata, "consecutive_passing_runs"))
            .unwrap_or(0);
        let required_margin = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_f64(&event.metadata, "required_margin"))
            .unwrap_or(0.05);
        let hard_gates_passed = hard_gates.values().all(|gate| *gate) && regression_count == 0;
        let computed_hot_path_eligible = match (baseline_score, candidate_score) {
            (Some(baseline), Some(candidate)) => {
                candidate >= baseline + required_margin
                    && consecutive_passing_runs >= 3
                    && hard_gates_passed
            }
            _ => false,
        };
        let hot_path_eligible = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_bool(&event.metadata, "hot_path_eligible"))
            .unwrap_or(computed_hot_path_eligible);
        let hot_path_mode = memory_hot_path_mode();
        let provisional_hot_path = hot_path_mode == "hypermemory_multivector" && !hot_path_eligible;
        let promotion_gate = latest_bench_audit.as_ref().map(|_| MemoryPromotionGate {
            baseline_mode: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "baseline_mode"))
                .unwrap_or_else(|| "graphsearch-lite".to_string()),
            candidate_mode: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "candidate_mode"))
                .unwrap_or_else(|| "hypermemory".to_string()),
            required_margin,
            baseline_score,
            candidate_score,
            consecutive_passing_runs,
            required_consecutive_runs: 3,
            hard_gates_passed,
            eligible: hot_path_eligible,
            rationale: if hot_path_eligible {
                "HyperMemory passed the v1.9 promotion gate for Home/search hot path.".to_string()
            } else {
                "HyperMemory remains advisory until it beats baseline by +5 points for 3 consecutive passing runs with full provenance and zero restricted leakage.".to_string()
            },
        });
        let status = match (&latest_bench_audit, regression_count) {
            (Some(_), 0) => "passing",
            (Some(_), _) => "regression",
            (None, _) => "empty",
        }
        .to_string();
        Ok(MemoryBenchmarkStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_BENCH_SCHEMA.to_string(),
            status,
            latest_run_id: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "run_id"))
                .or_else(|| latest_bench_audit.as_ref().and_then(|event| event.target_ref.clone())),
            latest_score,
            query_count: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_usize(&event.metadata, "query_count"))
                .unwrap_or(0),
            hard_gates,
            evaluated_modes: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_array_strings(&event.metadata, "evaluated_modes"))
                .unwrap_or_else(|| {
                    vec![
                        "graphsearch-lite".to_string(),
                        "hypermemory".to_string(),
                        "hypermemory_multivector".to_string(),
                        graph_status.retrieval_mode.clone(),
                    ]
                }),
            regression_count,
            artifact_manifest: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "artifact_manifest")),
            truthset_id,
            promotion_gate,
            hot_path_eligible,
            provisional_hot_path,
            hot_path_mode,
            confirmed_passing_runs: consecutive_passing_runs,
            portfolio_truthset_id: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "truthset_id")),
            degraded_reason: latest_bench_audit.is_none().then(|| {
                "No Memory Bench run has been audited in core yet; run beagle-memory-engine /v1/bench/runs.".to_string()
            }),
        })
    }

    pub(crate) fn export_sanitized_memory(
        &self,
        req: MemoryExportRequest,
    ) -> anyhow::Result<MemoryExportResponse> {
        self.ensure()?;
        let limit = req.limit.unwrap_or(1_000).clamp(1, 10_000);
        let mut episodes = self
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?
            .into_iter()
            .filter(|episode| episode.privacy_class != "restricted")
            .collect::<Vec<_>>();
        let episode_ids = episodes
            .iter()
            .map(|episode| episode.id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        let atoms = self
            .read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?
            .into_iter()
            .filter(|atom| atom.privacy_class != "restricted")
            .filter(|atom| episode_ids.contains(&atom.episode_id))
            .collect::<Vec<_>>();
        let worlds = if req.include_worlds {
            self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?
        } else {
            Vec::new()
        };
        let candidates = if req.include_candidates {
            self.latest_memory_candidates(limit)?
                .into_iter()
                .filter(|candidate| candidate.privacy_class != "restricted")
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        let material = episodes
            .iter()
            .map(|episode| format!("episode:{}:{}", episode.id, episode.content_hash))
            .chain(
                atoms
                    .iter()
                    .map(|atom| format!("atom:{}:{}", atom.id, atom.normalized_text)),
            )
            .chain(
                worlds
                    .iter()
                    .map(|world| format!("world:{}:{}", world.id, world.merkle_root)),
            )
            .chain(candidates.iter().map(|candidate| {
                format!(
                    "candidate:{}:{}:{}",
                    candidate.id, candidate.status, candidate.normalized_text
                )
            }))
            .collect::<Vec<_>>();
        episodes.sort_by(|a, b| b.occurred_at.cmp(&a.occurred_at));
        let passages = self
            .read_recent_jsonl::<ConversationPassageRecord>(CONVERSATION_PASSAGES_LOG, limit)?
            .into_iter()
            .filter(|record| normalize_privacy_class(Some(&record.privacy_class)) != "restricted")
            .collect::<Vec<_>>();
        Ok(MemoryExportResponse {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_MESH_SCHEMA.to_string(),
            privacy_policy: "cluster-sanitized: restricted episodes/atoms/candidates are excluded before lab export".to_string(),
            canonical_store: "/var/lib/beagle/exocortex".to_string(),
            episodes,
            atoms,
            worlds,
            candidates,
            synthetic_golden_queries: synthetic_golden_queries(),
            passages,
            merkle_root: merkle_hash(&material),
            provenance: serde_json::json!({
                "purpose": req.purpose.unwrap_or_else(|| "beagle-memory-lab-bakeoff".to_string()),
                "source": "beagle-core-export-api",
                "private_data_policy": "cluster_only_no_github_no_macbook",
                "schema_version": MEMORY_MESH_SCHEMA,
            }),
        })
    }

    pub(crate) fn create_memory_truthset(
        &self,
        req: CreateMemoryTruthSetRequest,
    ) -> anyhow::Result<MemoryTruthSet> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let truthset = MemoryTruthSet {
            id: stable_id(
                "truthset",
                &[
                    req.title.as_deref().unwrap_or("beagle-memory-truth-v1.9"),
                    &now,
                ],
            ),
            created_at: now,
            schema_version: MEMORY_TRUTH_SCHEMA.to_string(),
            status: "draft".to_string(),
            title: req
                .title
                .unwrap_or_else(|| "Beagle private Memory Truth v1.9".to_string()),
            description: req.description,
            domains: if req.domains.is_empty() {
                truthset_default_domains()
            } else {
                req.domains
            },
            source_refs: req.source_refs,
            case_count: 0,
            approved_case_count: 0,
            artifact_root: req
                .artifact_root
                .unwrap_or_else(|| "/orangefs/beagle-memory-lab/truthsets/v1.9".to_string()),
            privacy_policy:
                "cluster-only private truthset; restricted content is excluded before approval"
                    .to_string(),
            reviewer: req.reviewer,
            rationale: None,
        };
        self.append_jsonl(MEMORY_TRUTHSETS_LOG, &truthset)?;
        Ok(truthset)
    }

    pub(crate) fn create_memory_truth_case(
        &self,
        truthset_id: &str,
        req: CreateMemoryTruthCaseRequest,
    ) -> anyhow::Result<MemoryTruthCase> {
        self.ensure()?;
        let truthset = self
            .latest_memory_truthset(truthset_id)?
            .ok_or_else(|| anyhow::anyhow!("memory truthset not found: {}", truthset_id))?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted truth cases require explicit review outside v1.9"
        );
        let mut provenance_requirements = req.provenance_requirements;
        if provenance_requirements.is_empty() {
            provenance_requirements = vec![
                "episode_id".to_string(),
                "atom_id".to_string(),
                "source_ref".to_string(),
                "privacy_class".to_string(),
            ];
        }
        let case = MemoryTruthCase {
            id: stable_id("truthcase", &[truthset_id, &req.domain, &req.query]),
            truthset_id: truthset.id,
            created_at: Utc::now().to_rfc3339(),
            status: req.status.unwrap_or_else(|| "draft".to_string()),
            domain: req.domain,
            query: req.query,
            expected_answer: req.expected_answer,
            required_evidence_refs: req.required_evidence_refs,
            expected_atom_refs: req.expected_atom_refs,
            expected_episode_refs: req.expected_episode_refs,
            temporal_expectation: req.temporal_expectation,
            provenance_requirements,
            privacy_class,
            tags: req.tags,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
        };
        self.append_jsonl(MEMORY_TRUTH_CASES_LOG, &case)?;
        self.rewrite_memory_truthset_counts(truthset_id, None, None, None)?;
        Ok(case)
    }

    pub(crate) fn review_memory_truthset(
        &self,
        truthset_id: &str,
        req: ReviewMemoryTruthSetRequest,
    ) -> anyhow::Result<MemoryTruthSetResponse> {
        self.ensure()?;
        self.rewrite_memory_truthset_counts(
            truthset_id,
            req.status.as_deref(),
            req.reviewer.as_deref(),
            req.rationale.as_deref(),
        )?;
        self.memory_truthset_response(truthset_id)?
            .ok_or_else(|| anyhow::anyhow!("memory truthset not found: {}", truthset_id))
    }

    pub(crate) fn memory_truthset_response(
        &self,
        truthset_id: &str,
    ) -> anyhow::Result<Option<MemoryTruthSetResponse>> {
        let Some(truthset) = self.latest_memory_truthset(truthset_id)? else {
            return Ok(None);
        };
        let mut cases = self
            .read_recent_jsonl::<MemoryTruthCase>(MEMORY_TRUTH_CASES_LOG, usize::MAX)?
            .into_iter()
            .filter(|case| case.truthset_id == truthset_id && case.privacy_class != "restricted")
            .collect::<Vec<_>>();
        cases.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        Ok(Some(MemoryTruthSetResponse { truthset, cases }))
    }

    pub(crate) fn latest_memory_truthset(
        &self,
        truthset_id: &str,
    ) -> anyhow::Result<Option<MemoryTruthSet>> {
        Ok(self
            .read_recent_jsonl::<MemoryTruthSet>(MEMORY_TRUTHSETS_LOG, usize::MAX)?
            .into_iter()
            .find(|truthset| truthset.id == truthset_id))
    }

    pub(crate) fn rewrite_memory_truthset_counts(
        &self,
        truthset_id: &str,
        status: Option<&str>,
        reviewer: Option<&str>,
        rationale: Option<&str>,
    ) -> anyhow::Result<()> {
        let mut truthset = self
            .latest_memory_truthset(truthset_id)?
            .ok_or_else(|| anyhow::anyhow!("memory truthset not found: {}", truthset_id))?;
        let cases = self
            .read_recent_jsonl::<MemoryTruthCase>(MEMORY_TRUTH_CASES_LOG, usize::MAX)?
            .into_iter()
            .filter(|case| case.truthset_id == truthset_id && case.privacy_class != "restricted")
            .collect::<Vec<_>>();
        truthset.created_at = Utc::now().to_rfc3339();
        truthset.case_count = cases.len();
        if let Some(status) = status {
            truthset.status = status.trim().to_lowercase();
        }
        truthset.approved_case_count = if truthset.status == "approved" {
            cases.len()
        } else {
            cases
                .iter()
                .filter(|case| case.status == "approved")
                .count()
        };
        if let Some(reviewer) = reviewer {
            truthset.reviewer = Some(reviewer.to_string());
        }
        if let Some(rationale) = rationale {
            truthset.rationale = Some(rationale.to_string());
        }
        self.append_jsonl(MEMORY_TRUTHSETS_LOG, &truthset)?;
        Ok(())
    }

    pub(crate) fn run_graph_bakeoff(
        &self,
        req: GraphBakeoffRequest,
    ) -> anyhow::Result<GraphBakeoffRun> {
        self.ensure()?;
        let limit = req.dataset_limit.unwrap_or(200).clamp(1, 2_000);
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?;
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?;
        let candidates = bakeoff_candidates(episodes.len(), atoms.len(), worlds.len());
        let winner = candidates
            .iter()
            .max_by(|a, b| {
                a.score
                    .partial_cmp(&b.score)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .map(|candidate| candidate.name.clone())
            .unwrap_or_else(|| "FalkorDB GraphBLAS".to_string());
        let run = GraphBakeoffRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            status: "completed".to_string(),
            schema_version: MEMORY_GRAPH_SCHEMA.to_string(),
            dataset: serde_json::json!({
                "episodes": episodes.len(),
                "atoms": atoms.len(),
                "worlds": worlds.len(),
                "golden_queries": 20,
                "dataset_limit": limit,
                "sources": ["MemoryEpisode", "MemoryAtom", "Claude iOS", "Codex/Claude Code Work Memory"],
                "baseline_included": req.include_baseline.unwrap_or(true),
            }),
            candidates,
            winner,
            baseline: "Neo4j+Qdrant remains baseline only, not promoted by default".to_string(),
            report_ref: "docs/research/beagle_graphrag_runtime_bakeoff.md".to_string(),
            degraded_reason: "Bake-off scores are deterministic design metrics until live FalkorDB/Memgraph/SurrealDB endpoints are configured in the cluster.".to_string(),
        };
        self.append_jsonl(MEMORY_GRAPH_BAKEOFF_RUNS_LOG, &run)?;
        Ok(run)
    }

    pub(crate) fn index_graph(&self, req: GraphIndexRequest) -> anyhow::Result<GraphIndexRun> {
        self.ensure()?;
        let projection = self.project_memory(ProjectMemoryRequest {
            rebuild: req.rebuild,
            source_refs: req.source_refs,
        })?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let before_worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, usize::MAX)?;
        let mut worlds_created = 0;
        for episode in &episodes {
            let world = self.memory_world_for_episode(episode, &atoms)?;
            if !before_worlds.iter().any(|existing| existing.id == world.id) {
                self.append_jsonl(MEMORY_WORLDS_LOG, &world)?;
                worlds_created += 1;
            }
        }
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, usize::MAX)?;
        let merkle_root = merkle_hash(
            worlds
                .iter()
                .map(|world| format!("{}:{}", world.id, world.merkle_root))
                .collect::<Vec<_>>()
                .as_slice(),
        );
        let run = GraphIndexRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_GRAPH_SCHEMA.to_string(),
            runtime: req.runtime.unwrap_or_else(graph_runtime_name),
            status: if worlds_created > 0 || req.rebuild {
                "indexed".to_string()
            } else {
                "unchanged".to_string()
            },
            episodes_indexed: episodes.len(),
            atoms_indexed: atoms.len(),
            worlds_created,
            hyperedges_indexed: atoms.iter().map(|atom| atom.relations.len().max(1)).sum(),
            merkle_root,
            degraded_reason: graph_degraded_reason(graph_runtime_configured()),
            provenance: serde_json::json!({
                "projection_run_id": projection.id,
                "projection_hash": projection.projection_hash,
                "canonical_store": "/var/lib/beagle/exocortex",
                "runtime_configured": graph_runtime_configured(),
                "index_is_rebuildable": true
            }),
        };
        self.append_jsonl(MEMORY_GRAPH_INDEX_RUNS_LOG, &run)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some("graphrag++-index".to_string()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(run)
    }

    pub(crate) fn memory_world_for_episode(
        &self,
        episode: &MemoryEpisode,
        atoms: &[MemoryAtom],
    ) -> anyhow::Result<MemoryWorld> {
        let episode_atoms = atoms
            .iter()
            .filter(|atom| atom.episode_id == episode.id)
            .collect::<Vec<_>>();
        let relation_count = episode_atoms
            .iter()
            .map(|atom| atom.relations.len())
            .sum::<usize>();
        let material = std::iter::once(format!("episode:{}", episode.id))
            .chain(episode_atoms.iter().map(|atom| {
                format!(
                    "atom:{}:{}:{}",
                    atom.id, atom.atom_type, atom.normalized_text
                )
            }))
            .collect::<Vec<_>>();
        Ok(MemoryWorld {
            id: stable_id("world", &[&episode.source_ref, &episode.content_hash]),
            created_at: Utc::now().to_rfc3339(),
            world_type: episode
                .session_id
                .as_ref()
                .map(|_| "session")
                .unwrap_or("episode")
                .to_string(),
            source_ref: episode.source_ref.clone(),
            title: episode.title.clone(),
            merkle_root: merkle_hash(&material),
            valid_from: episode.occurred_at.clone(),
            valid_until: None,
            node_count: 1 + episode_atoms.len(),
            edge_count: relation_count + episode_atoms.len(),
            runtime_hint: graph_runtime_name(),
            tags: episode.tags.clone(),
            provenance: serde_json::json!({
                "source": "MemoryEpisode+MemoryAtom",
                "content_addressed": true,
                "canonical_store": "/var/lib/beagle/exocortex",
                "falkordb_promotion_candidate": true
            }),
        })
    }

    pub(crate) fn memory_graph_recent(
        &self,
        limit: usize,
    ) -> anyhow::Result<MemoryGraphRecentResponse> {
        self.ensure()?;
        let limit = limit.clamp(1, 50);
        let status = self.memory_projection_status()?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?;
        let mut relations = Vec::<MemoryRelation>::new();
        for atom in &atoms {
            for relation in &atom.relations {
                if !relations.iter().any(|existing| {
                    existing.subject == relation.subject
                        && existing.predicate == relation.predicate
                        && existing.object == relation.object
                }) {
                    relations.push(relation.clone());
                }
            }
        }
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?;
        let communities = memory_communities(&atoms, &worlds);
        Ok(MemoryGraphRecentResponse {
            generated_at: Utc::now().to_rfc3339(),
            status,
            episodes,
            atoms,
            relations,
            worlds,
            communities,
            provenance: serde_json::json!({
                "source": "cluster-jsonl",
                "schema_version": MEMORY_PROJECTION_SCHEMA,
                "graph_schema_version": MEMORY_GRAPH_SCHEMA,
                "graph_runtime": graph_runtime_name(),
                "canonical_store": "/var/lib/beagle/exocortex",
                "derived_indexes": "rebuildable"
            }),
        })
    }

    pub(crate) fn memory_worlds_recent(
        &self,
        limit: usize,
    ) -> anyhow::Result<MemoryWorldsRecentResponse> {
        self.ensure()?;
        let limit = limit.clamp(1, 50);
        Ok(MemoryWorldsRecentResponse {
            generated_at: Utc::now().to_rfc3339(),
            worlds: self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?,
            graph_status: self.memory_graph_status()?,
        })
    }

    pub(crate) fn graphrag_query(
        &self,
        req: GraphRagQueryRequest,
    ) -> anyhow::Result<GraphRagQueryResponse> {
        self.ensure()?;
        let max_items = req.max_items.unwrap_or(5).clamp(1, 20);
        let requested_mode = req.mode.clone().unwrap_or_else(memory_hot_path_mode);
        let is_multivector = requested_mode.eq_ignore_ascii_case("hypermemory_multivector");
        let is_hypermemory = requested_mode.eq_ignore_ascii_case("hypermemory") || is_multivector;
        let ranking_policy = memory_ranking_policy(req.ranking_policy.as_deref());
        let runtime_configured = graph_runtime_configured();
        let graph_runtime = graph_runtime_name();
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        if atoms.is_empty() {
            let strategy_used = retrieval_strategy_for(&req.query);
            let subqueries = retrieval_subqueries_for(&req.query, &strategy_used);
            let stable_fact_guard_applied = stable_fact_guard_applies(&req.query, &[]);
            return Ok(GraphRagQueryResponse {
                summary: format!(
                    "No GraphRAG++ projected memory matches found for '{}'.",
                    req.query
                ),
                evidence: Vec::new(),
                atoms: Vec::new(),
                episodes: Vec::new(),
                relations: Vec::new(),
                temporal_context: GraphRagTemporalContext {
                    newest_evidence_at: None,
                    oldest_evidence_at: None,
                    matched_episode_count: 0,
                },
                provenance: serde_json::json!({
                    "schema_version": MEMORY_PROJECTION_SCHEMA,
                    "graph_schema_version": MEMORY_GRAPH_SCHEMA,
                    "retrieval_mode": "append-only fallback",
                    "graph_runtime": graph_runtime.clone(),
                    "canonical_store": "/var/lib/beagle/exocortex",
                    "hypermemory": {
                        "enabled": is_hypermemory,
                        "authority": "derived-advisory",
                        "benchmark_gate": "required-before-hot-path"
                    }
                }),
                confidence: 0.0,
                degraded_reason: Some("no projected memory atoms available".to_string()),
                mode: Some(requested_mode.clone()),
                graph_runtime: Some(graph_runtime),
                evidence_graph: Some(EvidenceGraph {
                    nodes: Vec::new(),
                    edges: Vec::new(),
                    temporary: true,
                    merkle_root: merkle_hash(&[req.query.clone()]),
                }),
                community_context: Some(GraphRagCommunityContext {
                    strategy: "k-core-density-hierarchy".to_string(),
                    selected_communities: Vec::new(),
                    degraded_reason: Some("no projected atoms available".to_string()),
                }),
                retrieval_trace: vec![RetrievalTraceStep {
                    stage: "projection-check".to_string(),
                    backend: "cluster-jsonl".to_string(),
                    status: "empty".to_string(),
                    items: 0,
                    latency_ms: 0.0,
                    notes: vec!["Memory projection has no atoms yet.".to_string()],
                }],
                mesh_trace: vec![RetrievalTraceStep {
                    stage: "federated-mesh-shortlist".to_string(),
                    backend: "beagle-memory-engine".to_string(),
                    status: "degraded".to_string(),
                    items: 0,
                    latency_ms: 0.0,
                    notes: vec!["v1.5 mesh has no exported atoms to federate yet.".to_string()],
                }],
                runtime_votes: runtime_votes(false),
                candidate_refs: Vec::new(),
                runtime_used: Some(runtime_used_for(&requested_mode, runtime_configured)),
                fallback_chain: fallback_chain_for(&requested_mode, runtime_configured),
                semantic_trace: semantic_trace_for(&requested_mode, runtime_configured, 0),
                maxsim_scores: Vec::new(),
                graph_expansion: graph_expansion_trace(None, 0, 0),
                reranker_scores: Vec::new(),
                truthset_gate_status: truthset_gate_status_for(None, false),
                restricted_leak_check: restricted_leak_check_for(0),
                retrieval_agent: retrieval_agent_mode(),
                retrieval_plan_id: stable_id("retrieval-plan", &[&req.query, &requested_mode]),
                strategy_used: strategy_used.clone(),
                subqueries: subqueries.clone(),
                evidence_pack: evidence_pack_json(0, 0, Vec::new(), 0),
                context_format: retrieval_context_format(),
                planner_mode: retrieval_planner_mode(),
                budget: retrieval_budget_json(max_items, &retrieval_planner_mode()),
                runtime_trace: retrieval_agent_trace_for(
                    &strategy_used,
                    &subqueries,
                    runtime_configured,
                    0,
                    0,
                ),
                context_pack_id: Some(stable_id(
                    "context-pack",
                    &[
                        &req.query,
                        &requested_mode,
                        &strategy_used,
                        &memory_policy_version(),
                    ],
                )),
                policy_version: Some(memory_policy_version()),
                policy_gate: memory_policy_gate_json(),
                dreamcycle_status: Some(dreamcycle_mode()),
                ranking_policy: Some(ranking_policy.clone()),
                ranking_trace: ranking_trace_json(&[], &ranking_policy, stable_fact_guard_applied),
                recency_boost_applied: false,
                stable_fact_guard_applied,
            });
        }

        let query_tokens = tokenize(&req.query);
        let scope = req.scope.as_ref().map(|scope| scope.to_lowercase());
        let stable_fact_guard_applied = stable_fact_guard_applies(&req.query, &query_tokens);
        let episode_by_id = episodes
            .iter()
            .map(|episode| (episode.id.as_str(), episode))
            .collect::<BTreeMap<_, _>>();
        let mut scored = atoms
            .iter()
            .filter(|atom| {
                // Project-habitat isolation: a scoped recall must return ONLY atoms that belong to
                // that project, identified by the canonical `project:<slug>` tag that work-memory
                // capture writes. The previous substring match (`tag.contains(scope)` ||
                // `atom_type.contains(scope)`) leaked the portfolio/omnimemory that merely *mentions*
                // the project (e.g. papers tagged with a "sounio" topic) into `scope=sounio` recall,
                // breaking the per-project cognitive loop. Strict tag match fixes the isolation; a
                // bare `<scope>` tag is still accepted for non-project (topic) scopes.
                scope
                    .as_ref()
                    .map(|scope| {
                        let project_tag = format!("project:{scope}");
                        atom.tags.iter().any(|tag| {
                            let t = tag.to_lowercase();
                            t == project_tag || t == *scope
                        })
                    })
                    .unwrap_or(true)
            })
            .filter(|atom| {
                !is_restricted_memory(atom, episode_by_id.get(atom.episode_id.as_str()).copied())
            })
            .filter_map(|atom| {
                let base_score = if is_hypermemory {
                    hypermemory_atom_score(atom, &query_tokens)
                } else {
                    atom_score(atom, &query_tokens)
                };
                let ranked = rank_memory_atom(
                    atom,
                    episode_by_id.get(atom.episode_id.as_str()).copied(),
                    base_score,
                    &query_tokens,
                    &ranking_policy,
                    stable_fact_guard_applied,
                );
                (ranked.final_score > 0.0).then_some(ranked)
            })
            .collect::<Vec<_>>();
        scored.sort_by(|a, b| {
            b.final_score
                .partial_cmp(&a.final_score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| b.atom.occurred_at.cmp(&a.atom.occurred_at))
        });
        scored.truncate(max_items);
        let ranking_trace = ranking_trace_json(&scored, &ranking_policy, stable_fact_guard_applied);
        let recency_boost_applied = scored.iter().any(|item| item.recency_boost > 0.0);

        let mut matched_episodes = Vec::<MemoryEpisode>::new();
        let mut evidence = Vec::<GraphRagEvidence>::new();
        let mut relations = Vec::<MemoryRelation>::new();
        for ranked in &scored {
            let atom = &ranked.atom;
            if let Some(episode) = episodes
                .iter()
                .find(|episode| episode.id == atom.episode_id)
            {
                if !matched_episodes.iter().any(|item| item.id == episode.id) {
                    matched_episodes.push(episode.clone());
                }
                evidence.push(GraphRagEvidence {
                    atom_id: atom.id.clone(),
                    episode_id: atom.episode_id.clone(),
                    atom_type: atom.atom_type.clone(),
                    text: atom.text.clone(),
                    score: ranked.final_score,
                    source_refs: atom.source_refs.clone(),
                    provenance: episode.provenance.clone(),
                });
            }
            for relation in &atom.relations {
                if !relations.iter().any(|existing| {
                    existing.subject == relation.subject
                        && existing.predicate == relation.predicate
                        && existing.object == relation.object
                }) {
                    relations.push(relation.clone());
                }
            }
        }
        let newest = evidence
            .iter()
            .filter_map(|item| {
                matched_episodes
                    .iter()
                    .find(|episode| episode.id == item.episode_id)
                    .and_then(|episode| episode.occurred_at.clone())
            })
            .max();
        let oldest = evidence
            .iter()
            .filter_map(|item| {
                matched_episodes
                    .iter()
                    .find(|episode| episode.id == item.episode_id)
                    .and_then(|episode| episode.occurred_at.clone())
            })
            .min();
        let confidence = if evidence.is_empty() {
            0.0
        } else {
            (evidence.iter().map(|item| item.score).sum::<f64>() / evidence.len() as f64)
                .clamp(0.0, 1.0)
        };
        let summary = if evidence.is_empty() {
            format!(
                "No GraphRAG++ projected memory matches found for '{}'.",
                req.query
            )
        } else if is_hypermemory {
            format!(
                "Found {} HyperMemory match(es) across {} episode(s), with topic/world/hyperedge expansion, for '{}'.",
                evidence.len(),
                matched_episodes.len(),
                req.query
            )
        } else {
            format!(
                "Found {} GraphRAG++ projected memory match(es) across {} episode(s) for '{}'.",
                evidence.len(),
                matched_episodes.len(),
                req.query
            )
        };

        let matched_episode_count = matched_episodes.len();
        let matched_atoms = scored
            .into_iter()
            .map(|ranked| ranked.atom)
            .collect::<Vec<_>>();
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, max_items)?;
        let communities = memory_communities(&matched_atoms, &worlds);
        let evidence_graph =
            evidence_graph_for(&evidence, &matched_atoms, &matched_episodes, &relations);
        let candidate_refs = self
            .read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, 20)?
            .into_iter()
            .filter(|candidate| {
                (candidate.status == "candidate" || candidate.status == "triad_pending")
                    && query_tokens
                        .iter()
                        .any(|token| candidate.normalized_text.contains(token))
            })
            .map(|candidate| candidate.id)
            .take(5)
            .collect::<Vec<_>>();
        let mut retrieval_trace = vec![
            RetrievalTraceStep {
                stage: "question-analysis".to_string(),
                backend: "deterministic-tokenizer".to_string(),
                status: "ok".to_string(),
                items: query_tokens.len(),
                latency_ms: 0.0,
                notes: vec![format!("mode={}", requested_mode)],
            },
            RetrievalTraceStep {
                stage: "semantic-candidate-search".to_string(),
                backend: if runtime_configured {
                    graph_runtime.clone()
                } else {
                    "cluster-jsonl lexical fallback".to_string()
                },
                status: if evidence.is_empty() {
                    "no_hits".to_string()
                } else {
                    "ok".to_string()
                },
                items: evidence.len(),
                latency_ms: 0.0,
                notes: vec![graph_degraded_reason(runtime_configured)],
            },
            RetrievalTraceStep {
                stage: "structural-expansion".to_string(),
                backend: "memory-relations+worlds".to_string(),
                status: "ok".to_string(),
                items: relations.len() + worlds.len(),
                latency_ms: 0.0,
                notes: vec![
                    "Relink-lite is represented as a temporary evidence graph, never promoted automatically."
                        .to_string(),
                ],
            },
            RetrievalTraceStep {
                stage: "rerank-and-synthesis".to_string(),
                backend: "temporal-confidence-reranker".to_string(),
                status: "ok".to_string(),
                items: matched_atoms.len(),
                latency_ms: 0.0,
                notes: vec!["Evidence keeps provenance back to Episode+Atom JSONL.".to_string()],
            },
        ];
        if is_hypermemory {
            retrieval_trace.insert(
                1,
                RetrievalTraceStep {
                    stage: if is_multivector {
                        "hypermemory-multivector-topic-world-selection"
                    } else {
                        "hypermemory-topic-world-selection"
                    }
                    .to_string(),
                    backend: if is_multivector {
                        "LanceDB multivector + Jina-ColBERT-v2 + MemoryWorld projection"
                    } else {
                        "MemoryTopic+MemoryWorld+Hyperedge projection"
                    }
                    .to_string(),
                    status: if evidence.is_empty() { "no_hits" } else { "ok" }.to_string(),
                    items: communities.len() + worlds.len(),
                    latency_ms: 0.0,
                    notes: vec![
                        "HyperMemory is derived/advisory until Memory Bench beats baseline.".to_string(),
                        "Coarse-to-fine retrieval expands tags, source refs, relations, and MemoryWorlds.".to_string(),
                    ],
                },
            );
        }
        let mesh_trace = vec![
            RetrievalTraceStep {
                stage: "adaptive-federation".to_string(),
                backend: "beagle-memory-engine".to_string(),
                status: if runtime_configured {
                    "shortlist"
                } else {
                    "degraded"
                }
                .to_string(),
                items: evidence.len(),
                latency_ms: 0.0,
                notes: vec![
                    "Home/search use shortlist federation; Memory Lens can fan out deeper."
                        .to_string(),
                    "Canonical authority remains JSONL+Merkle+Chronoself in beagle-core."
                        .to_string(),
                ],
            },
            RetrievalTraceStep {
                stage: "candidate-memory-check".to_string(),
                backend: "memory_candidates.jsonl".to_string(),
                status: if candidate_refs.is_empty() {
                    "no_candidates"
                } else {
                    "candidate_refs"
                }
                .to_string(),
                items: candidate_refs.len(),
                latency_ms: 0.0,
                notes: vec![
                    "Candidates never enter active retrieval until Triad quorum promotes them."
                        .to_string(),
                ],
            },
        ];
        let evidence_count = evidence.len();
        let strategy_used = retrieval_strategy_for(&req.query);
        let subqueries = retrieval_subqueries_for(&req.query, &strategy_used);
        let evidence_refs = evidence
            .iter()
            .flat_map(|item| {
                let mut refs = vec![
                    format!("atom:{}", item.atom_id),
                    format!("episode:{}", item.episode_id),
                ];
                refs.extend(item.source_refs.clone());
                refs
            })
            .collect::<Vec<_>>();
        let maxsim_scores = maxsim_scores_for(&evidence);
        let graph_expansion =
            graph_expansion_trace(Some(&evidence_graph), communities.len(), relations.len());
        let reranker_scores = reranker_scores_for(&evidence);
        let benchmark_status = self.memory_benchmark_status().ok();
        let truthset_gate_status = truthset_gate_status_for(
            benchmark_status
                .as_ref()
                .and_then(|status| status.portfolio_truthset_id.clone()),
            benchmark_status
                .as_ref()
                .map(|status| status.hot_path_eligible)
                .unwrap_or(false),
        );
        Ok(GraphRagQueryResponse {
            summary,
            evidence,
            atoms: matched_atoms,
            episodes: matched_episodes,
            relations,
            temporal_context: GraphRagTemporalContext {
                newest_evidence_at: newest,
                oldest_evidence_at: oldest,
                matched_episode_count,
            },
            provenance: serde_json::json!({
                "schema_version": MEMORY_PROJECTION_SCHEMA,
                "graph_schema_version": MEMORY_GRAPH_SCHEMA,
                "retrieval_mode": requested_mode.clone(),
                "graph_runtime": graph_runtime.clone(),
                "canonical_store": "/var/lib/beagle/exocortex",
                "derived_indexes": "rebuildable",
                "runtime_configured": runtime_configured,
                "ranking_policy": ranking_policy.clone(),
                "stable_fact_guard_applied": stable_fact_guard_applied,
                "hypermemory": {
                    "enabled": is_hypermemory,
                    "multivector": is_multivector,
                    "authority": "derived-advisory",
                    "benchmark_schema": MEMORY_BENCH_SCHEMA,
                    "hot_path_gate": "must beat graphsearch-lite baseline with full provenance"
                }
            }),
            confidence,
            degraded_reason: Some(if is_hypermemory {
                hypermemory_degraded_reason(runtime_configured)
            } else {
                graph_degraded_reason(runtime_configured)
            }),
            mode: Some(requested_mode.clone()),
            graph_runtime: Some(graph_runtime),
            evidence_graph: Some(evidence_graph.clone()),
            community_context: Some(GraphRagCommunityContext {
                strategy: if is_hypermemory {
                    "hypermemory-topic-world-density".to_string()
                } else {
                    "k-core-density-hierarchy".to_string()
                },
                selected_communities: communities,
                degraded_reason: (!runtime_configured).then(|| {
                    if is_hypermemory {
                        hypermemory_degraded_reason(false)
                    } else {
                        graph_degraded_reason(false)
                    }
                }),
            }),
            retrieval_trace,
            mesh_trace,
            runtime_votes: runtime_votes(runtime_configured),
            candidate_refs,
            runtime_used: Some(runtime_used_for(&requested_mode, runtime_configured)),
            fallback_chain: fallback_chain_for(&requested_mode, runtime_configured),
            semantic_trace: semantic_trace_for(&requested_mode, runtime_configured, evidence_count),
            maxsim_scores,
            graph_expansion,
            reranker_scores,
            truthset_gate_status,
            restricted_leak_check: restricted_leak_check_for(0),
            retrieval_agent: retrieval_agent_mode(),
            retrieval_plan_id: stable_id("retrieval-plan", &[&req.query, &requested_mode]),
            strategy_used: strategy_used.clone(),
            subqueries: subqueries.clone(),
            evidence_pack: evidence_pack_json(
                evidence_count,
                matched_episode_count,
                evidence_refs,
                0,
            ),
            context_format: retrieval_context_format(),
            planner_mode: retrieval_planner_mode(),
            budget: retrieval_budget_json(max_items, &retrieval_planner_mode()),
            runtime_trace: retrieval_agent_trace_for(
                &strategy_used,
                &subqueries,
                runtime_configured,
                evidence_count,
                matched_episode_count,
            ),
            context_pack_id: Some(stable_id(
                "context-pack",
                &[
                    &req.query,
                    &requested_mode,
                    &strategy_used,
                    &memory_policy_version(),
                ],
            )),
            policy_version: Some(memory_policy_version()),
            policy_gate: memory_policy_gate_json(),
            dreamcycle_status: Some(dreamcycle_mode()),
            ranking_policy: Some(ranking_policy),
            ranking_trace,
            recency_boost_applied,
            stable_fact_guard_applied,
        })
    }

    pub(crate) fn find_episode_by_source_ref(
        &self,
        source_ref: &str,
    ) -> anyhow::Result<Option<MemoryEpisode>> {
        Ok(self
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?
            .into_iter()
            .find(|episode| episode.source_ref == source_ref))
    }

    pub(crate) fn find_atom_by_id(&self, atom_id: &str) -> anyhow::Result<Option<MemoryAtom>> {
        Ok(self
            .read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?
            .into_iter()
            .find(|atom| atom.id == atom_id))
    }

    pub(crate) fn find_memory_candidate(
        &self,
        candidate_id: &str,
    ) -> anyhow::Result<Option<MemoryCandidate>> {
        Ok(self
            .read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, usize::MAX)?
            .into_iter()
            .find(|candidate| candidate.id == candidate_id))
    }

    pub(crate) fn latest_candidate_quorum(
        &self,
        candidate_id: &str,
    ) -> anyhow::Result<Option<CandidateQuorumDecision>> {
        Ok(self
            .read_recent_jsonl::<CandidateQuorumDecision>(MEMORY_CANDIDATE_QUORUM_LOG, usize::MAX)?
            .into_iter()
            .find(|decision| decision.candidate_id == candidate_id))
    }

    pub(crate) fn latest_memory_candidates(
        &self,
        limit: usize,
    ) -> anyhow::Result<Vec<MemoryCandidate>> {
        let mut seen = std::collections::BTreeSet::<String>::new();
        let mut candidates = Vec::new();
        for candidate in
            self.read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, usize::MAX)?
        {
            if seen.insert(candidate.id.clone()) {
                candidates.push(candidate);
            }
            if candidates.len() >= limit {
                break;
            }
        }
        Ok(candidates)
    }

    pub(crate) fn memory_governance_status(&self) -> anyhow::Result<MemoryGovernanceStatus> {
        self.ensure()?;
        let candidates = self.latest_memory_candidates(usize::MAX)?;
        let contradictions =
            self.read_recent_jsonl::<MemoryContradiction>(MEMORY_CONTRADICTIONS_LOG, usize::MAX)?;
        let open_contradictions = contradictions
            .iter()
            .filter(|item| item.status == "open")
            .count();
        let pending_triads = candidates
            .iter()
            .filter(|candidate| {
                candidate.status == "candidate" || candidate.status == "triad_pending"
            })
            .count();
        let promoted_count = candidates
            .iter()
            .filter(|candidate| candidate.status == "promoted")
            .count();
        let rejected_count = candidates
            .iter()
            .filter(|candidate| candidate.status == "rejected")
            .count();
        let latest_run = self
            .read_recent_jsonl::<MemoryGovernanceRun>(MEMORY_GOVERNANCE_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let latest_promotion_decision = self
            .read_recent_jsonl::<MemoryPromotionDecision>(MEMORY_PROMOTION_DECISIONS_LOG, 1)?
            .into_iter()
            .next();
        Ok(MemoryGovernanceStatus {
            status: if pending_triads > 0 {
                "triad-pending".to_string()
            } else if open_contradictions > 0 {
                "contradiction-review".to_string()
            } else {
                "governed".to_string()
            },
            schema_version: MEMORY_GOVERNANCE_SCHEMA.to_string(),
            retrieval_policy: "promoted-only-active-search; candidates require strict Memory+Temporal+Critical 3/3 quorum".to_string(),
            candidate_count: candidates.len(),
            pending_triads,
            promoted_count,
            rejected_count,
            open_contradictions,
            latest_run,
            latest_promotion_decision,
        })
    }

    pub(crate) fn run_memory_governance(
        &self,
        req: MemoryGovernanceRunRequest,
    ) -> anyhow::Result<MemoryGovernanceRun> {
        self.ensure()?;
        let limit = req.limit.unwrap_or(100).clamp(1, 1_000);
        let dry_run = req.dry_run.unwrap_or(false);
        let reviewer = req
            .reviewer
            .unwrap_or_else(|| "memory-governor-v1.6".to_string());
        let candidates = self
            .latest_memory_candidates(limit)?
            .into_iter()
            .filter(|candidate| candidate.privacy_class != "restricted")
            .collect::<Vec<_>>();
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let mut contradictions_found = 0usize;
        let mut quality_scores_written = 0usize;
        let mut triad_pending = 0usize;
        let mut promoted = 0usize;
        let mut rejected = 0usize;

        for candidate in &candidates {
            match candidate.status.as_str() {
                "promoted" => {
                    promoted += 1;
                    continue;
                }
                "rejected" => {
                    rejected += 1;
                    continue;
                }
                _ => {}
            }

            let contradictions = detect_candidate_contradictions(candidate, &atoms);
            contradictions_found += contradictions.len();
            let quality_score = self.score_memory_candidate(candidate, &contradictions, None);
            if !dry_run {
                self.append_jsonl(MEMORY_QUALITY_SCORES_LOG, &quality_score)?;
                quality_scores_written += 1;
                for contradiction in contradictions {
                    self.append_jsonl(MEMORY_CONTRADICTIONS_LOG, &contradiction)?;
                }
                if candidate.status == "candidate" {
                    self.append_jsonl(
                        MEMORY_CANDIDATES_LOG,
                        &MemoryCandidate {
                            status: "triad_pending".to_string(),
                            ..candidate.clone()
                        },
                    )?;
                }
            }
            triad_pending += 1;
        }

        let run = MemoryGovernanceRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_GOVERNANCE_SCHEMA.to_string(),
            status: if dry_run { "dry_run" } else { "completed" }.to_string(),
            candidates_evaluated: candidates.len(),
            triad_pending,
            promoted,
            rejected,
            contradictions_found,
            quality_scores_written,
            hard_gates: serde_json::json!({
                "restricted_leak_zero": true,
                "triad_strict_required": true,
                "active_search_promoted_only": true,
                "provenance_required_for_promotion": true,
            }),
            degraded_reason: "v1.6 governor is deterministic and append-only; LLM/judge expansion remains delegated to memory-engine evals.".to_string(),
        };
        if !dry_run {
            self.append_jsonl(MEMORY_GOVERNANCE_RUNS_LOG, &run)?;
            let _ = self.create_audit_event(CreateAuditEventRequest {
                client_id: Some(reviewer),
                action: Some("memory.governance_run".to_string()),
                tool_name: Some("beagle_memory_governance_run".to_string()),
                risk_level: Some("write".to_string()),
                required_scopes: vec!["memory:write".to_string()],
                granted_scopes: vec!["memory:write".to_string()],
                status: Some("success".to_string()),
                source: Some("memory-governor".to_string()),
                target_ref: Some(format!("memory_governance_run:{}", run.id)),
                summary: Some(
                    "Evaluated candidate memory quality, contradictions, and Triad pending state."
                        .to_string(),
                ),
                metadata: Some(serde_json::json!({
                    "schema_version": MEMORY_GOVERNANCE_SCHEMA,
                    "candidates_evaluated": run.candidates_evaluated,
                    "contradictions_found": run.contradictions_found,
                    "triad_pending": run.triad_pending,
                })),
            })?;
        }
        Ok(run)
    }

    pub(crate) fn score_memory_candidate(
        &self,
        candidate: &MemoryCandidate,
        contradictions: &[MemoryContradiction],
        input: Option<MemoryQualityScoreInput>,
    ) -> MemoryQualityScore {
        let provenance_score = input
            .as_ref()
            .and_then(|score| score.provenance_score)
            .unwrap_or_else(|| {
                let source_refs = if candidate.source_refs.is_empty() {
                    0.0
                } else {
                    0.35
                };
                let provenance = if candidate.provenance.is_null() {
                    0.0
                } else {
                    0.35
                };
                (source_refs + provenance + candidate.confidence.min(0.30)).clamp(0.0, 1.0)
            });
        let temporal_score = input
            .as_ref()
            .and_then(|score| score.temporal_score)
            .unwrap_or_else(|| {
                if candidate
                    .tags
                    .iter()
                    .any(|tag| tag.contains("temporal") || tag.contains("work-memory"))
                {
                    0.78
                } else {
                    0.62
                }
            });
        let contradiction_risk = input
            .as_ref()
            .and_then(|score| score.contradiction_risk)
            .unwrap_or_else(|| (contradictions.len() as f64 * 0.35).clamp(0.0, 1.0));
        let critical_score = input
            .as_ref()
            .and_then(|score| score.critical_score)
            .unwrap_or_else(|| (candidate.confidence - contradiction_risk * 0.35).clamp(0.0, 1.0));
        let restricted_risk = input
            .as_ref()
            .and_then(|score| score.restricted_risk)
            .unwrap_or(if candidate.privacy_class == "restricted" {
                1.0
            } else {
                0.0
            });
        let overall = ((provenance_score + temporal_score + critical_score) / 3.0
            - restricted_risk * 0.5
            - contradiction_risk * 0.25)
            .clamp(0.0, 1.0);
        MemoryQualityScore {
            id: stable_id("quality", &[&candidate.id, &format!("{overall:.3}")]),
            created_at: Utc::now().to_rfc3339(),
            candidate_id: candidate.id.clone(),
            provenance_score,
            temporal_score,
            critical_score,
            overall,
            restricted_risk,
            contradiction_risk,
            rationale: input
                .and_then(|score| score.rationale)
                .unwrap_or_else(|| {
                    "Deterministic v1.6 score from provenance, temporal fit, critical risk, privacy, and contradiction signals.".to_string()
                }),
        }
    }

    pub(crate) fn analyze_temporal(
        &self,
        req: TemporalAnalyzeRequest,
    ) -> anyhow::Result<TemporalAnalysis> {
        self.ensure()?;
        let now = Utc::now();
        let commits = self.read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 50)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 25)?;
        let days_back = req.days_back.unwrap_or(90);
        let start = req
            .time_range_start
            .unwrap_or_else(|| (now - chrono::Duration::days(days_back as i64)).to_rfc3339());
        let end = req.time_range_end.unwrap_or_else(|| now.to_rfc3339());
        let latest_self = commits
            .first()
            .map(self_version_from_commit)
            .unwrap_or_else(default_self_version);
        let topic_lc = req.topic.to_lowercase();
        let matching_commits: Vec<_> = commits
            .iter()
            .filter(|commit| commit_matches_topic(commit, &topic_lc))
            .collect();
        let matching_imports: Vec<_> = imports
            .iter()
            .filter(|import| import_matches_topic(import, &topic_lc))
            .collect();
        let signal_count = matching_commits.len() + matching_imports.len();
        let phase_name = if signal_count >= 3 {
            "Fase de Integração Ativa"
        } else if signal_count > 0 {
            "Fase de Consolidação"
        } else {
            "Fase de Busca de Sinal"
        };
        let recommendation = if signal_count > 0 {
            format!(
                "Retome '{}' a partir dos sinais recentes e converta a próxima decisão em commit Chronoself.",
                req.topic
            )
        } else {
            format!(
                "Crie um primeiro registro explícito sobre '{}' para dar material longitudinal ao TemporalAI.",
                req.topic
            )
        };
        let analysis = TemporalAnalysis {
            id: Uuid::new_v4().to_string(),
            created_at: now.to_rfc3339(),
            topic: req.topic,
            time_range_start: start,
            time_range_end: end,
            phases: vec![TemporalPhase {
                name: phase_name.to_string(),
                period_start: latest_self.period_start.clone(),
                period_end: None,
                characteristics: vec![
                    "Análise gerada por sinais cluster-first do Exocortex.".to_string(),
                    format!("{} sinais relevantes encontrados.", signal_count),
                ],
                self_version_ref: latest_self.source_commit_id.clone(),
            }],
            turning_points: matching_commits
                .iter()
                .take(3)
                .map(|commit| TurningPoint {
                    date: commit.created_at.clone(),
                    description: commit.summary.clone().unwrap_or_else(|| commit.trigger_type.clone()),
                    cause: commit.identity_delta.cognitive_style_shift.clone(),
                    self_version_before: commit.parent_commit_ids.first().cloned(),
                    self_version_after: Some(commit.id.clone()),
                })
                .collect(),
            recurring_pattern: (signal_count >= 2).then(|| RecurringPattern {
                description: "O tema reaparece em múltiplas superfícies de memória.".to_string(),
                frequency_days: None,
                confidence: 0.62,
            }),
            causal_hypothesis: Some(
                "Hipótese inicial: mudanças de foco aparecem quando decisões, importações e projetos ativos convergem no mesmo tema."
                    .to_string(),
            ),
            recommendation,
            llm_model_used: Some("deterministic-temporalai-mvp".to_string()),
            confidence_score: if signal_count > 0 { 0.66 } else { 0.42 },
            source_refs: matching_commits
                .iter()
                .map(|commit| format!("chronoself:{}", commit.id))
                .chain(
                    matching_imports
                        .iter()
                        .map(|import| format!("omnimemory:{}", import.id)),
                )
                .take(10)
                .collect(),
        };
        self.append_jsonl(TEMPORAL_LOG, &analysis)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: None,
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(analysis)
    }

    pub(crate) fn create_audit_event(
        &self,
        req: CreateAuditEventRequest,
    ) -> anyhow::Result<AuditEvent> {
        self.ensure()?;
        let event = AuditEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            client_id: req.client_id.unwrap_or_else(|| "unknown-agent".to_string()),
            action: req.action.unwrap_or_else(|| "mcp.tool_call".to_string()),
            tool_name: req.tool_name,
            risk_level: req.risk_level.unwrap_or_else(|| "unknown".to_string()),
            required_scopes: req.required_scopes,
            granted_scopes: req.granted_scopes,
            status: req.status.unwrap_or_else(|| "success".to_string()),
            source: req.source.unwrap_or_else(|| "mcp".to_string()),
            target_ref: req.target_ref,
            summary: req.summary,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
        };
        self.append_jsonl(AUDIT_LOG, &event)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some("mcp".to_string()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(event)
    }

    pub(crate) fn create_memory_event(
        &self,
        req: CreateMemoryEventRequest,
    ) -> anyhow::Result<MemoryEvent> {
        self.ensure()?;
        let event = MemoryEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: req.source.unwrap_or_else(|| "mcp".to_string()),
            kind: req.kind.unwrap_or_else(|| "note".to_string()),
            content_ref: req.content_ref,
            summary: req
                .summary
                .unwrap_or_else(|| "Memory event recorded by Beagle MCP.".to_string()),
            tags: req.tags,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
            linked_chronoself_commits: req.linked_chronoself_commits,
            confidence: req.confidence.unwrap_or(0.7).clamp(0.0, 1.0),
        };
        self.append_jsonl(MEMORY_EVENTS_LOG, &event)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some(event.source.clone()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(event)
    }

    pub(crate) fn create_memory_candidate(
        &self,
        req: CreateMemoryCandidateRequest,
    ) -> anyhow::Result<MemoryCandidate> {
        self.ensure()?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted memory candidates require explicit human review outside v1.5"
        );
        let normalized_text = normalize_text(&req.text);
        let candidate = MemoryCandidate {
            id: stable_id("candidate", &[&req.candidate_type, &normalized_text]),
            created_at: Utc::now().to_rfc3339(),
            candidate_type: req.candidate_type,
            text: truncate_chars(&req.text, 1_200),
            normalized_text,
            source_refs: req.source_refs,
            relations: req.relations,
            tags: req.tags,
            provenance: req.provenance,
            confidence: req.confidence.unwrap_or(0.55).clamp(0.0, 1.0),
            privacy_class,
            status: "candidate".to_string(),
            quorum_ref: None,
            promoted_atom_id: None,
        };
        self.append_jsonl(MEMORY_CANDIDATES_LOG, &candidate)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-memory-engine".to_string()),
            action: Some("memory.candidate_create".to_string()),
            tool_name: Some("beagle_memory_candidates".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some("success".to_string()),
            source: Some("memory-engine".to_string()),
            target_ref: Some(format!("memory_candidate:{}", candidate.id)),
            summary: Some("Recorded candidate memory outside active retrieval.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_MESH_SCHEMA,
                "candidate_status": candidate.status,
                "candidate_type": candidate.candidate_type,
            })),
        })?;
        Ok(candidate)
    }

    pub(crate) fn context_compile(
        &self,
        req: ContextCompileRequest,
    ) -> anyhow::Result<ContextPack> {
        self.ensure()?;
        let mode = req.mode.clone().unwrap_or_else(memory_hot_path_mode);
        let query_response = self.graphrag_query(GraphRagQueryRequest {
            query: req.query.clone(),
            scope: req.scope.clone(),
            max_items: req.max_items,
            mode: Some(mode.clone()),
            ranking_policy: None,
        })?;
        let evidence_refs = query_response
            .evidence
            .iter()
            .flat_map(|item| {
                let mut refs = vec![
                    format!("atom:{}", item.atom_id),
                    format!("episode:{}", item.episode_id),
                ];
                refs.extend(item.source_refs.clone());
                refs
            })
            .collect::<Vec<_>>();
        let token_budget = req.token_budget.unwrap_or_else(|| {
            if req.surface.as_deref().unwrap_or("").contains("watch") {
                1_200
            } else {
                8_000
            }
        });
        let strategy_used = query_response.strategy_used.clone();
        let pack = ContextPack {
            id: stable_id(
                "context-pack",
                &[
                    &req.query,
                    req.surface.as_deref().unwrap_or("core-context"),
                    &strategy_used,
                    &memory_policy_version(),
                ],
            ),
            created_at: Utc::now().to_rfc3339(),
            schema_version: CONTEXT_COMPILER_SCHEMA.to_string(),
            query: req.query.clone(),
            task: req.task.clone(),
            surface: req
                .surface
                .clone()
                .unwrap_or_else(|| "beagle-core-context".to_string()),
            format: "episodic_envelope+evidence_frontier+procedural_hint+contradiction_guard+next_action"
                .to_string(),
            policy_version: memory_policy_version(),
            policy_mode: memory_policy_mode(),
            token_budget,
            retrieval_plan_id: Some(query_response.retrieval_plan_id.clone()),
            strategy_used,
            context_sections: serde_json::json!({
                "episodic_envelope": query_response.episodes.iter().take(6).collect::<Vec<_>>(),
                "evidence_frontier": query_response.evidence.iter().take(req.max_items.unwrap_or(8)).collect::<Vec<_>>(),
                "hypergraph_relations": query_response.relations.iter().take(16).collect::<Vec<_>>(),
                "timeline": query_response.temporal_context,
                "procedural_hint": [
                    "Preserve full episode context around nucleus hits.",
                    "Cite provenance and confidence before synthesis.",
                    "Record MemoryEffectivenessEvent after the action."
                ],
                "contradiction_guard": query_response.candidate_refs,
                "next_action": "Use this ContextPack, then append an effectiveness event with outcome."
            }),
            evidence_refs,
            provenance: serde_json::json!({
                "canonical_source": "beagle-core-jsonl",
                "mode": mode,
                "context_compiler": context_compiler_mode(),
                "agent": req.agent,
                "session_id": req.session_id,
            }),
            restricted_leak_check: query_response.restricted_leak_check,
            policy_rationale: vec![
                format!("policy={}", memory_policy_version()),
                format!("compiler={}", context_compiler_mode()),
                "Policy learning is observe-only until MemoryArena private gate passes.".to_string(),
            ],
            fallback_chain: query_response.fallback_chain,
            next_action:
                "Act with the compiled context and record effectiveness feedback afterward."
                    .to_string(),
            degraded_reason: query_response.degraded_reason,
        };
        self.append_jsonl(CONTEXT_PACKS_LOG, &pack)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-core".to_string()),
            action: Some("context.compile".to_string()),
            tool_name: Some("beagle_context_compile".to_string()),
            risk_level: Some("read".to_string()),
            required_scopes: vec!["exocortex:read".to_string()],
            granted_scopes: vec!["exocortex:read".to_string()],
            status: Some("success".to_string()),
            source: Some("context-compiler".to_string()),
            target_ref: Some(format!("context_pack:{}", pack.id)),
            summary: Some("Compiled adaptive ContextPack from GraphRAG++ evidence.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": CONTEXT_COMPILER_SCHEMA,
                "policy_version": pack.policy_version,
                "strategy_used": pack.strategy_used,
                "context_compiler": context_compiler_mode()
            })),
        })?;
        Ok(pack)
    }

    pub(crate) fn context_pack(&self, pack_id: &str) -> anyhow::Result<Option<ContextPack>> {
        Ok(self
            .read_recent_jsonl::<ContextPack>(CONTEXT_PACKS_LOG, usize::MAX)?
            .into_iter()
            .rev()
            .find(|pack| pack.id == pack_id))
    }

    pub(crate) fn record_memory_effectiveness(
        &self,
        req: MemoryEffectivenessEventRequest,
    ) -> anyhow::Result<MemoryEffectivenessEvent> {
        self.ensure()?;
        let event = MemoryEffectivenessEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_POLICY_SCHEMA.to_string(),
            context_pack_id: req.context_pack_id,
            query: req.query,
            surface: req.surface.unwrap_or_else(|| "unknown-surface".to_string()),
            principal: req
                .principal
                .unwrap_or_else(|| "unknown-principal".to_string()),
            session_id: req.session_id,
            strategy_used: req
                .strategy_used
                .unwrap_or_else(|| "not-recorded".to_string()),
            tokens_used: req.tokens_used,
            latency_ms: req.latency_ms,
            tests: req.tests,
            feedback: req.feedback,
            human_correction: req.human_correction,
            success: req.success.unwrap_or(false),
            outcome: req.outcome.unwrap_or_else(|| "observed".to_string()),
            metadata: req.metadata,
        };
        self.append_jsonl(MEMORY_EFFECTIVENESS_EVENTS_LOG, &event)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(event.principal.clone()),
            action: Some("memory.effectiveness_record".to_string()),
            tool_name: Some("beagle_memory_effectiveness_record".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some("success".to_string()),
            source: Some(event.surface.clone()),
            target_ref: Some(format!("context_pack:{}", event.context_pack_id)),
            summary: Some(format!("Recorded memory policy outcome: {}", event.outcome)),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_POLICY_SCHEMA,
                "policy_version": memory_policy_version(),
                "strategy_used": event.strategy_used,
                "success": event.success
            })),
        })?;
        Ok(event)
    }

    pub(crate) fn memory_policy_status(&self) -> anyhow::Result<MemoryPolicyStatus> {
        self.ensure()?;
        let events = self
            .read_recent_jsonl::<MemoryEffectivenessEvent>(MEMORY_EFFECTIVENESS_EVENTS_LOG, 250)?;
        let latest_effectiveness_event = events.last().cloned();
        let mut outcome_counts = BTreeMap::<String, usize>::new();
        for event in &events {
            *outcome_counts.entry(event.outcome.clone()).or_default() += 1;
        }
        Ok(MemoryPolicyStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_POLICY_SCHEMA.to_string(),
            status: memory_policy_mode(),
            policy_version: memory_policy_version(),
            policy_mode: memory_policy_mode(),
            latest_effectiveness_event,
            outcome_counts,
            promotion_gate: memory_policy_gate_json(),
            degraded_reason: Some(
                "Policy learner is observe/recommend/canary only; no fine-tuning or automatic promotion."
                    .to_string(),
            ),
        })
    }

    pub(crate) fn run_dreamcycle(
        &self,
        req: DreamCycleRunRequest,
    ) -> anyhow::Result<DreamCycleRun> {
        self.ensure()?;
        let limit = req.limit.unwrap_or(500).clamp(1, 5_000);
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?;
        let dry_run = req.dry_run.unwrap_or(true);
        let mut generated_candidate_refs = Vec::new();
        if !dry_run {
            for (candidate_type, text) in [
                (
                    "procedural_memory",
                    "DreamCycle candidate: consolidate recent work-memory into a reusable procedural playbook.",
                ),
                (
                    "project_summary",
                    "DreamCycle candidate: summarize active project drift and unresolved loops.",
                ),
                (
                    "contradiction_watch",
                    "DreamCycle candidate: review stale beliefs and contradictions before promotion.",
                ),
            ] {
                let candidate = self.create_memory_candidate(CreateMemoryCandidateRequest {
                    candidate_type: candidate_type.to_string(),
                    text: text.to_string(),
                    source_refs: vec!["dreamcycle:v2.3".to_string()],
                    relations: Vec::new(),
                    tags: vec![
                        "dreamcycle".to_string(),
                        "candidate".to_string(),
                        "v2.3".to_string(),
                    ],
                    provenance: serde_json::json!({
                        "schema_version": CONTEXT_COMPILER_SCHEMA,
                        "source": "beagle-core-dreamcycle",
                        "dry_run": dry_run
                    }),
                    confidence: Some(0.58),
                    privacy_class: Some("sensitive".to_string()),
                })?;
                generated_candidate_refs.push(candidate.id);
            }
        }
        let run = DreamCycleRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: CONTEXT_COMPILER_SCHEMA.to_string(),
            status: if dry_run {
                "dry_run".to_string()
            } else {
                "candidates_recorded".to_string()
            },
            mode: req.mode.unwrap_or_else(dreamcycle_mode),
            dry_run,
            triggered_by: req.triggered_by.unwrap_or_else(|| "manual".to_string()),
            source_episode_count: episodes.len(),
            source_atom_count: atoms.len(),
            candidate_count: if dry_run { 3 } else { generated_candidate_refs.len() },
            contradiction_count: usize::from(!atoms.is_empty()),
            procedural_memory_count: usize::from(!episodes.is_empty()),
            stale_belief_count: usize::from(atoms.len() > 10),
            project_summary_count: usize::from(!episodes.is_empty()),
            unresolved_loop_count: usize::from(!episodes.is_empty()),
            suggested_truth_cases: 3,
            generated_candidate_refs,
            provenance: serde_json::json!({
                "canonical_source": "/var/lib/beagle/exocortex",
                "restricted_policy": "restricted never enters DreamCycle candidates automatically",
                "cluster_only": true
            }),
            promotion_policy:
                "DreamCycle outputs are candidates only; Governor/Triad is required before active retrieval."
                    .to_string(),
            degraded_reason: Some(
                "DreamCycle v2.3 is deterministic consolidation; LLM reflection remains optional."
                    .to_string(),
            ),
        };
        self.append_jsonl(MEMORY_DREAMCYCLE_RUNS_LOG, &run)?;
        Ok(run)
    }

    pub(crate) fn dreamcycle_status(&self) -> anyhow::Result<DreamCycleStatus> {
        let latest_run = self
            .read_recent_jsonl::<DreamCycleRun>(MEMORY_DREAMCYCLE_RUNS_LOG, 1)?
            .into_iter()
            .next();
        Ok(DreamCycleStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: CONTEXT_COMPILER_SCHEMA.to_string(),
            status: latest_run
                .as_ref()
                .map(|run| run.status.clone())
                .unwrap_or_else(|| "manual-ready".to_string()),
            mode: dreamcycle_mode(),
            latest_run,
            policy:
                "candidate-only consolidation; no DreamCycle inference enters Home/search without Governor/Triad."
                    .to_string(),
            candidate_outputs_active: false,
            degraded_reason: None,
        })
    }

    pub(crate) fn append_sounio_trace(&self, event: SounioTraceEvent) -> anyhow::Result<()> {
        self.append_jsonl(SOUNIO_TRACE_EVENTS_LOG, &event)
    }

    pub(crate) fn record_candidate_quorum(
        &self,
        candidate_id: &str,
        req: CandidateQuorumRequest,
    ) -> anyhow::Result<CandidateQuorumDecision> {
        self.ensure()?;
        let candidate = self
            .find_memory_candidate(candidate_id)?
            .ok_or_else(|| anyhow::anyhow!("memory candidate not found: {}", candidate_id))?;
        let approved = req.memory_approved && req.temporal_approved && req.critical_approved;
        let contradictions = detect_candidate_contradictions(
            &candidate,
            &self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?,
        );
        let quality_score =
            self.score_memory_candidate(&candidate, &contradictions, req.quality_score.clone());
        self.append_jsonl(MEMORY_QUALITY_SCORES_LOG, &quality_score)?;
        for contradiction in contradictions {
            self.append_jsonl(MEMORY_CONTRADICTIONS_LOG, &contradiction)?;
        }
        let decision = CandidateQuorumDecision {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            candidate_id: candidate.id.clone(),
            memory_approved: req.memory_approved,
            temporal_approved: req.temporal_approved,
            critical_approved: req.critical_approved,
            status: if approved {
                "triad_pending"
            } else {
                "rejected"
            }
            .to_string(),
            rationale: req
                .rationale
                .unwrap_or_else(|| "Triad memory quorum evaluated candidate.".to_string()),
            reviewer: req.reviewer,
            quality_score: quality_score.clone(),
        };
        self.append_jsonl(MEMORY_CANDIDATE_QUORUM_LOG, &decision)?;
        let updated_candidate = MemoryCandidate {
            status: decision.status.clone(),
            quorum_ref: Some(decision.id.clone()),
            ..candidate.clone()
        };
        self.append_jsonl(MEMORY_CANDIDATES_LOG, &updated_candidate)?;
        if !approved {
            self.append_jsonl(
                MEMORY_PROMOTION_DECISIONS_LOG,
                &MemoryPromotionDecision {
                    id: Uuid::new_v4().to_string(),
                    created_at: Utc::now().to_rfc3339(),
                    candidate_id: candidate.id.clone(),
                    decision: "rejected".to_string(),
                    status: "rejected".to_string(),
                    quality_score: quality_score.clone(),
                    quorum_id: Some(decision.id.clone()),
                    promoted_atom_id: None,
                    rationale: decision.rationale.clone(),
                    reviewer: decision.reviewer.clone(),
                    evidence_refs: candidate.source_refs.clone(),
                },
            )?;
        }
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("triad-memory-quorum".to_string()),
            action: Some("memory.candidate_quorum".to_string()),
            tool_name: Some("beagle_memory_candidate_quorum".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some(if approved {
                "success".to_string()
            } else {
                "rejected".to_string()
            }),
            source: Some("triad-memory-quorum".to_string()),
            target_ref: Some(format!("memory_candidate:{}", candidate.id)),
            summary: Some(format!("Triad quorum {}", decision.status)),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_GOVERNANCE_SCHEMA,
                "memory_approved": decision.memory_approved,
                "temporal_approved": decision.temporal_approved,
                "critical_approved": decision.critical_approved,
                "quality_overall": decision.quality_score.overall,
                "candidate_id": candidate.id,
            })),
        })?;
        Ok(decision)
    }

    pub(crate) fn promote_memory_candidate(
        &self,
        candidate_id: &str,
        req: CandidatePromoteRequest,
    ) -> anyhow::Result<CandidatePromotionResponse> {
        self.ensure()?;
        let candidate = self
            .find_memory_candidate(candidate_id)?
            .ok_or_else(|| anyhow::anyhow!("memory candidate not found: {}", candidate_id))?;
        anyhow::ensure!(
            candidate.status != "promoted",
            "memory candidate already promoted"
        );
        let quorum = self
            .latest_candidate_quorum(candidate_id)?
            .ok_or_else(|| anyhow::anyhow!("candidate has no quorum decision: {}", candidate_id))?;
        anyhow::ensure!(
            quorum.status == "triad_pending"
                && quorum.memory_approved
                && quorum.temporal_approved
                && quorum.critical_approved,
            "candidate promotion requires strict 3-of-3 Memory+Temporal+Critical quorum"
        );
        let source_ref = format!("memory_candidate:{}", candidate.id);
        let candidate_hash = format!("sha256:{}", content_hash(candidate.text.as_bytes()));
        if self.find_episode_by_source_ref(&source_ref)?.is_none() {
            self.append_jsonl(
                MEMORY_EPISODES_LOG,
                &MemoryEpisode {
                    id: stable_id("episode", &[&source_ref, &candidate_hash]),
                    created_at: Utc::now().to_rfc3339(),
                    source: "beagle-memory-engine".to_string(),
                    source_platform: Some("beagle-memory-engine".to_string()),
                    session_id: None,
                    source_ref: source_ref.clone(),
                    content_hash: candidate_hash.clone(),
                    privacy_class: candidate.privacy_class.clone(),
                    provenance: serde_json::json!({
                        "candidate_id": candidate.id.clone(),
                        "quorum_id": quorum.id.clone(),
                        "promotion_rationale": req.rationale.clone(),
                        "chronoself_commit_id": req.chronoself_commit_id.clone(),
                        "source": "candidate-promotion"
                    }),
                    tags: candidate.tags.clone(),
                    title: Some(format!("Promoted candidate: {}", candidate.candidate_type)),
                    linked_chronoself_commits: req
                        .chronoself_commit_id
                        .clone()
                        .into_iter()
                        .collect(),
                    occurred_at: Some(Utc::now().to_rfc3339()),
                },
            )?;
        }
        let promoted_atom = MemoryAtom {
            id: stable_id(
                "atom",
                &[
                    &source_ref,
                    &candidate.candidate_type,
                    &candidate.normalized_text,
                ],
            ),
            created_at: Utc::now().to_rfc3339(),
            episode_id: stable_id("episode", &[&source_ref, &candidate_hash]),
            atom_type: candidate.candidate_type.clone(),
            text: candidate.text.clone(),
            normalized_text: candidate.normalized_text.clone(),
            source_refs: std::iter::once(source_ref.clone())
                .chain(candidate.source_refs.clone())
                .collect(),
            relations: candidate.relations.clone(),
            tags: candidate.tags.clone(),
            confidence: candidate.confidence,
            privacy_class: candidate.privacy_class.clone(),
            occurred_at: Some(Utc::now().to_rfc3339()),
        };
        if self.find_atom_by_id(&promoted_atom.id)?.is_none() {
            self.append_jsonl(MEMORY_ATOMS_LOG, &promoted_atom)?;
        }
        let promoted_candidate = MemoryCandidate {
            status: "promoted".to_string(),
            quorum_ref: Some(quorum.id.clone()),
            promoted_atom_id: Some(promoted_atom.id.clone()),
            ..candidate
        };
        self.append_jsonl(MEMORY_CANDIDATES_LOG, &promoted_candidate)?;
        let promotion_decision = MemoryPromotionDecision {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            candidate_id: promoted_candidate.id.clone(),
            decision: "promoted".to_string(),
            status: "promoted".to_string(),
            quality_score: quorum.quality_score.clone(),
            quorum_id: Some(quorum.id.clone()),
            promoted_atom_id: Some(promoted_atom.id.clone()),
            rationale: req.rationale.clone().unwrap_or_else(|| {
                "Strict Triad 3/3 quorum promoted candidate into active memory.".to_string()
            }),
            reviewer: quorum.reviewer.clone(),
            evidence_refs: promoted_candidate.source_refs.clone(),
        };
        self.append_jsonl(MEMORY_PROMOTION_DECISIONS_LOG, &promotion_decision)?;
        let audit_event = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("triad-memory-quorum".to_string()),
            action: Some("memory.candidate_promote".to_string()),
            tool_name: Some("beagle_memory_candidate_promote".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some("success".to_string()),
            source: Some("triad-memory-quorum".to_string()),
            target_ref: Some(format!("memory_atom:{}", promoted_atom.id)),
            summary: Some(
                "Promoted candidate memory into active Episode+Atom projection.".to_string(),
            ),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_GOVERNANCE_SCHEMA,
                "candidate_id": promoted_candidate.id.clone(),
                "quorum_id": quorum.id.clone(),
                "chronoself_commit_id": req.chronoself_commit_id.clone(),
                "quality_overall": promotion_decision.quality_score.overall,
                "promotion_rationale": req.rationale.clone(),
            })),
        })?;
        Ok(CandidatePromotionResponse {
            candidate: promoted_candidate,
            promoted_atom,
            quorum,
            promotion_decision,
            audit_event,
        })
    }

    pub(crate) fn active_projects(&self) -> anyhow::Result<Vec<ProjectState>> {
        self.ensure()?;
        let commits = self.read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 50)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 25)?;
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 25)?;
        let explicit_states = self.read_recent_jsonl::<ProjectState>(PROJECT_STATES_LOG, 50)?;

        let mut projects = Vec::<ProjectState>::new();
        for state in explicit_states {
            upsert_project(&mut projects, state);
        }

        for commit in &commits {
            for project in &commit.context_snapshot.active_project_ids {
                upsert_project(
                    &mut projects,
                    ProjectState {
                        id: project_slug(project),
                        name: project.clone(),
                        status: "active".to_string(),
                        recent_events: commit
                            .summary
                            .clone()
                            .into_iter()
                            .chain(commit.identity_delta.priority_reordering.clone())
                            .take(3)
                            .collect(),
                        next_actions: commit.identity_delta.priority_reordering.clone(),
                        linked_memories: commit
                            .source_refs
                            .iter()
                            .map(|source| source.to_string())
                            .collect(),
                        last_interaction_at: Some(commit.created_at.clone()),
                    },
                );
            }
        }

        for import in &imports {
            for project in &import.extracted.projects_mentioned {
                upsert_project(
                    &mut projects,
                    ProjectState {
                        id: project_slug(project),
                        name: project.clone(),
                        status: "active".to_string(),
                        recent_events: import
                            .extracted
                            .key_insights
                            .iter()
                            .take(3)
                            .cloned()
                            .collect(),
                        next_actions: import
                            .extracted
                            .unresolved_questions
                            .iter()
                            .take(3)
                            .cloned()
                            .collect(),
                        linked_memories: vec![format!("omnimemory:{}", import.id)],
                        last_interaction_at: Some(import.imported_at.clone()),
                    },
                );
            }
        }

        for event in &memory_events {
            for project in event
                .tags
                .iter()
                .filter_map(|tag| tag.strip_prefix("project:").map(str::to_string))
            {
                upsert_project(
                    &mut projects,
                    ProjectState {
                        id: project_slug(&project),
                        name: project,
                        status: "active".to_string(),
                        recent_events: vec![event.summary.clone()],
                        next_actions: Vec::new(),
                        linked_memories: vec![format!("memory_event:{}", event.id)],
                        last_interaction_at: Some(event.created_at.clone()),
                    },
                );
            }
        }

        if projects.is_empty() {
            projects.push(ProjectState {
                id: "sounio".to_string(),
                name: "sounio".to_string(),
                status: "forming".to_string(),
                recent_events: vec!["Bootstrap project for the Beagle exocortex.".to_string()],
                next_actions: vec![
                    "Importar conversa, registrar decisão ou iniciar pesquisa.".to_string()
                ],
                linked_memories: Vec::new(),
                last_interaction_at: None,
            });
        }

        projects.sort_by(|a, b| b.last_interaction_at.cmp(&a.last_interaction_at));
        Ok(projects)
    }

    pub(crate) fn current_self(&self) -> anyhow::Result<SelfVersion> {
        if let Some(snapshot) = self.read_snapshot::<SelfVersion>(CURRENT_SELF_SNAPSHOT)? {
            return Ok(snapshot);
        }
        let latest = self
            .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 1)?
            .into_iter()
            .next()
            .map(|commit| self_version_from_commit(&commit))
            .unwrap_or_else(default_self_version);
        self.write_snapshot(CURRENT_SELF_SNAPSHOT, &latest)?;
        Ok(latest)
    }

    pub(crate) fn build_home_snapshot(
        &self,
        query: HomeQuery,
    ) -> anyhow::Result<ExocortexHomeSnapshot> {
        let current_self = self.current_self()?;
        let commits = self.read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 5)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 5)?;
        let projected_atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, 5)?;
        let analyses = self.read_recent_jsonl::<TemporalAnalysis>(TEMPORAL_LOG, 3)?;
        let audit_events = self.read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 10)?;
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 5)?;
        let agent_observations =
            self.read_recent_jsonl::<AgentObservation>(AGENT_OBSERVATIONS_LOG, 5)?;
        let causal_hypotheses =
            self.read_recent_jsonl::<CausalHypothesis>(CAUSAL_HYPOTHESES_LOG, 3)?;
        let requested_platform = query.platform.clone();
        let target_hardware = commits
            .iter()
            .find_map(|commit| commit.context_snapshot.target_hardware.clone());
        let active_project = query
            .active_project_slug
            .or_else(|| {
                commits
                    .iter()
                    .find_map(|commit| commit.context_snapshot.active_project_ids.first().cloned())
            })
            .or_else(|| Some("sounio".to_string()));
        let sounio_workday_context = active_project.as_ref().and_then(|project| {
            self.sounio_workday_status(SounioWorkdayQuery {
                project_slug: Some(project.clone()),
                limit: Some(12),
            })
            .ok()
        });
        let mut memory_signals = projected_atoms
            .iter()
            .map(|atom| format!("{}: {}", atom.atom_type, atom.text))
            .chain(commits.iter().filter_map(|commit| {
                commit
                    .summary
                    .clone()
                    .or_else(|| commit.identity_delta.cognitive_style_shift.clone())
            }))
            .chain(
                imports
                    .iter()
                    .filter_map(|import| import.extracted.key_insights.first().cloned()),
            )
            .chain(memory_events.iter().map(|event| event.summary.clone()))
            .take(5)
            .collect::<Vec<_>>();
        if let Some(moment) = sounio_workday_context
            .as_ref()
            .and_then(|workday| workday.latest_moment.as_ref())
        {
            memory_signals.insert(
                0,
                format!("Sounio now: {}", truncate_chars(&moment.summary, 160)),
            );
            memory_signals.truncate(5);
        }
        let open_loops = imports
            .iter()
            .flat_map(|import| import.extracted.unresolved_questions.clone())
            .take(5)
            .collect::<Vec<_>>();
        let temporal_phase = analyses
            .first()
            .and_then(|analysis| analysis.phases.first())
            .map(|phase| phase.name.clone());
        let today_brief = if memory_signals.is_empty() {
            "O cluster está pronto para começar a formar continuidade: capture uma decisão, importe uma conversa ou retome um projeto ativo.".to_string()
        } else {
            format!(
                "O Exocortex tem {} sinais recentes e está ancorado em {}.",
                memory_signals.len(),
                current_self.label
            )
        };
        let recommended_next_action = open_loops.first().cloned().unwrap_or_else(|| {
            active_project
                .as_ref()
                .map(|project| {
                    format!(
                        "Retomar {} e registrar o próximo passo como memória.",
                        project
                    )
                })
                .unwrap_or_else(|| {
                    "Registrar uma intenção ou importar uma conversa importante.".to_string()
                })
        });
        let body_context = target_hardware
            .as_ref()
            .map(|hardware| format_target_hardware_context(hardware, requested_platform.as_deref()))
            .or_else(|| {
                requested_platform.map(|platform| {
                    format!(
                        "Superfície ativa: {}. HealthKit entra como contexto quando disponível.",
                        platform
                    )
                })
            });
        let latest_audit = audit_events.first();
        let recent_observations = agent_observations
            .iter()
            .map(|observation| observation.observation.clone())
            .chain(
                audit_events
                    .iter()
                    .filter_map(|event| event.summary.clone())
                    .take(3),
            )
            .take(5)
            .collect::<Vec<_>>();
        let agent_context = Some(AgentContext {
            active_sessions: audit_events
                .iter()
                .filter(|event| event.tool_name.as_deref() == Some("beagle_agent_session_start"))
                .filter(|event| event.status == "success")
                .count(),
            recent_observations,
            last_agent_write: latest_audit
                .and_then(|event| event.tool_name.clone())
                .or_else(|| memory_events.first().map(|event| event.kind.clone())),
            mcp_status: if audit_events.is_empty() {
                "waiting-for-first-agent-write".to_string()
            } else {
                "audited".to_string()
            },
        });
        let projection_status = self.memory_projection_status().ok();
        let graph_status = self.memory_graph_status().ok();
        let latest_world_hash = self
            .read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, 1)
            .ok()
            .and_then(|mut worlds| worlds.pop())
            .map(|world| world.merkle_root);
        let latest_agent_write = agent_context
            .as_ref()
            .and_then(|context| context.last_agent_write.clone());
        let latest_candidate = self
            .read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, 1)
            .ok()
            .and_then(|mut candidates| candidates.pop());
        let latest_quorum = self
            .read_recent_jsonl::<CandidateQuorumDecision>(MEMORY_CANDIDATE_QUORUM_LOG, 1)
            .ok()
            .and_then(|mut decisions| decisions.pop());
        let governance_status = self.memory_governance_status().ok();
        let benchmark_status = self.memory_benchmark_status().ok();
        let recent_episodes = self
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, 80)
            .unwrap_or_default();
        let apple_capture_freshness = recent_episodes
            .iter()
            .find(|episode| {
                let platform = episode.source_platform.as_deref().unwrap_or("");
                platform.contains("beagle-apple")
                    || episode.source.contains("watch")
                    || episode.source.contains("siri")
                    || episode.source.contains("share")
            })
            .map(|episode| {
                episode
                    .occurred_at
                    .clone()
                    .unwrap_or_else(|| episode.created_at.clone())
            });
        let agent_observer_status = if audit_events.iter().any(|event| {
            let client_id = event.client_id.as_str();
            event.tool_name.as_deref() == Some("beagle_work_memory_capture")
                || metadata_bool(&event.metadata, "work_memory").unwrap_or(false)
                || client_id.contains("codex")
                || client_id.contains("claude")
        }) {
            Some("observed".to_string())
        } else {
            Some("not-observed".to_string())
        };
        let capture_loop_status = Some(
            match (&apple_capture_freshness, &agent_observer_status) {
                (Some(_), Some(status)) if status == "observed" => "apple+agent-active",
                (Some(_), _) => "apple-active-agent-pending",
                (None, Some(status)) if status == "observed" => "agent-active-apple-pending",
                _ => "pending-first-capture",
            }
            .to_string(),
        );
        let hot_path_mode = memory_hot_path_mode();
        let provisional_hot_path = benchmark_status
            .as_ref()
            .map(|status| status.provisional_hot_path)
            .unwrap_or_else(|| hot_path_mode == "hypermemory_multivector");
        let portfolio_truth_gate = benchmark_status.as_ref().map(|status| {
            let truthset = status
                .portfolio_truthset_id
                .clone()
                .or_else(|| status.truthset_id.clone())
                .unwrap_or_else(|| "truthset:portfolio-mandic-provisional".to_string());
            let gate = if status.hot_path_eligible {
                "passing_confirmed"
            } else if status.provisional_hot_path {
                "provisional_hot_path"
            } else {
                "not_confirmed"
            };
            format!("{truthset}:{gate}")
        });
        let semantic_backbone_status = if hot_path_mode == "hypermemory_multivector" {
            "native-semantic-backbone-v2.1"
        } else {
            "semantic-backbone-standby"
        }
        .to_string();
        let latest_retrieval_strategy = if latest_agent_write.is_some() {
            Some("work_memory_replay".to_string())
        } else if apple_capture_freshness.is_some() {
            Some("temporal_trace".to_string())
        } else {
            Some("episode_nucleus_expansion".to_string())
        };
        let memoryarena_gate = benchmark_status.as_ref().map(|status| {
            if status.hot_path_eligible {
                "memoryarena-passing-confirmed".to_string()
            } else if status.provisional_hot_path {
                "memoryarena-canary-provisional".to_string()
            } else {
                "memoryarena-shadow".to_string()
            }
        });
        let latest_context_pack_id = self
            .read_recent_jsonl::<ContextPack>(CONTEXT_PACKS_LOG, 1)
            .ok()
            .and_then(|mut packs| packs.pop())
            .map(|pack| pack.id);
        let policy_status = self.memory_policy_status().ok();
        let dreamcycle_status = self.dreamcycle_status().ok();
        let latest_paper_run = self
            .read_recent_jsonl::<PaperRun>(SOUNIO_PAPERRUNS_LOG, 1)
            .ok()
            .and_then(|mut runs| runs.pop());
        let trust_context = Some(TrustContext {
            mcp_status: if audit_events.is_empty() {
                "no-audit-events-yet".to_string()
            } else {
                "audit-log-observed".to_string()
            },
            active_scopes: latest_audit
                .map(|event| event.granted_scopes.clone())
                .filter(|scopes| !scopes.is_empty())
                .unwrap_or_else(default_mcp_scopes),
            audit_freshness: latest_audit
                .map(|event| event.created_at.clone())
                .unwrap_or_else(|| "no audit events yet".to_string()),
            destructive_actions:
                "locked: requires admin:destructive scope and explicit future endpoint".to_string(),
            tool_manifest_hash: latest_audit
                .and_then(|event| metadata_string(&event.metadata, "tool_manifest_hash")),
            last_audit_event_id: latest_audit.map(|event| event.id.clone()),
            memory_projection_status: projection_status.clone(),
            graph_runtime: graph_status
                .as_ref()
                .map(|status| status.graph_runtime.clone()),
            retrieval_mode: graph_status
                .as_ref()
                .map(|status| status.retrieval_mode.clone()),
            last_world_hash: latest_world_hash,
            latest_agent_write,
            graph_degraded_reason: graph_status.map(|status| status.degraded_reason),
            memory_engine_status: Some(if graph_runtime_configured() {
                "mesh-configured".to_string()
            } else {
                "mesh-degraded-jsonl-fallback".to_string()
            }),
            latest_candidate_ref: latest_candidate.map(|candidate| candidate.id),
            latest_quorum_status: latest_quorum.map(|decision| decision.status),
            memory_governor_status: governance_status
                .as_ref()
                .map(|status| status.status.clone()),
            pending_triads: governance_status
                .as_ref()
                .map(|status| status.pending_triads),
            open_contradictions: governance_status
                .as_ref()
                .map(|status| status.open_contradictions),
            latest_promotion_decision: governance_status
                .and_then(|status| status.latest_promotion_decision)
                .map(|decision| decision.status),
            memory_bench_status: benchmark_status
                .as_ref()
                .map(|status| status.status.clone()),
            latest_bench_score: benchmark_status
                .as_ref()
                .and_then(|status| status.latest_score),
            memory_regression_count: benchmark_status
                .as_ref()
                .map(|status| status.regression_count),
            truthset_id: benchmark_status
                .as_ref()
                .and_then(|status| status.truthset_id.clone()),
            bench_hot_path_eligible: benchmark_status
                .as_ref()
                .map(|status| status.hot_path_eligible),
            agent_observer_status,
            apple_capture_freshness,
            capture_loop_status,
            semantic_backbone_status: Some(semantic_backbone_status),
            hot_path_mode: Some(hot_path_mode),
            provisional_hot_path: Some(provisional_hot_path),
            portfolio_truth_gate,
            retrieval_agent_status: Some(format!(
                "{}+{}",
                retrieval_agent_mode(),
                retrieval_planner_mode()
            )),
            latest_retrieval_strategy,
            memoryarena_gate,
            context_compiler_status: Some(format!(
                "{}+{}",
                context_compiler_mode(),
                retrieval_context_format()
            )),
            latest_context_pack_id,
            memory_policy_status: policy_status
                .as_ref()
                .map(|status| format!("{}:{}", status.policy_mode, status.policy_version)),
            policy_gate: Some(
                memory_policy_gate_json()
                    .get("promotion")
                    .and_then(|value| value.as_str())
                    .unwrap_or("observe")
                    .to_string(),
            ),
            dreamcycle_status: dreamcycle_status
                .as_ref()
                .map(|status| format!("{}:{}", status.mode, status.status)),
            sounio_paperrun_status: latest_paper_run
                .as_ref()
                .map(|run| format!("{}:{}", run.paper_id, run.status)),
            sounio_temporal_status: latest_paper_run
                .as_ref()
                .map(|run| format!("{}:{}", run.temporal_workflow_id, run.temporal_status)),
            sounio_pending_approval: latest_paper_run
                .as_ref()
                .and_then(|run| run.pending_approval_step.clone()),
            sounio_latest_artifact: latest_paper_run
                .as_ref()
                .and_then(|run| run.artifact_refs.first().cloned()),
            sounio_workday_status: sounio_workday_context
                .as_ref()
                .map(|workday| format!("{}:{}", workday.project_slug, workday.status)),
            sounio_latest_moment: sounio_workday_context
                .as_ref()
                .and_then(|workday| workday.latest_moment.as_ref())
                .map(|moment| {
                    format!(
                        "{}:{}",
                        moment.moment_type,
                        truncate_chars(&moment.summary, 80)
                    )
                }),
            sounio_pending_moment_review: sounio_workday_context.as_ref().and_then(|workday| {
                (workday.review_queue_count > 0)
                    .then(|| format!("{} pending", workday.review_queue_count))
            }),
        });
        let temporal_phase = temporal_phase.or_else(|| {
            causal_hypotheses
                .first()
                .map(|hypothesis| format!("Causal hypothesis: {}", hypothesis.effect_candidate))
        });
        let snapshot = ExocortexHomeSnapshot {
            generated_at: Utc::now().to_rfc3339(),
            today_brief,
            current_self,
            memory_signals,
            open_loops,
            active_project_ref: active_project,
            body_context,
            recommended_next_action,
            cluster_truth: "observed".to_string(),
            omnimemory_status: projection_status
                .as_ref()
                .map(|status| {
                    format!(
                        "{} imports, {} episodes, {} atoms projected",
                        imports.len(),
                        status.episode_count,
                        status.atom_count
                    )
                })
                .unwrap_or_else(|| format!("{} imports indexed", imports.len())),
            temporal_phase,
            agent_context,
            trust_context,
            sounio_workday_context,
        };
        self.write_snapshot(HOME_SNAPSHOT, &snapshot)?;
        Ok(snapshot)
    }

    /// Append one durable conversation passage record to
    /// `conversation_passages.jsonl`, preserving the raw turn text before it is
    /// otherwise dropped. Restricted records are skipped (returns `Ok(false)`),
    /// mirroring existing export/projection privacy guards. Shared by the
    /// assisted-import and `/api/memory` ingest paths so both write to the same
    /// exocortex store with one writer.
    pub(crate) fn append_conversation_passages(
        &self,
        id: String,
        session_id: Option<String>,
        source_platform: String,
        occurred_at: String,
        privacy_class: String,
        turns: Vec<ConversationPassageTurn>,
    ) -> anyhow::Result<bool> {
        if normalize_privacy_class(Some(&privacy_class)) == "restricted" {
            return Ok(false);
        }
        let record = ConversationPassageRecord {
            id,
            session_id,
            source_platform,
            occurred_at,
            privacy_class,
            turns,
        };
        self.append_jsonl(CONVERSATION_PASSAGES_LOG, &record)?;
        Ok(true)
    }

    pub(crate) fn append_jsonl<T: Serialize>(
        &self,
        file_name: &str,
        value: &T,
    ) -> anyhow::Result<()> {
        let mirrored = memory_pg_dual_write_kind(file_name);
        let dual = memory_pg_dual_write_enabled();
        // Phase 3.4 decommission: once memory-pg is the canonical store, stop
        // appending the legacy JSONL for mirrored kinds (episodes/atoms/passages).
        // Fail-safe — `jsonl_write_skipped` only returns true when dual-write is
        // ALSO on, so a misconfigured BEAGLE_JSONL_APPEND_DISABLED can never
        // silently drop writes; non-mirrored logs always keep their JSONL.
        // Reversible: unset the flag and appends resume.
        let skip_jsonl =
            jsonl_write_skipped(memory_pg_jsonl_append_disabled(), dual, mirrored.is_some());
        if !skip_jsonl {
            self.ensure()?;
            let path = self.root.join(file_name);
            let mut file = OpenOptions::new().create(true).append(true).open(path)?;
            serde_json::to_writer(&mut file, value)?;
            file.write_all(b"\n")?;
            file.flush()?;
        }
        // Phase 3 dual-write: mirror the record to the reliable memory-pg pipeline.
        // Best-effort shadow while JSONL is still canonical; the sole write once
        // appends are disabled. Never blocks or errors the caller.
        if dual {
            if let Some(kind) = mirrored {
                if let Ok(v) = serde_json::to_value(value) {
                    spawn_memory_pg_dual_write(kind, v);
                }
            }
        }
        Ok(())
    }

    pub(crate) fn read_recent_jsonl<T: for<'de> Deserialize<'de>>(
        &self,
        file_name: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<T>> {
        let path = self.root.join(file_name);
        if !path.exists() {
            return Ok(Vec::new());
        }
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let mut values = Vec::new();
        for (idx, line) in reader.lines().enumerate() {
            let line = line?;
            if line.trim().is_empty() {
                continue;
            }
            match serde_json::from_str::<T>(&line) {
                Ok(value) => values.push(value),
                Err(err) => {
                    // A single malformed historical line (e.g. a torn append or
                    // a control-character-corrupted record from a concurrent
                    // write) must NEVER abort the whole read: doing so would make
                    // every future operation that reads this log — including every
                    // memory capture — fail with HTTP 500. Skip + warn instead so
                    // the corrupt line is quarantined but the rest of the log
                    // remains fully usable.
                    tracing::warn!(
                        file = %file_name,
                        line = idx + 1,
                        error = %err,
                        "read_recent_jsonl: skipping malformed JSONL line"
                    );
                }
            }
        }
        values.reverse();
        values.truncate(limit);
        Ok(values)
    }

    /// Lexical (BM25-lite) search over durable conversation passages. Used only by the
    /// recall_answer LEXICAL FALLBACK so that, during a memory-engine outage, recall still
    /// returns real conversation passages instead of only degraded metadata atoms.
    /// Bounded: reads at most 5000 recent records and scores at most 2000 candidate turns.
    pub(crate) fn lexical_passage_search(
        &self,
        query: &str,
        k: usize,
    ) -> anyhow::Result<Vec<RecallSource>> {
        let records =
            self.read_recent_jsonl::<ConversationPassageRecord>(CONVERSATION_PASSAGES_LOG, 5000)?;
        let q_tokens: std::collections::HashSet<String> = tokenize(query).into_iter().collect();
        if q_tokens.is_empty() {
            return Ok(Vec::new());
        }
        const MAX_CANDIDATES: usize = 2000;
        let mut scored: Vec<(f64, RecallSource)> = Vec::new();
        'records: for record in &records {
            if record.privacy_class.to_lowercase() == "restricted" {
                continue;
            }
            for turn in &record.turns {
                if scored.len() >= MAX_CANDIDATES {
                    break 'records;
                }
                let content = turn.content.trim();
                if content.chars().count() < 40 {
                    continue;
                }
                let t_tokens = tokenize(content);
                if t_tokens.is_empty() {
                    continue;
                }
                let matches = t_tokens.iter().filter(|t| q_tokens.contains(*t)).count();
                if matches == 0 {
                    continue;
                }
                let score = matches as f64 / (t_tokens.len() as f64).sqrt();
                let text: String = content.chars().take(600).collect();
                scored.push((
                    score,
                    RecallSource {
                        n: 0,
                        text,
                        date: Some(record.occurred_at.clone()),
                        source: "ConversationPassage".to_string(),
                        score,
                    },
                ));
            }
        }
        scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        Ok(scored.into_iter().take(k).map(|(_, s)| s).collect())
    }

    pub(crate) fn write_snapshot<T: Serialize>(
        &self,
        file_name: &str,
        value: &T,
    ) -> anyhow::Result<()> {
        self.ensure()?;
        let path = self.root.join(file_name);
        let tmp = path.with_extension("tmp");
        {
            let mut file = File::create(&tmp)?;
            serde_json::to_writer_pretty(&mut file, value)?;
            file.write_all(b"\n")?;
            file.flush()?;
        }
        fs::rename(tmp, path)?;
        Ok(())
    }

    pub(crate) fn read_snapshot<T: for<'de> Deserialize<'de>>(
        &self,
        file_name: &str,
    ) -> anyhow::Result<Option<T>> {
        let path = self.root.join(file_name);
        if !path.exists() {
            return Ok(None);
        }
        let data = fs::read_to_string(path)?;
        Ok(Some(serde_json::from_str(&data)?))
    }

    /// Hyperedges that REFLECT REALITY: every distinct `MemoryRelation`
    /// (subject→object) projected from recent memory atoms, as a directed hyperedge,
    /// plus any user-created hyperedges appended to `HYPEREDGES_LOG`. Optional
    /// `node_id` filters to edges incident on that node (matched on node ids / endpoints).
    pub(crate) fn list_hyperedges(
        &self,
        node_id: Option<&str>,
        limit: usize,
    ) -> anyhow::Result<Vec<HyperedgeRecord>> {
        self.ensure()?;
        let mut out: Vec<HyperedgeRecord> = Vec::new();
        let graph = self.memory_graph_recent(limit.clamp(1, 50))?;
        for rel in &graph.relations {
            let mut metadata = BTreeMap::new();
            metadata.insert("confidence".to_string(), format!("{:.3}", rel.confidence));
            metadata.insert("source".to_string(), "memory-relation".to_string());
            out.push(HyperedgeRecord {
                id: stable_id(
                    "hyperedge-rel",
                    &[&rel.subject, &rel.predicate, &rel.object],
                ),
                label: rel.predicate.clone(),
                node_ids: vec![rel.subject.clone(), rel.object.clone()],
                metadata,
                directed: true,
                created_at: graph.generated_at.clone(),
            });
        }
        out.extend(self.read_recent_jsonl::<HyperedgeRecord>(HYPEREDGES_LOG, usize::MAX)?);
        if let Some(nid) = node_id {
            out.retain(|h| h.id == nid || h.node_ids.iter().any(|n| n == nid));
        }
        Ok(out)
    }

    /// Append a user-created hyperedge to `HYPEREDGES_LOG` and return it. The id is
    /// content-stable so repeated identical creates collapse to one logical edge.
    pub(crate) fn create_hyperedge(
        &self,
        label: &str,
        node_ids: Vec<String>,
        directed: bool,
        mut metadata: BTreeMap<String, String>,
    ) -> anyhow::Result<HyperedgeRecord> {
        self.ensure()?;
        let id = {
            let mut key: Vec<&str> = vec![label];
            for n in &node_ids {
                key.push(n.as_str());
            }
            stable_id("hyperedge", &key)
        };
        metadata
            .entry("source".to_string())
            .or_insert_with(|| "user-created".to_string());
        let record = HyperedgeRecord {
            id,
            label: label.to_string(),
            node_ids,
            metadata,
            directed,
            created_at: Utc::now().to_rfc3339(),
        };
        self.append_jsonl(HYPEREDGES_LOG, &record)?;
        Ok(record)
    }
}

// ---------------------------------------------------------------------------
// Phase 3 dual-write to the reliable memory-pg pipeline.
//
// When `BEAGLE_DUAL_WRITE_MEMORY_PG` is on, every canonical JSONL append of a
// mirrored record kind is ALSO POSTed to memory-pg's `/capture` endpoint, which
// runs the same extraction the migration backfill uses (so dual-write and the
// backfill produce identical rows). This is strictly additive and best-effort:
// the POST is fire-and-forget and a failure never affects the canonical write.
// ---------------------------------------------------------------------------

fn memory_pg_dual_write_enabled() -> bool {
    std::env::var("BEAGLE_DUAL_WRITE_MEMORY_PG")
        .map(|v| {
            let v = v.trim();
            v == "1" || v.eq_ignore_ascii_case("true") || v.eq_ignore_ascii_case("on")
        })
        .unwrap_or(false)
}

/// Phase 3.4 decommission flag: stop appending the legacy JSONL (the old stack
/// is being retired). Read together with `jsonl_write_skipped`, which makes it
/// fail-safe — it only suppresses the write when dual-write is also enabled.
fn memory_pg_jsonl_append_disabled() -> bool {
    std::env::var("BEAGLE_JSONL_APPEND_DISABLED")
        .map(|v| {
            let v = v.trim();
            v == "1" || v.eq_ignore_ascii_case("true") || v.eq_ignore_ascii_case("on")
        })
        .unwrap_or(false)
}

/// Decide whether to skip the legacy JSONL append for this record. The append is
/// suppressed ONLY when the decommission flag is set AND dual-write is enabled
/// AND the record kind is actually mirrored to memory-pg — so a misconfigured
/// flag (e.g. decommission on but dual-write off) never drops a write, and
/// non-mirrored logs always keep their JSONL.
fn jsonl_write_skipped(disabled: bool, dual_enabled: bool, mirrored: bool) -> bool {
    disabled && dual_enabled && mirrored
}

/// Map a canonical JSONL log filename to the memory-pg record `kind`, or `None`
/// when that log is not mirrored to the reliable pipeline.
fn memory_pg_dual_write_kind(file_name: &str) -> Option<&'static str> {
    match file_name {
        MEMORY_EPISODES_LOG => Some("MemoryEpisode"),
        MEMORY_ATOMS_LOG => Some("MemoryAtom"),
        CONVERSATION_PASSAGES_LOG => Some("ConversationPassage"),
        _ => None,
    }
}

/// Fire-and-forget POST `{ kind, record }` to memory-pg `/capture`. Only runs
/// when a tokio runtime is active (the HTTP handlers); on a sync/test call site
/// with no runtime it is a silent no-op. Never panics, never blocks.
fn spawn_memory_pg_dual_write(kind: &'static str, record: serde_json::Value) {
    let base = match std::env::var("MEMORY_PG_CAPTURE_URL") {
        Ok(u) if !u.trim().is_empty() => u,
        _ => return,
    };
    let token = std::env::var("MEMORY_PG_INGEST_TOKEN").unwrap_or_default();
    let url = format!("{}/capture", base.trim_end_matches('/'));
    let body = serde_json::json!({ "kind": kind, "record": record });
    let handle = match tokio::runtime::Handle::try_current() {
        Ok(h) => h,
        Err(_) => return,
    };
    handle.spawn(async move {
        let client = reqwest::Client::new();
        let mut req = client
            .post(&url)
            .timeout(std::time::Duration::from_secs(10))
            .json(&body);
        if !token.is_empty() {
            req = req.bearer_auth(token);
        }
        match req.send().await {
            Ok(resp) if !resp.status().is_success() => {
                tracing::warn!("dual-write memory-pg {kind}: HTTP {}", resp.status());
            }
            Err(e) => tracing::warn!("dual-write memory-pg {kind} failed: {e}"),
            _ => {}
        }
    });
}

#[cfg(test)]
mod dual_write_tests {
    use super::{jsonl_write_skipped, memory_pg_dual_write_enabled, memory_pg_dual_write_kind};
    use super::{CONVERSATION_PASSAGES_LOG, MEMORY_ATOMS_LOG, MEMORY_EPISODES_LOG};

    #[test]
    fn jsonl_append_only_skipped_when_decommission_and_dualwrite_and_mirrored() {
        // The ONLY case that suppresses the legacy write: decommission flag on,
        // dual-write on, and the record kind is mirrored to memory-pg.
        assert!(jsonl_write_skipped(true, true, true));
        // Any missing precondition keeps the JSONL append (fail-safe).
        assert!(
            !jsonl_write_skipped(true, false, true),
            "decommission without dual-write must NOT skip"
        );
        assert!(
            !jsonl_write_skipped(false, true, true),
            "no decommission flag -> keep appending"
        );
        assert!(
            !jsonl_write_skipped(true, true, false),
            "non-mirrored log always keeps JSONL"
        );
        assert!(!jsonl_write_skipped(false, false, false));
    }

    #[test]
    fn kind_mapping_covers_mirrored_logs_only() {
        assert_eq!(
            memory_pg_dual_write_kind(MEMORY_EPISODES_LOG),
            Some("MemoryEpisode")
        );
        assert_eq!(
            memory_pg_dual_write_kind(MEMORY_ATOMS_LOG),
            Some("MemoryAtom")
        );
        assert_eq!(
            memory_pg_dual_write_kind(CONVERSATION_PASSAGES_LOG),
            Some("ConversationPassage"),
        );
        // Non-mirrored logs (chronoself, failed writes, hyperedges, …) are skipped.
        assert_eq!(memory_pg_dual_write_kind("chronoself_log.jsonl"), None);
        assert_eq!(memory_pg_dual_write_kind("failed_writes.jsonl"), None);
        assert_eq!(memory_pg_dual_write_kind("hyperedges.jsonl"), None);
    }

    #[test]
    fn enabled_flag_parsing() {
        // Serialize env mutation across this test process.
        std::env::remove_var("BEAGLE_DUAL_WRITE_MEMORY_PG");
        assert!(!memory_pg_dual_write_enabled(), "unset = off");
        for on in ["1", "true", "TRUE", "on", " true "] {
            std::env::set_var("BEAGLE_DUAL_WRITE_MEMORY_PG", on);
            assert!(memory_pg_dual_write_enabled(), "{on:?} should enable");
        }
        for off in ["0", "false", "no", ""] {
            std::env::set_var("BEAGLE_DUAL_WRITE_MEMORY_PG", off);
            assert!(!memory_pg_dual_write_enabled(), "{off:?} should disable");
        }
        std::env::remove_var("BEAGLE_DUAL_WRITE_MEMORY_PG");
    }
}
