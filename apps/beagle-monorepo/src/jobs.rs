//! JobRegistry - Gerenciamento de jobs assíncronos (pipeline, Triad)
//!
//! Gerencia estado de execução de pipelines e Triads com run_id único.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Status de execução de um run
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RunStatus {
    /// Run criado, aguardando execução
    Created,
    /// Pipeline em execução
    Running,
    /// Pipeline concluído com sucesso
    Done,
    /// Pipeline falhou
    Error(String),
    /// Triad em execução
    TriadRunning,
    /// Triad concluída
    TriadDone,
}

/// Estado de um run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunState {
    pub run_id: String,
    pub question: String,
    pub status: RunStatus,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub error: Option<String>,
}

impl RunState {
    pub fn new(run_id: String, question: String) -> Self {
        let now = Utc::now();
        Self {
            run_id,
            question,
            status: RunStatus::Created,
            created_at: now,
            updated_at: now,
            error: None,
        }
    }

    pub fn update_status(&mut self, status: RunStatus) {
        self.status = status;
        self.updated_at = Utc::now();
    }

    pub fn set_error(&mut self, error: String) {
        self.status = RunStatus::Error(error.clone());
        self.error = Some(error);
        self.updated_at = Utc::now();
    }
}

/// Registry de jobs (runs)
#[derive(Debug, Clone)]
pub struct JobRegistry {
    runs: Arc<Mutex<HashMap<String, RunState>>>,
}

impl JobRegistry {
    pub fn new() -> Self {
        Self {
            runs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Cria um novo run
    pub async fn create_run(&self, run_id: String, question: String) -> RunState {
        let state = RunState::new(run_id.clone(), question);
        let mut runs = self.runs.lock().await;
        runs.insert(run_id, state.clone());
        state
    }

    /// Obtém estado de um run
    pub async fn get_run(&self, run_id: &str) -> Option<RunState> {
        let runs = self.runs.lock().await;
        runs.get(run_id).cloned()
    }

    /// Atualiza status de um run
    pub async fn update_status(&self, run_id: &str, status: RunStatus) -> bool {
        let mut runs = self.runs.lock().await;
        if let Some(state) = runs.get_mut(run_id) {
            state.update_status(status);
            true
        } else {
            false
        }
    }

    /// Define erro em um run
    pub async fn set_error(&self, run_id: &str, error: String) -> bool {
        let mut runs = self.runs.lock().await;
        if let Some(state) = runs.get_mut(run_id) {
            state.set_error(error);
            true
        } else {
            false
        }
    }

    /// Lista runs recentes (ordenados por created_at desc)
    pub async fn list_recent(&self, limit: usize) -> Vec<RunState> {
        let runs = self.runs.lock().await;
        let mut states: Vec<RunState> = runs.values().cloned().collect();
        states.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        states.into_iter().take(limit).collect()
    }
}

impl Default for JobRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// SCIENCE JOBS
// ============================================================================

/// Tipo de job científico
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScienceJobKind {
    Pbpk,
    Scaffold,
    Helio,
    Pcs,
    Kec,
    /// Externally-originated job (K8s/Slurm via cockpit reconciler).
    /// Carries a free-form label (e.g. "sounio-test-suite") so the UI can
    /// render something meaningful without the backend knowing the preset.
    External(String),
}

impl ScienceJobKind {
    /// Short slug suitable for UI display. Prefer this over `format!("{:?}", kind)`.
    pub fn kind_label(&self) -> String {
        match self {
            ScienceJobKind::Pbpk => "pbpk".to_string(),
            ScienceJobKind::Scaffold => "scaffold".to_string(),
            ScienceJobKind::Helio => "helio".to_string(),
            ScienceJobKind::Pcs => "pcs".to_string(),
            ScienceJobKind::Kec => "kec".to_string(),
            ScienceJobKind::External(label) => label.clone(),
        }
    }
}

/// Status de um job científico
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScienceJobStatus {
    Created,
    Running,
    Error(String),
    Done,
}

impl ToString for ScienceJobStatus {
    fn to_string(&self) -> String {
        match self {
            ScienceJobStatus::Created => "created".to_string(),
            ScienceJobStatus::Running => "running".to_string(),
            ScienceJobStatus::Error(_) => "error".to_string(),
            ScienceJobStatus::Done => "done".to_string(),
        }
    }
}

/// Estado de um job científico em execução
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScienceJobState {
    pub job_id: String,
    pub kind: ScienceJobKind,
    pub status: ScienceJobStatus,
    pub params: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub error: Option<String>,
    pub output_paths: Vec<String>,
    pub result_json: Option<serde_json::Value>,
}

impl ScienceJobState {
    pub fn new(job_id: String, kind: ScienceJobKind, params: serde_json::Value) -> Self {
        let now = Utc::now();
        Self {
            job_id,
            kind,
            status: ScienceJobStatus::Created,
            params,
            created_at: now,
            updated_at: now,
            error: None,
            output_paths: Vec::new(),
            result_json: None,
        }
    }

    pub fn update_status(&mut self, status: ScienceJobStatus) {
        self.status = status;
        self.updated_at = Utc::now();
    }

    pub fn set_error(&mut self, error_msg: String) {
        self.status = ScienceJobStatus::Error(error_msg.clone());
        self.error = Some(error_msg);
        self.updated_at = Utc::now();
    }
}

/// Registry de jobs científicos
#[derive(Debug, Clone)]
pub struct ScienceJobRegistry {
    jobs: Arc<Mutex<HashMap<String, ScienceJobState>>>,
}

impl ScienceJobRegistry {
    pub fn new() -> Self {
        Self {
            jobs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn add_job(&self, job_state: ScienceJobState) {
        let mut jobs = self.jobs.lock().await;
        jobs.insert(job_state.job_id.clone(), job_state);
    }

    pub async fn get_job(&self, job_id: &str) -> Option<ScienceJobState> {
        let jobs = self.jobs.lock().await;
        jobs.get(job_id).cloned()
    }

    pub async fn update_job<F>(&self, job_id: &str, f: F)
    where
        F: FnOnce(&mut ScienceJobState),
    {
        let mut jobs = self.jobs.lock().await;
        if let Some(job_state) = jobs.get_mut(job_id) {
            f(job_state);
        }
    }

    /// Upsert an externally-managed job (cockpit reconciler).
    /// Preserves `created_at` if the entry already exists so we don't clobber
    /// the original submission time on subsequent register ticks.
    pub async fn register_external(
        &self,
        job_id: String,
        label: String,
        status: ScienceJobStatus,
        started_at: Option<DateTime<Utc>>,
    ) {
        let mut jobs = self.jobs.lock().await;
        let now = Utc::now();
        let created_at = started_at.unwrap_or(now);
        jobs.entry(job_id.clone())
            .and_modify(|existing| {
                existing.status = status.clone();
                existing.updated_at = now;
            })
            .or_insert(ScienceJobState {
                job_id,
                kind: ScienceJobKind::External(label),
                status,
                params: serde_json::Value::Null,
                created_at,
                updated_at: now,
                error: None,
                output_paths: Vec::new(),
                result_json: None,
            });
    }

    /// Mark an externally-managed job as terminal. Safe even if the job was
    /// never registered — creates a placeholder entry in that case so the
    /// completion still surfaces.
    pub async fn complete_external(
        &self,
        job_id: String,
        label: String,
        status: ScienceJobStatus,
        error: Option<String>,
    ) {
        let mut jobs = self.jobs.lock().await;
        let now = Utc::now();
        let entry = jobs.entry(job_id.clone()).or_insert(ScienceJobState {
            job_id,
            kind: ScienceJobKind::External(label),
            status: ScienceJobStatus::Created,
            params: serde_json::Value::Null,
            created_at: now,
            updated_at: now,
            error: None,
            output_paths: Vec::new(),
            result_json: None,
        });
        entry.status = status;
        entry.error = error;
        entry.updated_at = now;
    }

    pub async fn get_recent_jobs(&self, limit: usize) -> Vec<ScienceJobState> {
        let jobs = self.jobs.lock().await;
        let mut sorted_jobs: Vec<ScienceJobState> = jobs.values().cloned().collect();
        sorted_jobs.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        sorted_jobs.into_iter().take(limit).collect()
    }
}

impl Default for ScienceJobRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// COGNITIVE NOVELTY REGISTRIES (void / fractal / phi)
//
// Pattern mirrors ScienceJobRegistry above: in-memory Vec behind a Mutex,
// fixed-size recent-window query for the cognitive state aggregator. BUT:
// these three are ALSO persisted to JSONL under $BEAGLE_DATA_DIR so that
// pod restarts don't amnesiate the cognitive history. The last 64 entries
// are loaded at boot via `load_from_disk(path)`. Pattern mirrors the
// beagle-feedback crate's file store.
// ============================================================================

fn data_root() -> std::path::PathBuf {
    std::env::var("BEAGLE_DATA_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from("/var/lib/beagle"))
}

/// Append one JSON line to the given file under BEAGLE_DATA_DIR.
/// Best-effort: file errors are logged but never propagated — registry
/// observability must never fail the request.
fn jsonl_append<T: Serialize>(filename: &str, value: &T) {
    let path = data_root().join(filename);
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) else {
        tracing::warn!("jsonl_append: cannot open {:?}", path);
        return;
    };
    if let Ok(s) = serde_json::to_string(value) {
        use std::io::Write;
        let _ = writeln!(f, "{}", s);
    }
}

/// Read the last `limit` entries from a JSONL file. Missing file → empty vec.
pub fn jsonl_load_tail<T: for<'de> Deserialize<'de>>(filename: &str, limit: usize) -> Vec<T> {
    let path = data_root().join(filename);
    let Ok(contents) = std::fs::read_to_string(&path) else {
        return Vec::new();
    };
    let lines: Vec<&str> = contents.lines().collect();
    let start = lines.len().saturating_sub(limit);
    lines[start..]
        .iter()
        .filter_map(|l| serde_json::from_str::<T>(l).ok())
        .collect()
}

/// Re-export for callers that persist things outside jobs.rs (e.g. physio).
pub fn jsonl_append_pub<T: Serialize>(filename: &str, value: &T) {
    jsonl_append(filename, value)
}

/// Canonical file under $BEAGLE_DATA_DIR for HRV/physio persistence.
pub const PHYSIO_JSONL: &str = "cognitive/physio.jsonl";

/// Summary of a single /dev/void journey — what the iOS widget sees.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoidJourneySummary {
    pub journey_id: String,
    pub focus: String,
    pub target_depth: f64,
    pub max_depth_reached: Option<f64>,
    pub duration_ms: Option<u64>,
    pub insight_count: usize,
    pub probe_result: Option<String>,
    pub completed_at: DateTime<Utc>,
    pub truth_mode: String,
}

const VOID_JSONL: &str = "cognitive/voids.jsonl";

#[derive(Debug, Clone, Default)]
pub struct VoidJourneyRegistry {
    inner: Arc<Mutex<Vec<VoidJourneySummary>>>,
}

impl VoidJourneyRegistry {
    pub fn new() -> Self {
        let warm: Vec<VoidJourneySummary> = jsonl_load_tail(VOID_JSONL, 64);
        Self {
            inner: Arc::new(Mutex::new(warm)),
        }
    }

    pub async fn append(&self, entry: VoidJourneySummary) {
        jsonl_append(VOID_JSONL, &entry);
        let mut v = self.inner.lock().await;
        v.push(entry);
        let len = v.len();
        if len > 64 {
            v.drain(0..(len - 64));
        }
    }

    pub async fn recent(&self, limit: usize) -> Vec<VoidJourneySummary> {
        let v = self.inner.lock().await;
        v.iter().rev().take(limit).cloned().collect()
    }
}

/// Summary of one fractal recursion tree.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FractalTreeSummary {
    pub root_id: String,
    pub root_prompt: String,
    pub max_depth: u8,
    pub branching: u8,
    pub node_count: usize,
    pub generated_at: DateTime<Utc>,
    pub duration_ms: u64,
    pub truth_mode: String,
}

const FRACTAL_JSONL: &str = "cognitive/fractals.jsonl";

#[derive(Debug, Clone, Default)]
pub struct FractalTreeRegistry {
    inner: Arc<Mutex<Vec<FractalTreeSummary>>>,
}

impl FractalTreeRegistry {
    pub fn new() -> Self {
        let warm: Vec<FractalTreeSummary> = jsonl_load_tail(FRACTAL_JSONL, 64);
        Self {
            inner: Arc::new(Mutex::new(warm)),
        }
    }

    pub async fn append(&self, entry: FractalTreeSummary) {
        jsonl_append(FRACTAL_JSONL, &entry);
        let mut v = self.inner.lock().await;
        v.push(entry);
        let len = v.len();
        if len > 64 {
            v.drain(0..(len - 64));
        }
    }

    pub async fn recent(&self, limit: usize) -> Vec<FractalTreeSummary> {
        let v = self.inner.lock().await;
        v.iter().rev().take(limit).cloned().collect()
    }
}

/// Summary of one exocortex IIT Φ measurement.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhiMeasurementSummary {
    pub query_snippet: String,
    pub phi: f64,
    pub substrate_size: usize,
    pub mip_partition: (Vec<String>, Vec<String>),
    pub awareness_level: String,
    pub router_tier: String,
    pub measured_at: DateTime<Utc>,
    pub duration_ms: u64,
    pub truth_mode: String,
    /// "embeddings" when the TPM was built from cosine similarity over
    /// EmbeddingClient vectors; "activations" when we fell back to token
    /// co-occurrence. Legacy JSONL entries (before this field) default to
    /// "activations" — matches the old behavior honestly.
    #[serde(default = "default_tpm_source")]
    pub tpm_source: String,
}

fn default_tpm_source() -> String {
    "activations".to_string()
}

const PHI_JSONL: &str = "cognitive/phis.jsonl";

#[derive(Debug, Clone, Default)]
pub struct PhiMeasurementRegistry {
    inner: Arc<Mutex<Vec<PhiMeasurementSummary>>>,
}

impl PhiMeasurementRegistry {
    pub fn new() -> Self {
        let warm: Vec<PhiMeasurementSummary> = jsonl_load_tail(PHI_JSONL, 64);
        Self {
            inner: Arc::new(Mutex::new(warm)),
        }
    }

    pub async fn append(&self, entry: PhiMeasurementSummary) {
        jsonl_append(PHI_JSONL, &entry);
        let mut v = self.inner.lock().await;
        v.push(entry);
        let len = v.len();
        if len > 64 {
            v.drain(0..(len - 64));
        }
    }

    pub async fn recent(&self, limit: usize) -> Vec<PhiMeasurementSummary> {
        let v = self.inner.lock().await;
        v.iter().rev().take(limit).cloned().collect()
    }
}

// ─── MCP tool-call history ─────────────────────────────────────────
//
// Every MCP tool invocation — from Claude Desktop, Claude Code, or
// ChatGPT — becomes an observable cognitive event. The MCP server POSTs
// here after each tools/call. Lets the platform measure Φ over its own
// tool-usage rhythm (see /api/v1/cognitive/tool_rhythm_phi).

const MCP_TOOL_JSONL: &str = "cognitive/mcp_tool_calls.jsonl";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpToolCallSummary {
    pub tool_name: String,
    pub caller: String,
    /// Milliseconds the tool took end-to-end (including beagle-core HTTP
    /// roundtrip). Only present when the MCP server can measure it.
    pub duration_ms: Option<u64>,
    /// true when the tool's result carried {error}; lets tool_rhythm_phi
    /// weight failures separately.
    pub is_error: bool,
    pub invoked_at: DateTime<Utc>,
    pub truth_mode: String,
}

#[derive(Debug, Clone, Default)]
pub struct McpToolCallRegistry {
    inner: Arc<Mutex<Vec<McpToolCallSummary>>>,
}

impl McpToolCallRegistry {
    pub fn new() -> Self {
        let warm: Vec<McpToolCallSummary> = jsonl_load_tail(MCP_TOOL_JSONL, 256);
        Self {
            inner: Arc::new(Mutex::new(warm)),
        }
    }

    pub async fn append(&self, entry: McpToolCallSummary) {
        jsonl_append(MCP_TOOL_JSONL, &entry);
        let mut v = self.inner.lock().await;
        v.push(entry);
        let len = v.len();
        if len > 256 {
            v.drain(0..(len - 256));
        }
    }

    pub async fn recent(&self, limit: usize) -> Vec<McpToolCallSummary> {
        let v = self.inner.lock().await;
        v.iter().rev().take(limit).cloned().collect()
    }

    /// Chronological tool_name sequence (oldest → newest) for Φ math.
    pub async fn trajectory(&self, limit: usize) -> Vec<String> {
        let v = self.inner.lock().await;
        let start = v.len().saturating_sub(limit);
        v[start..].iter().map(|e| e.tool_name.clone()).collect()
    }

    /// Like `trajectory`, but filtered by caller — used for per-session
    /// rhythm analysis. Empty `caller` returns the global trajectory.
    pub async fn trajectory_for(&self, caller: &str, limit: usize) -> Vec<String> {
        let v = self.inner.lock().await;
        let filtered: Vec<&McpToolCallSummary> = if caller.is_empty() {
            v.iter().collect()
        } else {
            v.iter().filter(|e| e.caller == caller).collect()
        };
        let start = filtered.len().saturating_sub(limit);
        filtered[start..]
            .iter()
            .map(|e| e.tool_name.clone())
            .collect()
    }

    /// Distinct callers seen in the registry (used to surface split
    /// rhythms in /api/v1/cognitive/tool_rhythm_phi).
    pub async fn callers(&self) -> Vec<String> {
        let v = self.inner.lock().await;
        let mut set = std::collections::BTreeSet::new();
        for e in v.iter() {
            set.insert(e.caller.clone());
        }
        set.into_iter().collect()
    }
}

// ─── Deep-Think Registry ───────────────────────────────────────────
//
// One entry per /api/cognitive/deep-think invocation. Mirrors the other
// three registry patterns: in-memory + JSONL, warm-load on boot, truth_mode
// on each entry.

const DEEP_THINK_JSONL: &str = "cognitive/deep_thinks.jsonl";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeepThinkSummary {
    pub journey_id: String,
    pub root_prompt: String,
    pub fractal_node_count: usize,
    pub void_journey_count: usize,
    pub phi: f64,
    pub tpm_source: String,
    pub hrv_tier: String,
    pub duration_ms: u64,
    pub generated_at: DateTime<Utc>,
    pub truth_mode: String,
}

#[derive(Debug, Clone, Default)]
pub struct DeepThinkRegistry {
    inner: Arc<Mutex<Vec<DeepThinkSummary>>>,
}

impl DeepThinkRegistry {
    pub fn new() -> Self {
        let warm: Vec<DeepThinkSummary> = jsonl_load_tail(DEEP_THINK_JSONL, 64);
        Self {
            inner: Arc::new(Mutex::new(warm)),
        }
    }

    pub async fn append(&self, entry: DeepThinkSummary) {
        jsonl_append(DEEP_THINK_JSONL, &entry);
        let mut v = self.inner.lock().await;
        v.push(entry);
        let len = v.len();
        if len > 64 {
            v.drain(0..(len - 64));
        }
    }

    pub async fn recent(&self, limit: usize) -> Vec<DeepThinkSummary> {
        let v = self.inner.lock().await;
        v.iter().rev().take(limit).cloned().collect()
    }
}

/// Stamp a truth_mode based on age of a measurement. `observed` if < 10min
/// old, `stale` otherwise. Callers pass `observed` at append time; the
/// cognitive-state handler re-stamps to `stale` when it sees aged entries.
pub fn truth_mode_for_age(ts: DateTime<Utc>) -> &'static str {
    let age = Utc::now().signed_duration_since(ts);
    if age.num_minutes() < 10 {
        "observed"
    } else {
        "stale"
    }
}
