# BEAGLE Framework Integration Plan

## Executive Summary

This document outlines integration strategies inspired by three leading AI agent frameworks:
1. **DSPy** - For prompt layer improvements (Signatures + Optimizers)
2. **LangGraph** - For checkpointing and state persistence
3. **AutoGen Studio** - For Exocortex UI patterns

---

## 1. DSPy Integration: Typed Prompt Contracts

### 1.1 Current State Analysis

BEAGLE's `RequestMeta` (`crates/beagle-llm/src/routing_types.rs`) already provides:
- Quality requirements (`requires_high_quality`, `requires_phd_level_reasoning`)
- Capability requirements (`requires_math`, `requires_vision`, `requires_code`)
- Operational requirements (`offline_required`, `approximate_tokens`)
- Priority scoring via `priority_score()` method

**Gap**: No formal input/output typing for prompts (like DSPy Signatures).

### 1.2 DSPy Concepts to Adopt

#### Signatures (Typed Contracts)

DSPy Signatures declare what a transformation should achieve:

```python
# DSPy Example
class ExtractInfo(dspy.Signature):
    text: str = dspy.InputField()
    title: str = dspy.OutputField()
    entities: list[dict] = dspy.OutputField(desc="entities and metadata")
```

**BEAGLE Equivalent** - Create `PromptSignature` trait:

```rust
// crates/beagle-llm/src/signatures.rs

use serde::{Serialize, Deserialize};

/// Typed prompt signature (inspired by DSPy)
pub trait PromptSignature: Send + Sync {
    /// Input type for this signature
    type Input: Serialize + Send;
    /// Output type for this signature
    type Output: for<'de> Deserialize<'de> + Send;
    
    /// Signature description for prompt generation
    fn description(&self) -> &str;
    
    /// Generate prompt from input
    fn to_prompt(&self, input: &Self::Input) -> String;
    
    /// Parse output from LLM response
    fn parse_output(&self, response: &str) -> Result<Self::Output, SignatureError>;
    
    /// Get RequestMeta for routing
    fn request_meta(&self) -> RequestMeta;
}

/// Example: Triad ATHENA Signature
pub struct AthenaReviewSignature;

#[derive(Serialize)]
pub struct AthenaInput {
    pub draft: String,
    pub context_summary: Option<String>,
    pub domain_keywords: Vec<String>,
}

#[derive(Deserialize)]
pub struct AthenaOutput {
    pub strengths: Vec<String>,
    pub weaknesses: Vec<String>,
    pub suggested_references: Vec<Citation>,
    pub score: f32,
}

impl PromptSignature for AthenaReviewSignature {
    type Input = AthenaInput;
    type Output = AthenaOutput;
    
    fn description(&self) -> &str {
        "Scientific draft review with Q1 journal standards"
    }
    
    fn request_meta(&self) -> RequestMeta {
        RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            critical_section: false,
            ..Default::default()
        }
    }
    
    // ... implementation
}
```

#### Modules (Prompt Techniques)

DSPy modules apply specific prompt techniques:
- `ChainOfThought` - Generates reasoning before output
- `ReAct` - Enables tool use with reasoning
- `ProgramOfThought` - Generates code to solve problems

**BEAGLE Implementation**:

```rust
// crates/beagle-llm/src/modules.rs

/// Prompt module that wraps a signature with a technique
pub trait PromptModule<S: PromptSignature>: Send + Sync {
    /// Execute the module with the given input
    async fn execute(
        &self,
        ctx: &BeagleContext,
        input: &S::Input,
    ) -> Result<S::Output, ModuleError>;
}

/// Chain of Thought module
pub struct ChainOfThought<S: PromptSignature> {
    signature: S,
    reasoning_prefix: String,
}

impl<S: PromptSignature> ChainOfThought<S> {
    pub fn new(signature: S) -> Self {
        Self {
            signature,
            reasoning_prefix: "Let me think step by step:".to_string(),
        }
    }
}

impl<S: PromptSignature> PromptModule<S> for ChainOfThought<S> {
    async fn execute(
        &self,
        ctx: &BeagleContext,
        input: &S::Input,
    ) -> Result<S::Output, ModuleError> {
        let base_prompt = self.signature.to_prompt(input);
        let cot_prompt = format!(
            "{}\n\n{}\n\nAfter reasoning, provide your answer in the required format.",
            base_prompt,
            self.reasoning_prefix
        );
        
        let meta = self.signature.request_meta();
        let stats = ctx.llm_stats.get_or_create("module_exec");
        let (client, _tier) = ctx.router.choose_with_limits(&meta, &stats);
        
        let output = client.complete(&cot_prompt).await?;
        self.signature.parse_output(&output.text)
    }
}
```

#### Optimizers (Auto-Tuning)

DSPy's MIPROv2 optimizer:
1. **Bootstrapping** - Collects high-performing traces
2. **Grounded Proposal** - Drafts improved instructions
3. **Discrete Search** - Evaluates combinations

**BEAGLE Implementation** - `PromptOptimizer`:

```rust
// crates/beagle-llm/src/optimizer.rs

/// Trace of a signature execution
#[derive(Serialize, Deserialize)]
pub struct ExecutionTrace<I, O> {
    pub input: I,
    pub output: O,
    pub score: f64,
    pub latency_ms: u64,
    pub provider_tier: ProviderTier,
}

/// Prompt optimizer (inspired by DSPy MIPROv2)
pub struct PromptOptimizer<S: PromptSignature> {
    signature: S,
    traces: Vec<ExecutionTrace<S::Input, S::Output>>,
    best_instructions: Option<String>,
    metric: Box<dyn Fn(&S::Output) -> f64 + Send + Sync>,
}

impl<S: PromptSignature> PromptOptimizer<S> {
    /// Bootstrap phase: collect high-scoring traces
    pub async fn bootstrap(
        &mut self,
        ctx: &BeagleContext,
        inputs: &[S::Input],
        min_score: f64,
    ) -> Result<(), OptimizerError> {
        for input in inputs {
            let output = self.execute_and_trace(ctx, input).await?;
            let score = (self.metric)(&output);
            if score >= min_score {
                self.traces.push(ExecutionTrace {
                    input: input.clone(),
                    output,
                    score,
                    // ...
                });
            }
        }
        Ok(())
    }
    
    /// Propose improved instructions based on traces
    pub async fn propose_instructions(
        &self,
        ctx: &BeagleContext,
    ) -> Result<Vec<String>, OptimizerError> {
        // Use LLM to generate improved instructions based on high-scoring traces
        let meta_prompt = self.build_meta_prompt();
        // ... generate N candidate instructions
        Ok(vec![])
    }
    
    /// Search for best instruction combination
    pub async fn optimize(
        &mut self,
        ctx: &BeagleContext,
        validation_set: &[S::Input],
    ) -> Result<OptimizationResult, OptimizerError> {
        // Evaluate candidate instructions on validation set
        // Return best performing configuration
        Ok(OptimizationResult::default())
    }
}
```

### 1.3 Triad Auto-Tuning Application

Apply DSPy-style optimization to Triad prompts:

```rust
// Example: Optimize ARGOS critic prompts
let argos_signature = ArgosCriticSignature::new();
let mut optimizer = PromptOptimizer::new(
    argos_signature,
    |output| output.precision_score * 0.6 + output.recall_score * 0.4,
);

// Bootstrap with historical Triad runs
optimizer.bootstrap(&ctx, &historical_inputs, 0.8).await?;

// Generate improved instructions
let candidates = optimizer.propose_instructions(&ctx).await?;

// Find best configuration
let result = optimizer.optimize(&ctx, &validation_inputs).await?;

// Apply optimized signature
let optimized_argos = result.best_signature;
```

---

## 2. LangGraph Checkpointing: State Persistence

### 2.1 Current State Analysis

BEAGLE has:
- `beagle-sync/src/storage.rs` - WAL, snapshots, MVCC (excellent foundation)
- `beagle-feedback` - Feedback collection (needs checkpointing)
- Pipeline runs with `run_id` tracking

**Gap**: No formal checkpoint API for pipeline state recovery.

### 2.2 LangGraph Concepts to Adopt

#### Checkpointer Interface

LangGraph's `BaseCheckpointSaver`:
- `put(config, checkpoint, metadata)` - Store checkpoint
- `get_tuple(config)` - Retrieve checkpoint
- `list(config, filter)` - List checkpoints
- Thread-based organization

**BEAGLE Implementation** - `PipelineCheckpointer`:

```rust
// crates/beagle-checkpoint/src/lib.rs

use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

/// Checkpoint configuration (thread + optional checkpoint ID)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckpointConfig {
    /// Thread ID (e.g., run_id, session_id)
    pub thread_id: String,
    /// Specific checkpoint ID (if replaying)
    pub checkpoint_id: Option<Uuid>,
    /// Namespace for multi-tenant isolation
    pub namespace: Option<String>,
}

/// Checkpoint metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckpointMetadata {
    /// Source node that created this checkpoint
    pub source_node: String,
    /// Step number in execution
    pub step: u64,
    /// Timestamp
    pub created_at: DateTime<Utc>,
    /// Parent checkpoint ID
    pub parent_id: Option<Uuid>,
    /// Custom metadata
    pub custom: serde_json::Value,
}

/// A checkpoint snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Checkpoint<S: Serialize + for<'de> Deserialize<'de>> {
    /// Unique checkpoint ID
    pub id: Uuid,
    /// Configuration
    pub config: CheckpointConfig,
    /// Metadata
    pub metadata: CheckpointMetadata,
    /// State values
    pub state: S,
    /// Pending writes (for fault tolerance)
    pub pending_writes: Vec<PendingWrite>,
}

/// Pending write for fault tolerance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingWrite {
    pub node: String,
    pub data: serde_json::Value,
}

/// Checkpointer trait (inspired by LangGraph)
#[async_trait]
pub trait Checkpointer<S>: Send + Sync 
where
    S: Serialize + for<'de> Deserialize<'de> + Send + Sync,
{
    /// Store a checkpoint
    async fn put(
        &self,
        config: &CheckpointConfig,
        state: &S,
        metadata: CheckpointMetadata,
    ) -> Result<Uuid, CheckpointError>;
    
    /// Store pending writes (for fault tolerance)
    async fn put_writes(
        &self,
        config: &CheckpointConfig,
        writes: Vec<PendingWrite>,
    ) -> Result<(), CheckpointError>;
    
    /// Get checkpoint tuple
    async fn get_tuple(
        &self,
        config: &CheckpointConfig,
    ) -> Result<Option<Checkpoint<S>>, CheckpointError>;
    
    /// List checkpoints for a thread
    async fn list(
        &self,
        config: &CheckpointConfig,
        limit: Option<usize>,
    ) -> Result<Vec<Checkpoint<S>>, CheckpointError>;
    
    /// Get state history (time travel)
    async fn get_history(
        &self,
        config: &CheckpointConfig,
    ) -> Result<Vec<Checkpoint<S>>, CheckpointError>;
}
```

#### Pipeline State Definition

```rust
// crates/beagle-checkpoint/src/pipeline_state.rs

/// Pipeline execution state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineState {
    /// Current phase
    pub phase: PipelinePhase,
    /// Question/input
    pub question: String,
    /// Research results
    pub research_results: Option<ResearchResults>,
    /// Draft content
    pub draft: Option<String>,
    /// Triad opinions
    pub triad_opinions: Vec<TriadOpinion>,
    /// Final output
    pub final_output: Option<String>,
    /// LLM call statistics
    pub llm_stats: LlmCallsStats,
    /// Errors encountered
    pub errors: Vec<PipelineError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PipelinePhase {
    Started,
    ResearchComplete,
    DraftGenerated,
    TriadAthenaComplete,
    TriadHermesComplete,
    TriadArgosComplete,
    TriadJudgeComplete,
    Finalized,
    Failed(String),
}

impl PipelineState {
    /// Check if can resume from this state
    pub fn is_resumable(&self) -> bool {
        !matches!(self.phase, PipelinePhase::Finalized | PipelinePhase::Failed(_))
    }
    
    /// Get next phase
    pub fn next_phase(&self) -> Option<PipelinePhase> {
        match self.phase {
            PipelinePhase::Started => Some(PipelinePhase::ResearchComplete),
            PipelinePhase::ResearchComplete => Some(PipelinePhase::DraftGenerated),
            // ...
            PipelinePhase::Finalized => None,
            PipelinePhase::Failed(_) => None,
        }
    }
}
```

#### Checkpointer Implementations

```rust
// PostgreSQL Checkpointer
pub struct PostgresCheckpointer {
    pool: PgPool,
    serde: JsonPlusSerializer,
}

impl<S> Checkpointer<S> for PostgresCheckpointer
where
    S: Serialize + for<'de> Deserialize<'de> + Send + Sync,
{
    async fn put(
        &self,
        config: &CheckpointConfig,
        state: &S,
        metadata: CheckpointMetadata,
    ) -> Result<Uuid, CheckpointError> {
        let id = Uuid::new_v4();
        let state_json = self.serde.serialize(state)?;
        
        sqlx::query!(
            r#"
            INSERT INTO checkpoints (id, thread_id, namespace, source_node, step, state, metadata, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            "#,
            id,
            config.thread_id,
            config.namespace,
            metadata.source_node,
            metadata.step as i64,
            state_json,
            serde_json::to_value(&metadata)?,
            metadata.created_at,
        )
        .execute(&self.pool)
        .await?;
        
        Ok(id)
    }
    
    // ... other implementations
}

// In-Memory Checkpointer (for testing)
pub struct InMemoryCheckpointer<S> {
    checkpoints: Arc<RwLock<HashMap<String, Vec<Checkpoint<S>>>>>,
}

// Redis Checkpointer (for distributed deployments)
pub struct RedisCheckpointer {
    client: redis::Client,
    ttl_secs: u64,
}
```

#### Integration with Pipeline

```rust
// apps/beagle-monorepo/src/pipeline.rs

pub async fn run_pipeline_with_checkpoints(
    ctx: &BeagleContext,
    question: &str,
    checkpointer: &dyn Checkpointer<PipelineState>,
    config: CheckpointConfig,
) -> anyhow::Result<PipelineOutput> {
    // Try to resume from existing checkpoint
    let mut state = if let Some(checkpoint) = checkpointer.get_tuple(&config).await? {
        tracing::info!(
            checkpoint_id = %checkpoint.id,
            phase = ?checkpoint.state.phase,
            "Resuming pipeline from checkpoint"
        );
        checkpoint.state
    } else {
        PipelineState {
            phase: PipelinePhase::Started,
            question: question.to_string(),
            ..Default::default()
        }
    };
    
    // Execute phases with checkpointing
    loop {
        match state.phase {
            PipelinePhase::Started => {
                state.research_results = Some(run_research(ctx, question).await?);
                state.phase = PipelinePhase::ResearchComplete;
                checkpoint_state(&checkpointer, &config, &state, "research").await?;
            }
            PipelinePhase::ResearchComplete => {
                state.draft = Some(generate_draft(ctx, &state).await?);
                state.phase = PipelinePhase::DraftGenerated;
                checkpoint_state(&checkpointer, &config, &state, "draft").await?;
            }
            // ... other phases
            PipelinePhase::Finalized => break,
            PipelinePhase::Failed(ref err) => return Err(anyhow::anyhow!("{}", err)),
        }
    }
    
    Ok(state.into())
}

async fn checkpoint_state(
    checkpointer: &dyn Checkpointer<PipelineState>,
    config: &CheckpointConfig,
    state: &PipelineState,
    source_node: &str,
) -> Result<(), CheckpointError> {
    let metadata = CheckpointMetadata {
        source_node: source_node.to_string(),
        step: state.phase.step_number(),
        created_at: Utc::now(),
        parent_id: None, // Would track from previous checkpoint
        custom: serde_json::json!({}),
    };
    
    checkpointer.put(config, state, metadata).await?;
    Ok(())
}
```

#### Time Travel API

```rust
/// Replay pipeline from specific checkpoint
pub async fn replay_from_checkpoint(
    ctx: &BeagleContext,
    checkpointer: &dyn Checkpointer<PipelineState>,
    config: CheckpointConfig,
    checkpoint_id: Uuid,
) -> anyhow::Result<PipelineOutput> {
    let replay_config = CheckpointConfig {
        checkpoint_id: Some(checkpoint_id),
        ..config
    };
    
    // This will fork from the specified checkpoint
    run_pipeline_with_checkpoints(ctx, "", checkpointer, replay_config).await
}

/// Update state at checkpoint (human-in-the-loop)
pub async fn update_state_at_checkpoint(
    checkpointer: &dyn Checkpointer<PipelineState>,
    config: &CheckpointConfig,
    updates: PipelineStateUpdates,
) -> anyhow::Result<Uuid> {
    let current = checkpointer.get_tuple(config).await?
        .ok_or_else(|| anyhow::anyhow!("Checkpoint not found"))?;
    
    let mut new_state = current.state;
    new_state.apply_updates(updates);
    
    let metadata = CheckpointMetadata {
        source_node: "human_update".to_string(),
        step: current.metadata.step,
        created_at: Utc::now(),
        parent_id: Some(current.id),
        custom: serde_json::json!({"type": "human_in_the_loop"}),
    };
    
    checkpointer.put(config, &new_state, metadata).await
}
```

### 2.3 Database Schema

```sql
-- migrations/NNNN_add_checkpoints.sql

CREATE TABLE checkpoints (
    id UUID PRIMARY KEY,
    thread_id VARCHAR(255) NOT NULL,
    namespace VARCHAR(255),
    source_node VARCHAR(255) NOT NULL,
    step BIGINT NOT NULL,
    state JSONB NOT NULL,
    metadata JSONB NOT NULL,
    parent_id UUID REFERENCES checkpoints(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Indexes for efficient queries
    INDEX idx_checkpoints_thread (thread_id, created_at DESC),
    INDEX idx_checkpoints_namespace (namespace, thread_id),
    INDEX idx_checkpoints_parent (parent_id)
);

CREATE TABLE pending_writes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checkpoint_id UUID NOT NULL REFERENCES checkpoints(id) ON DELETE CASCADE,
    node VARCHAR(255) NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 3. AutoGen Studio: Exocortex UI Patterns

### 3.1 Key UI Components

AutoGen Studio provides:
1. **Team Builder** - Visual drag-and-drop for agent composition
2. **Playground** - Interactive testing with live streaming
3. **Gallery** - Component discovery and sharing
4. **Deployment** - Export to JSON/Docker

### 3.2 BEAGLE Exocortex UI Design

#### Workflow Definition Format (JSON)

```json
{
  "version": "1.0",
  "name": "Research Pipeline",
  "description": "Scientific document research and review workflow",
  "team": {
    "name": "Research Triad",
    "agents": [
      {
        "id": "athena",
        "type": "research_specialist",
        "capabilities": ["research", "analysis", "citation"],
        "model_config": {
          "tier": "premium",
          "requires_phd_level": true
        },
        "system_prompt": "You are ATHENA, the scientific rigor specialist..."
      },
      {
        "id": "hermes",
        "type": "writer",
        "capabilities": ["writing", "synthesis", "editing"],
        "model_config": {
          "tier": "standard"
        }
      },
      {
        "id": "argos",
        "type": "critic",
        "capabilities": ["analysis", "critique", "validation"],
        "model_config": {
          "tier": "premium",
          "high_bias_risk": true
        }
      }
    ],
    "termination": {
      "type": "judge_consensus",
      "max_rounds": 3,
      "min_score": 0.85
    }
  },
  "tools": [
    {
      "id": "pubmed_search",
      "type": "api",
      "config": {
        "endpoint": "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/",
        "rate_limit": 3
      }
    },
    {
      "id": "arxiv_search",
      "type": "api",
      "config": {
        "endpoint": "https://export.arxiv.org/api/"
      }
    }
  ],
  "flow": {
    "type": "sequential",
    "steps": [
      {"agent": "athena", "action": "review", "output": "athena_feedback"},
      {"agent": "hermes", "action": "rewrite", "input": ["draft", "athena_feedback"]},
      {"agent": "argos", "action": "critique", "input": ["draft", "hermes_output"]},
      {"agent": "judge", "action": "arbitrate", "input": ["*"]}
    ]
  }
}
```

#### Rust Types for UI Integration

```rust
// crates/beagle-exocortex/src/workflow.rs

use serde::{Serialize, Deserialize};

/// Workflow definition (JSON-serializable for UI)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowDefinition {
    pub version: String,
    pub name: String,
    pub description: Option<String>,
    pub team: TeamDefinition,
    pub tools: Vec<ToolDefinition>,
    pub flow: FlowDefinition,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamDefinition {
    pub name: String,
    pub agents: Vec<AgentDefinition>,
    pub termination: TerminationConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentDefinition {
    pub id: String,
    #[serde(rename = "type")]
    pub agent_type: String,
    pub capabilities: Vec<String>,
    pub model_config: ModelConfig,
    pub system_prompt: Option<String>,
    pub tools: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelConfig {
    pub tier: String,
    pub requires_phd_level: Option<bool>,
    pub high_bias_risk: Option<bool>,
    pub max_tokens: Option<usize>,
    pub temperature: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowDefinition {
    #[serde(rename = "type")]
    pub flow_type: FlowType,
    pub steps: Vec<FlowStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FlowType {
    Sequential,
    Parallel,
    Conditional,
    Loop,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowStep {
    pub agent: String,
    pub action: String,
    pub input: Option<Vec<String>>,
    pub output: Option<String>,
    pub condition: Option<String>,
}

impl WorkflowDefinition {
    /// Convert to RequestMeta for an agent
    pub fn agent_request_meta(&self, agent_id: &str) -> Option<RequestMeta> {
        self.team.agents.iter()
            .find(|a| a.id == agent_id)
            .map(|a| RequestMeta {
                requires_high_quality: a.model_config.tier == "premium",
                requires_phd_level_reasoning: a.model_config.requires_phd_level.unwrap_or(false),
                high_bias_risk: a.model_config.high_bias_risk.unwrap_or(false),
                ..Default::default()
            })
    }
    
    /// Validate workflow definition
    pub fn validate(&self) -> Result<(), ValidationError> {
        // Check all agent references exist
        // Validate flow connectivity
        // Check tool configurations
        Ok(())
    }
}
```

#### REST API for UI

```rust
// crates/beagle-server/src/api/routes/workflows.rs

use axum::{
    extract::{Path, State, Json},
    routing::{get, post, put, delete},
    Router,
};

pub fn workflow_routes() -> Router<AppState> {
    Router::new()
        .route("/workflows", get(list_workflows).post(create_workflow))
        .route("/workflows/:id", get(get_workflow).put(update_workflow).delete(delete_workflow))
        .route("/workflows/:id/run", post(run_workflow))
        .route("/workflows/:id/export", get(export_workflow))
        .route("/workflows/import", post(import_workflow))
        .route("/workflows/:id/stream", get(stream_workflow_execution))
}

/// List all workflows
async fn list_workflows(State(state): State<AppState>) -> Json<Vec<WorkflowSummary>> {
    // ...
}

/// Create a new workflow
async fn create_workflow(
    State(state): State<AppState>,
    Json(workflow): Json<WorkflowDefinition>,
) -> Result<Json<WorkflowDefinition>, ApiError> {
    workflow.validate()?;
    // Store in database
    Ok(Json(workflow))
}

/// Run a workflow (returns run_id for streaming)
async fn run_workflow(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(input): Json<WorkflowInput>,
) -> Result<Json<RunResponse>, ApiError> {
    let run_id = Uuid::new_v4().to_string();
    
    // Start workflow execution in background
    tokio::spawn(async move {
        execute_workflow(&state.ctx, &id, &run_id, input).await;
    });
    
    Ok(Json(RunResponse { run_id }))
}

/// Stream workflow execution events (SSE)
async fn stream_workflow_execution(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let rx = state.workflow_events.subscribe(&id);
    
    let stream = BroadcastStream::new(rx).map(|event| {
        Ok(Event::default()
            .event("workflow_update")
            .data(serde_json::to_string(&event).unwrap()))
    });
    
    Sse::new(stream)
}

/// Export workflow to JSON
async fn export_workflow(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<WorkflowDefinition>, ApiError> {
    // Fetch and return full workflow definition
    Ok(Json(workflow))
}
```

#### WebSocket for Real-time Updates

```rust
// crates/beagle-websocket/src/workflow_handler.rs

/// Workflow execution events
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type")]
pub enum WorkflowEvent {
    Started { run_id: String, workflow_name: String },
    AgentStarted { agent_id: String, action: String },
    AgentProgress { agent_id: String, progress: f32, message: String },
    AgentCompleted { agent_id: String, output_preview: String },
    MessageStream { agent_id: String, delta: String },
    CheckpointCreated { checkpoint_id: String, phase: String },
    Error { message: String, recoverable: bool },
    Completed { run_id: String, final_output: String },
}

/// Handle workflow WebSocket connection
pub async fn handle_workflow_ws(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Path(run_id): Path<String>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| workflow_socket(socket, state, run_id))
}

async fn workflow_socket(
    socket: WebSocket,
    state: AppState,
    run_id: String,
) {
    let (mut sender, mut receiver) = socket.split();
    
    // Subscribe to workflow events
    let mut event_rx = state.workflow_events.subscribe(&run_id);
    
    // Send events to client
    let send_task = tokio::spawn(async move {
        while let Ok(event) = event_rx.recv().await {
            let msg = serde_json::to_string(&event).unwrap();
            if sender.send(Message::Text(msg)).await.is_err() {
                break;
            }
        }
    });
    
    // Handle client messages (e.g., pause, resume, cancel)
    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if let Message::Text(text) = msg {
                if let Ok(cmd) = serde_json::from_str::<WorkflowCommand>(&text) {
                    // Handle command
                }
            }
        }
    });
    
    tokio::select! {
        _ = send_task => {},
        _ = recv_task => {},
    }
}
```

### 3.3 UI Component Suggestions

For a future web UI (React/Vue/Svelte):

1. **Team Builder Canvas**
   - Drag-and-drop agents from sidebar
   - Connect agents with flow arrows
   - Configure agent properties in panel
   - Real-time validation feedback

2. **Playground**
   - Input field for queries
   - Live message streaming
   - Agent activity indicators
   - Checkpoint markers on timeline
   - Time travel slider

3. **Gallery**
   - Pre-built workflow templates
   - Community-shared workflows
   - One-click import

4. **Monitoring Dashboard**
   - LLM usage statistics
   - Cost tracking per workflow
   - Latency metrics
   - Error rates

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Create `crates/beagle-checkpoint` crate
- [ ] Implement `Checkpointer` trait and in-memory backend
- [ ] Add checkpoint tables to database schema
- [ ] Create `crates/beagle-signatures` for DSPy-style signatures

### Phase 2: Integration (Week 3-4)
- [ ] Integrate checkpointing into pipeline
- [ ] Implement PostgreSQL checkpointer
- [ ] Define Triad agent signatures
- [ ] Add REST API endpoints for workflows

### Phase 3: Optimization (Week 5-6)
- [ ] Implement `PromptOptimizer` for Triad tuning
- [ ] Add WebSocket streaming for workflow events
- [ ] Create workflow JSON import/export
- [ ] Build basic CLI for workflow management

### Phase 4: UI Foundation (Week 7-8)
- [ ] Design OpenAPI spec for workflow API
- [ ] Create workflow validation logic
- [ ] Implement basic web dashboard skeleton
- [ ] Add monitoring/metrics endpoints

---

## 5. References

### DSPy
- [DSPy Official Site](https://dspy.ai/)
- [Stanford NLP DSPy GitHub](https://github.com/stanfordnlp/dspy)
- [DSPy Prompt Optimization Guide](https://towardsdatascience.com/systematic-llm-prompt-engineering-using-dspy-optimization/)

### LangGraph
- [LangGraph Persistence Docs](https://docs.langchain.com/oss/python/langgraph/persistence)
- [langgraph-checkpoint PyPI](https://pypi.org/project/langgraph-checkpoint/)
- [LangGraph Architecture](https://medium.com/@shuv.sdr/langgraph-architecture-and-design-280c365aaf2c)

### AutoGen Studio
- [AutoGen Studio Introduction (Microsoft Research)](https://www.microsoft.com/en-us/research/blog/introducing-autogen-studio-a-low-code-interface-for-building-multi-agent-workflows/)
- [AutoGen Studio Documentation](https://microsoft.github.io/autogen/dev//user-guide/autogenstudio-user-guide/index.html)
- [AutoGen GitHub](https://github.com/microsoft/autogen)

---

*Document generated: 2025-11-29*
*BEAGLE Version: 0.10.x*
