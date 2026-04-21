use crate::{
    get_workstream_control_room_detail, resolve_registered_workstream, WorkstreamLastResultReference,
    WorkspaceLastSuccessfulTask, WorkspaceSessionState,
};
use crate::workspace_plane::{
    bootstrap_workspace_session, load_workspace_session, workspace_plane_dir, write_workspace_session,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{fs, io::Write, path::{Path, PathBuf}};

const TOOL_RETURN_PHASE: &str = "B18.2";
const TOOL_RETURN_LEDGER_FILE: &str = "tool_return_events.jsonl";

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct WorkstreamToolRepoRefs {
    #[serde(default)]
    pub branch: Option<String>,
    #[serde(default)]
    pub commit: Option<String>,
    #[serde(default)]
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct WorkstreamToolReturnPayload {
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub tool: String,
    pub action_type: String,
    pub summary: String,
    pub memory_text: String,
    #[serde(default)]
    pub handoff_patch: Option<String>,
    #[serde(default)]
    pub patch_ref: Option<String>,
    #[serde(default)]
    pub result_refs: Vec<String>,
    #[serde(default)]
    pub repo_refs: Option<WorkstreamToolRepoRefs>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamToolReturnResponse {
    pub status: String,
    pub phase: String,
    pub return_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub tool: String,
    pub action_type: String,
    pub governance_state: String,
    pub last_handoff: Option<String>,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
    pub handoff_updated: bool,
    pub memory_ingested: bool,
    pub memory_id: Option<String>,
    pub patch_ref: Option<String>,
    pub ledger_appended: bool,
    pub recorded_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamToolReturnLedgerEntry {
    pub phase: String,
    pub return_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub tool: String,
    pub action_type: String,
    pub summary: String,
    pub memory_id: Option<String>,
    pub patch_ref: Option<String>,
    pub result_refs: Vec<String>,
    pub repo_refs: Option<WorkstreamToolRepoRefs>,
    pub previous_handoff: Option<String>,
    pub updated_handoff: String,
    pub governance_state: String,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub recorded_at: DateTime<Utc>,
}

pub fn apply_workstream_tool_return(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    payload: &WorkstreamToolReturnPayload,
    memory_id: Option<String>,
) -> anyhow::Result<WorkstreamToolReturnResponse> {
    let workstream_id = trim_required(workstream_id, "workstream_id")?;
    let payload_workstream_id = trim_required(&payload.workstream_id, "payload.workstream_id")?;
    if payload_workstream_id != workstream_id {
        return Err(anyhow!(
            "payload workstream_id {} does not match route workstream_id {}",
            payload_workstream_id,
            workstream_id
        ));
    }

    let tool = normalize_tool(&payload.tool)?;
    let action_type = normalize_action_type(&payload.action_type)?;
    let summary = trim_required(&payload.summary, "summary")?;
    let memory_text = non_empty_string(&payload.memory_text).unwrap_or_else(|| summary.clone());
    let handoff_patch = sanitize_optional_text(payload.handoff_patch.as_deref());
    let patch_ref = sanitize_optional_text(payload.patch_ref.as_deref());
    let repo_refs = normalize_repo_refs(payload.repo_refs.clone());
    let result_refs = payload
        .result_refs
        .iter()
        .filter_map(|value| non_empty_string(value))
        .collect::<Vec<_>>();

    let mut session = resolve_mutable_workstream_session(data_dir, cfg, &workstream_id)?;
    if session.workstream_cutover_policy.workstream_name != workstream_id {
        return Err(anyhow!(
            "latest session {} is not bound to workstream {}",
            session.workspace_id,
            workstream_id
        ));
    }

    let payload_workspace_id = trim_required(&payload.workspace_id, "payload.workspace_id")?;
    if payload_workspace_id != session.workspace_id {
        return Err(anyhow!(
            "payload workspace_id {} does not match live workspace_id {}",
            payload_workspace_id,
            session.workspace_id
        ));
    }

    let payload_session_id = trim_required(&payload.session_id, "payload.session_id")?;
    if payload_session_id != session.session_id {
        return Err(anyhow!(
            "payload session_id {} does not match live session_id {}",
            payload_session_id,
            session.session_id
        ));
    }

    let recorded_at = Utc::now();
    let return_id = format!(
        "tool-return-{}-{}-{}",
        workstream_id,
        tool,
        recorded_at.format("%Y%m%d%H%M%S")
    );
    let previous_handoff = session.last_handoff.clone();
    let updated_handoff = build_handoff_line(
        &session,
        &tool,
        &action_type,
        &summary,
        handoff_patch.as_deref(),
        patch_ref.as_deref(),
        &result_refs,
        repo_refs.as_ref(),
    );

    session.updated_at = recorded_at;
    session.last_handoff = Some(updated_handoff.clone());
    write_workspace_session(data_dir, &session)?;

    let last_result_reference = last_result_reference_from_session(&session);
    append_tool_return_ledger(
        data_dir,
        &WorkstreamToolReturnLedgerEntry {
            phase: TOOL_RETURN_PHASE.to_string(),
            return_id: return_id.clone(),
            workstream_id: workstream_id.clone(),
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            tool: tool.clone(),
            action_type: action_type.clone(),
            summary: memory_text,
            memory_id: memory_id.clone(),
            patch_ref: patch_ref.clone(),
            result_refs,
            repo_refs,
            previous_handoff,
            updated_handoff,
            governance_state: session.workstream_cutover_policy.promotion_state.state.clone(),
            active_dev_plane: session.active_dev_plane.clone(),
            fallback_active: session.fallback_active,
            recorded_at,
        },
    )?;

    Ok(WorkstreamToolReturnResponse {
        status: "ok".to_string(),
        phase: TOOL_RETURN_PHASE.to_string(),
        return_id,
        workstream_id,
        workspace_id: session.workspace_id.clone(),
        session_id: session.session_id.clone(),
        tool,
        action_type,
        governance_state: session.workstream_cutover_policy.promotion_state.state.clone(),
        last_handoff: session.last_handoff.clone(),
        last_successful_task: session.last_successful_task.clone(),
        last_result_reference,
        handoff_updated: true,
        memory_ingested: memory_id.is_some(),
        memory_id,
        patch_ref,
        ledger_appended: true,
        recorded_at,
    })
}

pub fn tool_return_ledger_path(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join(TOOL_RETURN_LEDGER_FILE)
}

fn append_tool_return_ledger(
    data_dir: &Path,
    entry: &WorkstreamToolReturnLedgerEntry,
) -> anyhow::Result<()> {
    let path = tool_return_ledger_path(data_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create tool return ledger dir {}",
                parent.display()
            )
        })?;
    }

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .with_context(|| format!("failed to open tool return ledger {}", path.display()))?;
    let line = serde_json::to_string(entry)?;
    writeln!(file, "{line}")
        .with_context(|| format!("failed to append tool return ledger {}", path.display()))
}

fn resolve_mutable_workstream_session(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> anyhow::Result<WorkspaceSessionState> {
    let detail = get_workstream_control_room_detail(data_dir, cfg, workstream_id)?;
    let workspace_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.workspace_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.registry_entry.cutover_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_workspace_id))
        .or_else(|| {
            (cfg.workspace.cutover_workstream == workstream_id)
                .then(|| cfg.workspace.canonical_workspace_id.clone())
        });

    let Some(workspace_id) = workspace_id else {
        resolve_registered_workstream(workstream_id)?;
        return Err(anyhow!("no live workspace is recorded for workstream {}", workstream_id));
    };

    if let Some(session) = load_workspace_session(data_dir, cfg, &workspace_id)? {
        return Ok(session);
    }

    if cfg.workspace.cutover_workstream != workstream_id {
        return Err(anyhow!(
            "no live session recorded for workstream {} and it is not the canonical cutover workstream",
            workstream_id
        ));
    }

    bootstrap_workspace_session(
        data_dir,
        cfg,
        Some(&cfg.workspace.canonical_workspace_id),
        None,
    )?;

    load_workspace_session(data_dir, cfg, &cfg.workspace.canonical_workspace_id)?
        .ok_or_else(|| {
            anyhow!(
                "failed to resolve mutable workstream session for {} after bootstrap",
                workstream_id
            )
        })
}

fn build_handoff_line(
    session: &WorkspaceSessionState,
    tool: &str,
    action_type: &str,
    summary: &str,
    handoff_patch: Option<&str>,
    patch_ref: Option<&str>,
    result_refs: &[String],
    repo_refs: Option<&WorkstreamToolRepoRefs>,
) -> String {
    let repo_branch = repo_refs
        .and_then(|refs| refs.branch.as_deref())
        .unwrap_or(&session.canonical_branch);
    let repo_commit = repo_refs
        .and_then(|refs| refs.commit.as_deref())
        .unwrap_or("none");
    let path_list = repo_refs
        .map(|refs| {
            if refs.paths.is_empty() {
                "none".to_string()
            } else {
                refs.paths.join(",")
            }
        })
        .unwrap_or_else(|| "none".to_string());
    let result_list = if result_refs.is_empty() {
        "none".to_string()
    } else {
        result_refs.join(",")
    };

    format!(
        "workspace={} repo={} branch={} session={} tool return {} action {} summary={} repo_branch={} repo_commit={} repo_paths={} result_refs={} patch_ref={} candidate_handoff={} previous_handoff={}",
        session.workspace_id,
        session.canonical_repo,
        session.canonical_branch,
        session.session_id,
        tool,
        action_type,
        compact_text(summary),
        repo_branch,
        repo_commit,
        path_list,
        result_list,
        patch_ref.map(compact_text).unwrap_or_else(|| "none".to_string()),
        handoff_patch.map(compact_text).unwrap_or_else(|| "none".to_string()),
        session
            .last_handoff
            .as_deref()
            .map(compact_text)
            .unwrap_or_else(|| "none".to_string())
    )
}

fn last_result_reference_from_session(
    session: &WorkspaceSessionState,
) -> Option<WorkstreamLastResultReference> {
    session
        .last_published_result_job_id
        .map(|job_id| WorkstreamLastResultReference {
            job_id,
            run_label: session.last_published_result_run_label.clone(),
            profile_id: session.last_published_result_profile_id.clone(),
            node_list: session.last_published_result_node_list.clone(),
            manifest_key: session.last_published_manifest_key.clone(),
        })
}

fn normalize_tool(value: &str) -> anyhow::Result<String> {
    let normalized = trim_required(value, "tool")?.to_ascii_lowercase();
    match normalized.as_str() {
        "cursor" | "claude-code" | "claude_code" | "claude" | "codex" => Ok(match normalized.as_str() {
            "claude" | "claude_code" => "claude-code".to_string(),
            _ => normalized,
        }),
        _ => Err(anyhow!(
            "unsupported tool {}; expected one of cursor, claude-code, codex",
            value
        )),
    }
}

fn normalize_action_type(value: &str) -> anyhow::Result<String> {
    let normalized = trim_required(value, "action_type")?.to_ascii_lowercase();
    match normalized.as_str() {
        "note" | "implementation" | "analysis" | "handoff_update" => Ok(normalized),
        _ => Err(anyhow!(
            "unsupported action_type {}; expected one of note, implementation, analysis, handoff_update",
            value
        )),
    }
}

fn normalize_repo_refs(repo_refs: Option<WorkstreamToolRepoRefs>) -> Option<WorkstreamToolRepoRefs> {
    repo_refs.and_then(|refs| {
        let branch = refs.branch.and_then(|value| non_empty_string(&value));
        let commit = refs.commit.and_then(|value| non_empty_string(&value));
        let paths = refs
            .paths
            .into_iter()
            .filter_map(|value| non_empty_string(&value))
            .collect::<Vec<_>>();

        if branch.is_none() && commit.is_none() && paths.is_empty() {
            None
        } else {
            Some(WorkstreamToolRepoRefs { branch, commit, paths })
        }
    })
}

fn sanitize_optional_text(value: Option<&str>) -> Option<String> {
    value.and_then(non_empty_string)
}

fn trim_required(value: &str, field: &str) -> anyhow::Result<String> {
    non_empty_string(value).ok_or_else(|| anyhow!("{field} is required"))
}

fn non_empty_string(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn compact_text(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace_plane::{write_workspace_session, WorkspaceSessionState};
    use beagle_config::{
        AdvancedModulesConfig, ConsumerAccessConfig, GraphConfig, HermesConfig, LlmConfig,
        ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::Utc;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    const CANONICAL_WORKSTREAM_ID: &str = "beagle-darwin-hpc-governance";

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        fn new(label: &str) -> Self {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "beagle-darwin-tool-return-{label}-{}-{unique}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn test_config(data_dir: &Path) -> BeagleConfig {
        BeagleConfig {
            profile: "cluster".to_string(),
            safe_mode: true,
            api_token: Some("test-token".to_string()),
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: data_dir.display().to_string(),
            },
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace: WorkspacePlaneConfig {
                canonical_workspace_id: "test-tool-return".to_string(),
                canonical_repo: "agourakis82/beagle".to_string(),
                canonical_branch: "feat/darwin-hpc-governance".to_string(),
                canonical_track: "darwin-hpc".to_string(),
                operator_name: Some("test-operator".to_string()),
                default_dev_plane: "beagle-cluster".to_string(),
                vm_fallback_role: "fallback-only".to_string(),
                promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
                cutover_workstream: CANONICAL_WORKSTREAM_ID.to_string(),
                cutover_state: "canonical".to_string(),
                cutover_last_transition: "resume".to_string(),
                cutover_branch_lineage: "feat/darwin-hpc-governance".to_string(),
                cutover_default_profile: "cpu-short-v1".to_string(),
                cutover_batch_profile: "cpu-batch-v1".to_string(),
                cutover_advanced_profile: "gpu-single-v1".to_string(),
                cutover_result_publication: "object-backed".to_string(),
                cutover_result_retrieval: "object-backed".to_string(),
                cutover_result_retention_policy: "active".to_string(),
                cutover_operator_consumer_policy: "full".to_string(),
                cutover_research_consumer_policy: "bounded".to_string(),
                cutover_recovery_required: true,
                cutover_handoff_required: true,
                bootstrap_enabled: true,
                habitat: WorkspaceHabitatConfig::default(),
            },
            consumers: ConsumerAccessConfig::default(),
            advanced: AdvancedModulesConfig::default(),
            observer: ObserverThresholds::default(),
        }
    }

    fn seeded_session(cfg: &BeagleConfig, workspace_id: &str, session_id: &str) -> WorkspaceSessionState {
        let mut session = WorkspaceSessionState::new(
            cfg,
            workspace_id.to_string(),
            Some(session_id.to_string()),
        );
        session.updated_at = Utc::now();
        session.last_handoff = Some("seed handoff before tool return".to_string());
        session.last_published_result_job_id = Some(31);
        session.last_published_result_run_label = Some("b181-seed".to_string());
        session.last_published_result_profile_id = Some("cpu-batch-v1".to_string());
        session.last_published_result_node_list = Some("t560-proxmox".to_string());
        session.last_published_manifest_key = Some("results/31/manifest.json".to_string());
        session
    }

    #[test]
    fn apply_tool_return_updates_handoff_and_appends_ledger() {
        let dir = TestDir::new("updates-handoff");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, "test-tool-return", "ws-tool-return");
        write_workspace_session(dir.path(), &session).unwrap();

        let payload = WorkstreamToolReturnPayload {
            workstream_id: CANONICAL_WORKSTREAM_ID.to_string(),
            workspace_id: "test-tool-return".to_string(),
            session_id: "ws-tool-return".to_string(),
            tool: "codex".to_string(),
            action_type: "implementation".to_string(),
            summary: "Implemented bounded writeback".to_string(),
            memory_text: "Implemented bounded writeback and prepared handoff".to_string(),
            handoff_patch: Some("resume with the updated writeback path".to_string()),
            patch_ref: None,
            result_refs: vec!["result:31".to_string()],
            repo_refs: Some(WorkstreamToolRepoRefs {
                branch: Some("feat/darwin-hpc-governance".to_string()),
                commit: Some("abc123".to_string()),
                paths: vec!["crates/beagle-darwin/src/workstream_tool_return.rs".to_string()],
            }),
        };

        let response =
            apply_workstream_tool_return(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID, &payload, Some("memory-1".to_string()))
                .unwrap();

        assert_eq!(response.status, "ok");
        assert_eq!(response.tool, "codex");
        assert_eq!(response.action_type, "implementation");
        assert_eq!(response.workspace_id, "test-tool-return");
        assert_eq!(response.session_id, "ws-tool-return");
        assert!(response.handoff_updated);
        assert!(response.memory_ingested);
        assert_eq!(response.memory_id.as_deref(), Some("memory-1"));
        assert!(response
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("tool return codex action implementation"));

        let persisted = load_workspace_session(dir.path(), &cfg, "test-tool-return")
            .unwrap()
            .unwrap();
        assert!(persisted
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("candidate_handoff=resume with the updated writeback path"));

        let ledger = fs::read_to_string(tool_return_ledger_path(dir.path())).unwrap();
        assert!(ledger.contains("\"tool\":\"codex\""));
        assert!(ledger.contains("\"action_type\":\"implementation\""));
        assert!(ledger.contains("\"memory_id\":\"memory-1\""));
        assert!(ledger.contains("\"result_refs\":[\"result:31\"]"));
    }

    #[test]
    fn apply_tool_return_rejects_identity_mismatch() {
        let dir = TestDir::new("identity-mismatch");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, "test-tool-return", "ws-tool-return");
        write_workspace_session(dir.path(), &session).unwrap();

        let payload = WorkstreamToolReturnPayload {
            workstream_id: CANONICAL_WORKSTREAM_ID.to_string(),
            workspace_id: "different-workspace".to_string(),
            session_id: "ws-tool-return".to_string(),
            tool: "cursor".to_string(),
            action_type: "note".to_string(),
            summary: "Session mismatch".to_string(),
            memory_text: "Session mismatch".to_string(),
            handoff_patch: None,
            patch_ref: None,
            result_refs: Vec::new(),
            repo_refs: None,
        };

        let error =
            apply_workstream_tool_return(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID, &payload, None)
                .unwrap_err();

        assert!(error
            .to_string()
            .contains("payload workspace_id different-workspace does not match live workspace_id"));
    }

    #[test]
    fn apply_tool_return_supports_ordered_multi_step_session_loop() {
        let dir = TestDir::new("multi-step");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, "test-tool-return", "ws-tool-return");
        write_workspace_session(dir.path(), &session).unwrap();

        let steps = [
            (
                "codex",
                "implementation",
                "Step 1 implemented the bounded writeback path",
                "resume from the implementation step",
                "memory-step-1",
                "crates/beagle-darwin/src/workstream_tool_return.rs",
            ),
            (
                "claude-code",
                "analysis",
                "Step 2 analyzed the writeback sequence",
                "review the analysis before final note",
                "memory-step-2",
                "apps/beagle-monorepo/src/http_darwin_hpc.rs",
            ),
            (
                "cursor",
                "note",
                "Step 3 finalized the session note",
                "final handoff should preserve the ordered sequence",
                "memory-step-3",
                "docs/darwin/hpc/B183_MULTI_STEP_TOOL_SESSION_LOOP.md",
            ),
        ];

        for (index, (tool, action_type, summary, handoff_patch, memory_id, path)) in
            steps.iter().enumerate()
        {
            let payload = WorkstreamToolReturnPayload {
                workstream_id: CANONICAL_WORKSTREAM_ID.to_string(),
                workspace_id: "test-tool-return".to_string(),
                session_id: "ws-tool-return".to_string(),
                tool: (*tool).to_string(),
                action_type: (*action_type).to_string(),
                summary: (*summary).to_string(),
                memory_text: format!(
                    "multi-step tool session loop step {} for {}",
                    index + 1,
                    tool
                ),
                handoff_patch: Some((*handoff_patch).to_string()),
                patch_ref: None,
                result_refs: vec!["result:31".to_string()],
                repo_refs: Some(WorkstreamToolRepoRefs {
                    branch: Some("feat/darwin-hpc-governance".to_string()),
                    commit: Some(format!("step-{}", index + 1)),
                    paths: vec![(*path).to_string()],
                }),
            };

            let response = apply_workstream_tool_return(
                dir.path(),
                &cfg,
                CANONICAL_WORKSTREAM_ID,
                &payload,
                Some((*memory_id).to_string()),
            )
            .unwrap();

            assert_eq!(response.status, "ok");
            assert_eq!(response.workspace_id, "test-tool-return");
            assert_eq!(response.session_id, "ws-tool-return");
            assert_eq!(response.tool, *tool);
            assert_eq!(response.action_type, *action_type);
            assert_eq!(response.memory_id.as_deref(), Some(*memory_id));
            assert!(response
                .last_handoff
                .as_deref()
                .unwrap()
                .contains(summary));
        }

        let persisted = load_workspace_session(dir.path(), &cfg, "test-tool-return")
            .unwrap()
            .unwrap();
        let final_handoff = persisted.last_handoff.unwrap();
        assert!(final_handoff.contains("Step 3 finalized the session note"));
        assert!(final_handoff.contains("Step 2 analyzed the writeback sequence"));
        assert!(final_handoff.contains("Step 1 implemented the bounded writeback path"));

        let ledger_entries = fs::read_to_string(tool_return_ledger_path(dir.path()))
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str::<WorkstreamToolReturnLedgerEntry>(line).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(ledger_entries.len(), 3);
        assert_eq!(
            ledger_entries
                .iter()
                .map(|entry| entry.tool.as_str())
                .collect::<Vec<_>>(),
            vec!["codex", "claude-code", "cursor"]
        );
        assert_eq!(
            ledger_entries
                .iter()
                .map(|entry| entry.action_type.as_str())
                .collect::<Vec<_>>(),
            vec!["implementation", "analysis", "note"]
        );
        assert_eq!(
            ledger_entries[0].previous_handoff.as_deref(),
            Some("seed handoff before tool return")
        );
        assert!(ledger_entries[1]
            .previous_handoff
            .as_deref()
            .unwrap()
            .contains("Step 1 implemented the bounded writeback path"));
        assert!(ledger_entries[2]
            .previous_handoff
            .as_deref()
            .unwrap()
            .contains("Step 2 analyzed the writeback sequence"));
    }

    #[test]
    fn apply_tool_return_records_repo_native_patch_output() {
        let dir = TestDir::new("repo-native-patch");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, "test-tool-return", "ws-tool-return");
        write_workspace_session(dir.path(), &session).unwrap();

        let payload = WorkstreamToolReturnPayload {
            workstream_id: CANONICAL_WORKSTREAM_ID.to_string(),
            workspace_id: "test-tool-return".to_string(),
            session_id: "ws-tool-return".to_string(),
            tool: "cursor".to_string(),
            action_type: "note".to_string(),
            summary: "Recorded repo-aware session output".to_string(),
            memory_text: "Recorded repo-aware session output with bounded patch ref".to_string(),
            handoff_patch: Some("review the repo-aware patch output".to_string()),
            patch_ref: Some("artifact:darwin-hpc/b184/session-output.patch".to_string()),
            result_refs: vec!["result:31".to_string()],
            repo_refs: Some(WorkstreamToolRepoRefs {
                branch: Some("feat/darwin-hpc-governance".to_string()),
                commit: Some("base-sha".to_string()),
                paths: vec![
                    "docs/darwin/hpc/B184_REPO_AWARE_TOOL_SESSION_COMMIT_PATH.md".to_string(),
                    "docs/darwin/hpc/contracts/tool-session-commit-payload.json".to_string(),
                ],
            }),
        };

        let response = apply_workstream_tool_return(
            dir.path(),
            &cfg,
            CANONICAL_WORKSTREAM_ID,
            &payload,
            Some("memory-patch".to_string()),
        )
        .unwrap();

        assert_eq!(
            response.patch_ref.as_deref(),
            Some("artifact:darwin-hpc/b184/session-output.patch")
        );
        assert!(response
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("patch_ref=artifact:darwin-hpc/b184/session-output.patch"));

        let ledger_entries = fs::read_to_string(tool_return_ledger_path(dir.path()))
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str::<WorkstreamToolReturnLedgerEntry>(line).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(ledger_entries.len(), 1);
        assert_eq!(
            ledger_entries[0].patch_ref.as_deref(),
            Some("artifact:darwin-hpc/b184/session-output.patch")
        );
        assert!(ledger_entries[0]
            .updated_handoff
            .contains("patch_ref=artifact:darwin-hpc/b184/session-output.patch"));
    }
}
