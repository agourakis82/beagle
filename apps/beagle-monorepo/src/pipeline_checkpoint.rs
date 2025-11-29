//! Pipeline Checkpointing Integration
//!
//! Provides checkpointing support for BEAGLE pipelines, enabling:
//! - Fault tolerance (resume from last checkpoint on failure)
//! - Time travel (replay from any checkpoint)
//! - Human-in-the-loop (pause, edit, resume)

use beagle_checkpoint::{
    Checkpoint, CheckpointConfig, CheckpointMetadata, Checkpointer, CheckpointerExt,
    InMemoryCheckpointer, PendingWrite,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::{info, warn};

/// Pipeline execution state for checkpointing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineState {
    /// Current execution phase
    pub phase: PipelinePhase,

    /// Original question/query
    pub question: String,

    /// Run ID
    pub run_id: String,

    /// Darwin context (populated after Phase 1)
    pub darwin_context: Option<String>,

    /// Memory context (populated after Phase 0)
    pub memory_context: Option<String>,

    /// Serendipity discoveries
    pub serendipity_accidents: Vec<String>,
    pub serendipity_score: Option<f64>,

    /// Physiological state (populated after Phase 2)
    pub physio_state: Option<String>,
    pub hrv_level: Option<String>,

    /// Exocortex insights (populated after Phase 2.5)
    pub exocortex_insights: Option<String>,

    /// Generated draft (populated after Phase 3)
    pub draft: Option<String>,

    /// Output paths (populated after Phase 4)
    pub draft_md_path: Option<PathBuf>,
    pub draft_pdf_path: Option<PathBuf>,
    pub run_report_path: Option<PathBuf>,

    /// LLM statistics
    pub llm_stats: LlmStatsSnapshot,

    /// Errors encountered (non-fatal)
    pub warnings: Vec<String>,

    /// Timestamp of state creation
    pub created_at: DateTime<Utc>,

    /// Timestamp of last update
    pub updated_at: DateTime<Utc>,
}

impl PipelineState {
    /// Create initial state for a new pipeline run
    pub fn new(run_id: impl Into<String>, question: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            phase: PipelinePhase::Started,
            question: question.into(),
            run_id: run_id.into(),
            darwin_context: None,
            memory_context: None,
            serendipity_accidents: Vec::new(),
            serendipity_score: None,
            physio_state: None,
            hrv_level: None,
            exocortex_insights: None,
            draft: None,
            draft_md_path: None,
            draft_pdf_path: None,
            run_report_path: None,
            llm_stats: LlmStatsSnapshot::default(),
            warnings: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }

    /// Update the phase and timestamp
    pub fn advance_to(&mut self, phase: PipelinePhase) {
        self.phase = phase;
        self.updated_at = Utc::now();
    }

    /// Add a warning
    pub fn add_warning(&mut self, warning: impl Into<String>) {
        self.warnings.push(warning.into());
        self.updated_at = Utc::now();
    }

    /// Check if pipeline can be resumed from this state
    pub fn is_resumable(&self) -> bool {
        !matches!(
            self.phase,
            PipelinePhase::Completed | PipelinePhase::Failed(_)
        )
    }

    /// Get the next phase to execute
    pub fn next_phase(&self) -> Option<PipelinePhase> {
        match self.phase {
            PipelinePhase::Started => Some(PipelinePhase::MemoryRag),
            PipelinePhase::MemoryRag => Some(PipelinePhase::DarwinContext),
            PipelinePhase::DarwinContext => Some(PipelinePhase::Serendipity),
            PipelinePhase::Serendipity => Some(PipelinePhase::ObserverPhysio),
            PipelinePhase::ObserverPhysio => Some(PipelinePhase::Exocortex),
            PipelinePhase::Exocortex => Some(PipelinePhase::HermesSynthesis),
            PipelinePhase::HermesSynthesis => Some(PipelinePhase::ArtifactWriting),
            PipelinePhase::ArtifactWriting => Some(PipelinePhase::Completed),
            PipelinePhase::Completed => None,
            PipelinePhase::Failed(_) => None,
        }
    }

    /// Get step number for metadata
    pub fn step_number(&self) -> u64 {
        match self.phase {
            PipelinePhase::Started => 0,
            PipelinePhase::MemoryRag => 1,
            PipelinePhase::DarwinContext => 2,
            PipelinePhase::Serendipity => 3,
            PipelinePhase::ObserverPhysio => 4,
            PipelinePhase::Exocortex => 5,
            PipelinePhase::HermesSynthesis => 6,
            PipelinePhase::ArtifactWriting => 7,
            PipelinePhase::Completed => 8,
            PipelinePhase::Failed(_) => 99,
        }
    }
}

/// Pipeline execution phases
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PipelinePhase {
    /// Pipeline just started
    Started,
    /// Phase 0: Memory RAG injection
    MemoryRag,
    /// Phase 1: Darwin context (GraphRAG)
    DarwinContext,
    /// Phase 1.5: Serendipity discoveries
    Serendipity,
    /// Phase 2: Observer physiological state
    ObserverPhysio,
    /// Phase 2.5: Exocortex cognitive integration
    Exocortex,
    /// Phase 3: HERMES synthesis
    HermesSynthesis,
    /// Phase 4: Artifact writing (MD, PDF, report)
    ArtifactWriting,
    /// Pipeline completed successfully
    Completed,
    /// Pipeline failed with error
    Failed(String),
}

impl std::fmt::Display for PipelinePhase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PipelinePhase::Started => write!(f, "started"),
            PipelinePhase::MemoryRag => write!(f, "memory_rag"),
            PipelinePhase::DarwinContext => write!(f, "darwin_context"),
            PipelinePhase::Serendipity => write!(f, "serendipity"),
            PipelinePhase::ObserverPhysio => write!(f, "observer_physio"),
            PipelinePhase::Exocortex => write!(f, "exocortex"),
            PipelinePhase::HermesSynthesis => write!(f, "hermes_synthesis"),
            PipelinePhase::ArtifactWriting => write!(f, "artifact_writing"),
            PipelinePhase::Completed => write!(f, "completed"),
            PipelinePhase::Failed(e) => write!(f, "failed: {}", e),
        }
    }
}

/// Snapshot of LLM statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LlmStatsSnapshot {
    pub grok3_calls: u32,
    pub grok3_tokens_in: u32,
    pub grok3_tokens_out: u32,
    pub grok4_calls: u32,
    pub grok4_tokens_in: u32,
    pub grok4_tokens_out: u32,
}

impl LlmStatsSnapshot {
    /// Create from beagle_llm stats
    pub fn from_llm_stats(stats: &beagle_llm::stats::LlmCallsStats) -> Self {
        Self {
            grok3_calls: stats.grok3_calls,
            grok3_tokens_in: stats.grok3_tokens_in,
            grok3_tokens_out: stats.grok3_tokens_out,
            grok4_calls: stats.grok4_calls,
            grok4_tokens_in: stats.grok4_tokens_in,
            grok4_tokens_out: stats.grok4_tokens_out,
        }
    }

    /// Total calls
    pub fn total_calls(&self) -> u32 {
        self.grok3_calls + self.grok4_calls
    }

    /// Total tokens
    pub fn total_tokens(&self) -> u32 {
        self.grok3_tokens_in + self.grok3_tokens_out + self.grok4_tokens_in + self.grok4_tokens_out
    }
}

/// Pipeline checkpointer wrapper
pub struct PipelineCheckpointer {
    inner: InMemoryCheckpointer<PipelineState>,
}

impl PipelineCheckpointer {
    /// Create a new in-memory checkpointer
    pub fn new() -> Self {
        Self {
            inner: InMemoryCheckpointer::new(),
        }
    }

    /// Get checkpoint config for a run
    pub fn config_for_run(run_id: &str) -> CheckpointConfig {
        CheckpointConfig::new(run_id)
    }

    /// Save checkpoint after a phase completes
    pub async fn checkpoint(
        &self,
        state: &PipelineState,
    ) -> Result<uuid::Uuid, beagle_checkpoint::CheckpointError> {
        let config = Self::config_for_run(&state.run_id);
        let metadata = CheckpointMetadata::new(state.phase.to_string(), state.step_number());

        info!(
            run_id = %state.run_id,
            phase = %state.phase,
            step = state.step_number(),
            "Creating checkpoint"
        );

        self.inner.put(&config, state, metadata).await
    }

    /// Get latest checkpoint for a run
    pub async fn get_latest(
        &self,
        run_id: &str,
    ) -> Result<Option<Checkpoint<PipelineState>>, beagle_checkpoint::CheckpointError> {
        let config = Self::config_for_run(run_id);
        CheckpointerExt::get_latest(&self.inner, run_id).await
    }

    /// Get checkpoint history for a run
    pub async fn get_history(
        &self,
        run_id: &str,
    ) -> Result<Vec<Checkpoint<PipelineState>>, beagle_checkpoint::CheckpointError> {
        let config = Self::config_for_run(run_id);
        self.inner.get_history(&config).await
    }

    /// Check if a run has checkpoints
    pub async fn has_checkpoints(&self, run_id: &str) -> bool {
        CheckpointerExt::has_checkpoints(&self.inner, run_id)
            .await
            .unwrap_or(false)
    }

    /// Resume from the latest checkpoint
    pub async fn resume(
        &self,
        run_id: &str,
    ) -> Result<Option<PipelineState>, beagle_checkpoint::CheckpointError> {
        if let Some(checkpoint) = self.get_latest(run_id).await? {
            if checkpoint.state.is_resumable() {
                info!(
                    run_id = %run_id,
                    phase = %checkpoint.state.phase,
                    "Resuming pipeline from checkpoint"
                );
                Ok(Some(checkpoint.state))
            } else {
                warn!(
                    run_id = %run_id,
                    phase = %checkpoint.state.phase,
                    "Cannot resume from completed/failed state"
                );
                Ok(None)
            }
        } else {
            Ok(None)
        }
    }

    /// Replay from a specific checkpoint
    pub async fn replay_from(
        &self,
        run_id: &str,
        checkpoint_id: uuid::Uuid,
    ) -> Result<Option<PipelineState>, beagle_checkpoint::CheckpointError> {
        let config = CheckpointConfig::new(run_id).at_checkpoint(checkpoint_id);
        if let Some(tuple) = self.inner.get_tuple(&config).await? {
            info!(
                run_id = %run_id,
                checkpoint_id = %checkpoint_id,
                phase = %tuple.checkpoint.state.phase,
                "Replaying from checkpoint"
            );
            Ok(Some(tuple.checkpoint.state))
        } else {
            Ok(None)
        }
    }

    /// Fork a run from a checkpoint
    pub async fn fork(
        &self,
        source_run_id: &str,
        new_run_id: &str,
    ) -> Result<Option<PipelineState>, beagle_checkpoint::CheckpointError> {
        if let Some(checkpoint) = self.get_latest(source_run_id).await? {
            let mut new_state = checkpoint.state.clone();
            new_state.run_id = new_run_id.to_string();
            new_state.created_at = Utc::now();
            new_state.updated_at = Utc::now();

            // Save as new checkpoint
            self.checkpoint(&new_state).await?;

            info!(
                source_run_id = %source_run_id,
                new_run_id = %new_run_id,
                phase = %new_state.phase,
                "Forked pipeline"
            );

            Ok(Some(new_state))
        } else {
            Ok(None)
        }
    }

    /// Clear all checkpoints
    pub async fn clear(&self) {
        self.inner.clear().await;
    }
}

impl Default for PipelineCheckpointer {
    fn default() -> Self {
        Self::new()
    }
}

/// Helper trait for checkpointing in pipeline execution
pub trait CheckpointablePipeline {
    /// Get the checkpointer
    fn checkpointer(&self) -> &PipelineCheckpointer;

    /// Checkpoint the current state
    fn checkpoint_state(
        &self,
        state: &PipelineState,
    ) -> impl std::future::Future<Output = Result<uuid::Uuid, beagle_checkpoint::CheckpointError>> + Send
    {
        async { self.checkpointer().checkpoint(state).await }
    }

    /// Try to resume from checkpoint
    fn try_resume(
        &self,
        run_id: &str,
    ) -> impl std::future::Future<Output = Option<PipelineState>> + Send {
        async {
            match self.checkpointer().resume(run_id).await {
                Ok(state) => state,
                Err(e) => {
                    warn!("Failed to resume from checkpoint: {}", e);
                    None
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_pipeline_state_creation() {
        let state = PipelineState::new("run-123", "What is consciousness?");

        assert_eq!(state.run_id, "run-123");
        assert_eq!(state.question, "What is consciousness?");
        assert_eq!(state.phase, PipelinePhase::Started);
        assert!(state.is_resumable());
    }

    #[tokio::test]
    async fn test_phase_progression() {
        let mut state = PipelineState::new("run-123", "test");

        assert_eq!(state.phase, PipelinePhase::Started);
        assert_eq!(state.next_phase(), Some(PipelinePhase::MemoryRag));

        state.advance_to(PipelinePhase::MemoryRag);
        assert_eq!(state.next_phase(), Some(PipelinePhase::DarwinContext));

        state.advance_to(PipelinePhase::Completed);
        assert_eq!(state.next_phase(), None);
        assert!(!state.is_resumable());
    }

    #[tokio::test]
    async fn test_checkpointing() {
        let checkpointer = PipelineCheckpointer::new();
        let mut state = PipelineState::new("run-456", "test question");

        // Initial checkpoint
        let id1 = checkpointer.checkpoint(&state).await.unwrap();

        // Advance and checkpoint again
        state.advance_to(PipelinePhase::DarwinContext);
        state.darwin_context = Some("Some context".to_string());
        let id2 = checkpointer.checkpoint(&state).await.unwrap();

        assert_ne!(id1, id2);

        // Get history
        let history = checkpointer.get_history("run-456").await.unwrap();
        assert_eq!(history.len(), 2);

        // Resume
        let resumed = checkpointer.resume("run-456").await.unwrap().unwrap();
        assert_eq!(resumed.phase, PipelinePhase::DarwinContext);
        assert_eq!(resumed.darwin_context, Some("Some context".to_string()));
    }

    #[tokio::test]
    async fn test_fork() {
        let checkpointer = PipelineCheckpointer::new();
        let mut state = PipelineState::new("run-original", "test");
        state.advance_to(PipelinePhase::HermesSynthesis);
        state.draft = Some("Draft content".to_string());

        checkpointer.checkpoint(&state).await.unwrap();

        // Fork
        let forked = checkpointer
            .fork("run-original", "run-forked")
            .await
            .unwrap()
            .unwrap();

        assert_eq!(forked.run_id, "run-forked");
        assert_eq!(forked.phase, PipelinePhase::HermesSynthesis);
        assert_eq!(forked.draft, Some("Draft content".to_string()));

        // Both should have checkpoints
        assert!(checkpointer.has_checkpoints("run-original").await);
        assert!(checkpointer.has_checkpoints("run-forked").await);
    }

    #[test]
    fn test_phase_display() {
        assert_eq!(PipelinePhase::Started.to_string(), "started");
        assert_eq!(PipelinePhase::DarwinContext.to_string(), "darwin_context");
        assert_eq!(
            PipelinePhase::Failed("error".to_string()).to_string(),
            "failed: error"
        );
    }
}
