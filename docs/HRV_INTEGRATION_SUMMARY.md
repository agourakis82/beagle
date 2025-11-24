# Beagle-Agents Crate Architecture Analysis
## Summary for HRV-Aware Strategy Selection Integration

---

## 1. MAIN LIB.RS STRUCTURE & KEY EXPORTS

### File Location
`/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/lib.rs`

### Core Module Organization
- **Agent Infrastructure**: `agent_trait`, `coordinator`, `models`, `researcher`, `specialized_agents`
- **Disruptive Techniques (v1.0)**: `debate`, `reasoning`, `causal`
- **Revolutionary Techniques (v2.0)**: `deep_research`, `swarm`, `temporal`, `metacognitive`, `neurosymbolic`, `quantum`, `quantum_mcts`, `adversarial`

### Key Exports
```rust
pub use agent_trait::{Agent, AgentCapability, AgentHealth, AgentInput, AgentOutput};
pub use coordinator::CoordinatorAgent;
pub use models::{ResearchMetrics, ResearchResult, ResearchStep};
pub use researcher::ResearcherAgent;
pub use specialized_agents::{QualityAgent, RetrievalAgent, ValidationAgent};
pub use adversarial::{
    Strategy, ResearchApproach, CompetitionArena, MetaLearner, ...
};
```

---

## 2. AGENT TRAIT DEFINITION

### File Location
`/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/agent_trait.rs`

### Core Trait (76 lines)
```rust
#[async_trait]
pub trait Agent: Send + Sync {
    fn id(&self) -> &str;
    fn capability(&self) -> AgentCapability;
    async fn execute(&self, input: AgentInput) -> Result<AgentOutput>;
    async fn health_check(&self) -> AgentHealth { AgentHealth::Healthy }
}
```

### Agent Capabilities Enum
```rust
pub enum AgentCapability {
    ContextRetrieval,
    FactChecking,
    QualityAssessment,
    ResponseGeneration,
    Coordination,
    Synthesis,
}
```

### Input/Output Structures
```rust
pub struct AgentInput {
    pub query: String,
    pub context: Vec<String>,
    pub metadata: Value,  // Flexible metadata carrier
}

pub struct AgentOutput {
    pub agent_id: String,
    pub result: Value,
    pub confidence: f32,
    pub duration_ms: u64,
    pub metadata: Value,
}

pub enum AgentHealth {
    Healthy,
    Degraded,
    Unhealthy,
}
```

### Key Design Pattern
- **Async-first**: Uses `async_trait` for async execution
- **Flexible metadata**: JSON `Value` enables adding arbitrary state
- **Health monitoring**: Built-in health check capability
- **Compositional**: Agents register capabilities, not specific behavior

---

## 3. COORDINATOR AGENT

### File Location
`/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/coordinator.rs`

### Structure (312 lines)
```rust
pub struct CoordinatorAgent {
    anthropic: Arc<AnthropicClient>,
    personality: Arc<PersonalityEngine>,
    context_bridge: Arc<ContextBridge>,
    agents: Vec<Arc<dyn Agent>>,  // Registered agents
}
```

### Multi-Agent Orchestration Workflow

#### Registration Pattern
```rust
pub fn register_agent(mut self, agent: Arc<dyn Agent>) -> Self {
    self.agents.push(agent);
    self
}
```

#### Research Flow
1. **Domain Detection** (~49ms): Uses PersonalityEngine to identify query domain
2. **Session Management** (~70ms): Creates/reuses conversation session
3. **Context Retrieval** (~82-110ms): Parallel retrieval from ContextBridge
   - Triggered via RetrievalAgent (ContextRetrieval capability)
4. **System Prompt Composition** (~114-125ms): Combines personality + context
5. **Primary LLM Call** (~128-139ms): AnthropicClient completion
6. **Parallel Specialized Agents** (~148-204ms): JoinSet-based concurrent execution
   - FactChecking agent (ValidationAgent)
   - QualityAssessment agent (QualityAgent)
   - Both execute in parallel via `tokio::task::JoinSet`
7. **Metric Aggregation**: Quality score clamped if validation fails
8. **Persistence** (~250-280ms): Stores turn in ContextBridge

### Key Parallelism Pattern
```rust
let mut join_set = JoinSet::new();
for agent in &self.agents {
    match capability {
        AgentCapability::FactChecking | AgentCapability::QualityAssessment => {
            let agent = Arc::clone(agent);
            join_set.spawn(async move { /* execute */ });
        }
        _ => {}
    }
}

while let Some(result) = join_set.join_next().await {
    // Handle results as they complete
}
```

### Current Strategy Selection
**None explicit** - Uses fixed domain detection and single research flow

---

## 4. RESEARCH-RELATED AGENTS

### ResearcherAgent (574 lines)
**File**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/researcher.rs`

#### Capabilities
- Self-RAG (Retrieval-Augmented Generation) in series
- Paper search (PubMed + arXiv with Neo4j storage)
- Reflexion loop (critique → refine → iterate)
- Quality thresholds: `QUALITY_THRESHOLD = 0.7`, `MAX_REFINEMENTS = 3`

#### Workflow
1. Domain detection
2. Scientific paper search & storage
3. Session/context retrieval
4. System prompt composition
5. **Main LLM call**
6. **Reflexion loop**:
   - Critique answer using LLM as critic
   - Calculate quality score from critique
   - Refine if score < 0.7 (up to 3 iterations)
7. Persist conversation turn

#### Quality Assessment Method
```rust
// Parse "SCORE: [0.0-1.0]" from critic response
// Fallback: count positive/negative words
// Formula: ((pos_count - neg_count) / 10.0 + 0.5).clamp(0.0, 1.0)
```

### Specialized Agents (238 lines)
**File**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/specialized_agents.rs`

#### RetrievalAgent
- **Capability**: ContextRetrieval
- **Input**: session_id in metadata
- **Output**: 6 most recent conversation turns
- **Confidence**: 0.9 if chunks found, 0.3 otherwise

#### ValidationAgent
- **Capability**: FactChecking
- **Method**: LLM-based fact-checking against context
- **Prompt**: "Is answer supported by context? YES or NO"
- **Output**: `is_supported` boolean

#### QualityAgent
- **Capability**: QualityAssessment
- **Method**: LLM rates response 0.0-1.0
- **Prompt**: "Rate quality 0.0-1.0. Answer ONLY with the number."
- **Output**: Parsed floating-point score

---

## 5. CURRENT DEPENDENCIES

### File Location
`/mnt/e/workspace/beagle-remote/crates/beagle-agents/Cargo.toml`

#### Core Dependencies
```toml
anyhow = "1.0"              # Error handling
thiserror = "1.0"           # Custom errors
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"          # JSON metadata carrier
tokio = { version = "1.35", features = ["full"] }  # Async runtime
async-trait = "0.1"         # Async trait support

# Internal Integration Points
beagle-llm = { path = "../beagle-llm" }
beagle-personality = { path = "../beagle-personality" }
beagle-memory = { path = "../beagle-memory" }
beagle-hypergraph = { path = "../beagle-hypergraph" }
beagle-search = { path = "../beagle-search" }
beagle-core = { path = "../beagle-core" }

# Time & IDs
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1.6", features = ["v4", "serde"] }

# Logging
tracing = "0.1"

# Math & Numerics
num-complex = "0.4"
rand = "0.8"

# HTTP
reqwest = { version = "0.11", features = ["json"] }
urlencoding = "2.1"
```

### State/Configuration Pattern in Beagle Ecosystem

**beagle-server** implements pattern for reference:
```rust
pub struct Config {
    host: String,
    port: u16,
    database_url: String,
    // ... loaded from env via config crate
}

pub struct AppState {
    // Immutable shared state
    pub storage: Arc<CachedPostgresStorage>,
    anthropic_client: Option<Arc<AnthropicClient>>,
    // ... all agents and systems
    performance_monitor: Arc<Mutex<PerformanceMonitor>>,
    // ... event infrastructure
}
```

### No Existing State/Config in beagle-agents
- beagle-agents is **library crate** (no config loading)
- All configuration passed via constructors/method arguments
- **Flexibility point**: Easy to add HRV config layer

---

## 6. STRATEGY SELECTION INFRASTRUCTURE

### Current Strategy Pattern
**File**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/adversarial/strategy.rs`

```rust
pub struct Strategy {
    pub name: String,
    pub approach: ResearchApproach,
    pub parameters: HashMap<String, f64>,
}

pub enum ResearchApproach {
    Aggressive,   // boldness=0.9, risk_tolerance=0.8
    Conservative, // boldness=0.3, risk_tolerance=0.2
    Exploratory,  // boldness=0.7, novelty_seeking=0.9, randomness=0.6
    Exploitative, // boldness=0.5, refinement=0.8, consistency=0.9
}
```

### Evolution Pattern
- **Mutation**: Random ±0.1 adjustments to parameters
- **Crossover**: Blend parents' parameters
- Used by MetaLearner and CompetitionArena for strategy improvement

### MCTS Engine Integration
**File**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/deep_research/mcts.rs`

```rust
pub struct MCTSEngine {
    llm: Arc<AnthropicClient>,
    simulator: Arc<SimulationEngine>,
    puct: PUCTSelector,
    iterations: usize,
    max_depth: usize,
}
```

- No strategy selection logic, pure tree search
- Could be extended with context-aware iteration/depth parameters

---

## 7. PERFORMANCE MONITORING & STATE TRACKING

### PerformanceMonitor Structure
**File**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/metacognitive/monitor.rs`

```rust
pub struct QueryPerformance {
    pub query_id: Uuid,
    pub query: String,
    pub domain: String,
    pub latency_ms: u64,
    pub quality_score: f64,
    pub user_satisfaction: Option<f64>,
    pub timestamp: DateTime<Utc>,
    pub success: bool,
    pub error: Option<String>,
}

pub struct PerformanceMonitor {
    history: Vec<QueryPerformance>,
    max_history: usize,
}

impl PerformanceMonitor {
    pub fn new(max_history: usize) -> Self { /* ... */ }
    pub fn record(&mut self, performance: QueryPerformance) { /* ... */ }
    pub fn get_recent(&self, n: usize) -> &[QueryPerformance] { /* ... */ }
    pub fn get_failures(&self, n: usize) -> Vec<&QueryPerformance> { /* ... */ }
    pub fn success_rate(&self, last_n: usize) -> f64 { /* ... */ }
    pub fn average_quality(&self, last_n: usize) -> f64 { /* ... */ }
}
```

### Key Exports from Metacognitive Module
```rust
pub use analyzer::{FailurePattern, PatternCluster, WeaknessAnalyzer};
pub use evolver::{AgentSpecification, ArchitectureEvolver};
pub use monitor::{
    PerformanceBottleneck, PerformanceDegradation, PerformanceMonitor,
    PerformanceTrend, QueryPerformance, DegradationSeverity, TrendDirection
};
pub use specialized::SpecializedAgentFactory;
```

---

## 8. MODELS & METRICS DEFINITIONS

### File Location
`/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/models.rs` (35 lines)

```rust
pub struct ResearchStep {
    pub step_number: usize,
    pub action: String,
    pub result: String,
    pub duration_ms: u64,
}

pub struct ResearchMetrics {
    pub total_duration_ms: u64,
    pub llm_calls: usize,
    pub context_chunks_retrieved: usize,
    pub refinement_iterations: usize,
    pub quality_score: f32,
}

pub struct ResearchResult {
    pub answer: String,
    pub domain: Domain,
    pub steps: Vec<ResearchStep>,
    pub metrics: ResearchMetrics,
    pub session_id: Uuid,
    pub sources: Option<Vec<String>>,
}
```

---

## 9. INTEGRATION POINTS FOR HRV-AWARE STRATEGY SELECTION

### Entry Points (Priority Order)

#### 1. **CoordinatorAgent::research()** (HIGHEST PRIORITY)
- **Current**: Fixed single-path workflow
- **Opportunity**: Select agent composition based on HRV metrics
- **Implementation location**: Before agent registration/execution loop
- **Hooks**: 
  - Add HRV metrics to `metadata: Value`
  - Switch agent selection in `get_agent()` method
  - Modify quality threshold based on HRV state

#### 2. **ResearcherAgent::research()** (HIGH PRIORITY)
- **Current**: Fixed critique → refine loop with hardcoded thresholds
- **Opportunity**: Adjust `QUALITY_THRESHOLD` and `MAX_REFINEMENTS` based on HRV
- **Implementation location**: Before quality loop or as runtime parameters
- **Hooks**:
  - Pass HRV state to `critique_answer()` method
  - Dynamically adjust temperature/max_tokens in LLM calls
  - Modify paper search strategy (max_results) based on HRV

#### 3. **Strategy Evolution in Adversarial Module** (MEDIUM PRIORITY)
- **Current**: Genetic algorithm for strategy mutation/crossover
- **Opportunity**: Use HRV as fitness function alongside tournament results
- **Implementation location**: `adversarial/evolution.rs`
- **Hooks**:
  - Incorporate HRV stability into elo_rating calculations
  - Weight strategy selection by HRV responsiveness

#### 4. **MCTSEngine Configuration** (MEDIUM PRIORITY)
- **Current**: Fixed iterations and max_depth
- **Opportunity**: Adjust exploration/exploitation based on HRV
- **Implementation location**: Constructor or new method
- **Hooks**:
  - Scale iterations based on HRV confidence
  - Adjust PUCT exploration constant

#### 5. **Agent Health Checks** (LOW-MEDIUM PRIORITY)
- **Current**: Stub returning Healthy
- **Opportunity**: Integrate HRV degradation signals
- **Implementation location**: Each agent's `health_check()` override
- **Hooks**:
  - Return `AgentHealth::Degraded` when HRV indicates stress
  - Trigger fallback strategies

---

## 10. RECOMMENDED INTEGRATION ARCHITECTURE

### Phase 1: Core Infrastructure (Foundation)
1. **New Module**: `beagle-agents/src/hrv_aware/mod.rs`
   - HRVStateTracker: Holds current HRV metrics
   - HRVConfig: Strategy parameters indexed by HRV zones
   - HRVStrategySelector: Trait for pluggable selection algorithms

2. **Extend AgentInput Metadata**
   ```rust
   // In AgentInput, pass HRV context
   metadata: {
       "hrv_state": { "zone": "High", "confidence": 0.85 },
       "strategy_hint": "conservative"
   }
   ```

3. **Modify ResearchMetrics**
   ```rust
   // Track HRV alignment
   pub hrv_zone_when_executed: String,
   pub strategy_adaptation: String,
   ```

### Phase 2: Agent-Level Integration
1. **CoordinatorAgent**: Pluggable strategy selector
2. **ResearcherAgent**: Dynamic parameter adjustment
3. **Specialized Agents**: HRV-aware confidence/quality thresholds

### Phase 3: System Integration
1. **PerformanceMonitor**: Track HRV → performance correlations
2. **ArchitectureEvolver**: Evolve strategies per HRV zone
3. **CompetitionArena**: Evaluate strategies under HRV conditions

---

## 11. KEY DESIGN CONSIDERATIONS

### Strengths to Leverage
1. **Async-first architecture**: HRV updates won't block execution
2. **Compositional agents**: Easy to add HRV-aware variants
3. **Metadata carrier (JSON Value)**: Flexible HRV state propagation
4. **JoinSet parallelism**: Can distribute agent execution by HRV confidence
5. **PerformanceMonitor exists**: Foundation for HRV correlation tracking
6. **Strategy enum**: Already supports multiple approaches

### Challenges to Address
1. **No configuration system**: Need to add HRV config loading
2. **Fixed thresholds throughout**: `QUALITY_THRESHOLD = 0.7` hardcoded in multiple places
3. **Sequential coordinator flow**: Could benefit from HRV-aware parallelism tuning
4. **No feedback mechanism**: Missing path from outcomes back to strategy selection
5. **Agent registration is immutable**: Consider runtime agent pool swapping

### Recommended Patterns
1. **Use `Arc<Mutex<HRVStateTracker>>`** for shared, mutable HRV state
2. **Extend metadata early** in agent execution pipeline
3. **Create HRV-aware trait implementations** alongside existing agents
4. **Implement PerformanceMonitor recording** at each strategy decision point
5. **Use builder pattern** for dynamic agent/strategy composition

---

## 12. FILES SUMMARY TABLE

| File | Lines | Key Type | Purpose |
|------|-------|----------|---------|
| lib.rs | 176 | Module | Core exports and module organization |
| agent_trait.rs | 76 | Trait | Base Agent interface and capability enum |
| coordinator.rs | 312 | Struct | Multi-agent orchestrator with parallel execution |
| researcher.rs | 574 | Struct | Sequential RAG with reflexion loop |
| specialized_agents.rs | 238 | Struct | RetrievalAgent, ValidationAgent, QualityAgent |
| models.rs | 35 | Struct | ResearchStep, ResearchMetrics, ResearchResult |
| adversarial/strategy.rs | 100+ | Struct/Enum | Strategy, ResearchApproach, mutation/crossover |
| deep_research/mcts.rs | 100+ | Struct | MCTSEngine for hypothesis discovery |
| metacognitive/monitor.rs | 380+ | Struct | PerformanceMonitor, QueryPerformance tracking |
| metacognitive/mod.rs | 24 | Module | Analyzer, Evolver, Monitor exports |
| Cargo.toml | 45 | Config | Dependencies (tokio, serde, beagle-* crates) |

---

## CONCLUSION

The beagle-agents crate provides:
- **Strong foundation**: Async traits, agent composition, parallelism
- **Existing monitoring**: PerformanceMonitor with historical tracking
- **Strategy infrastructure**: Adversarial module with evolution support
- **Clear integration points**: Metadata carrier, health checks, capability registry

**HRV integration should focus on**:
1. Pluggable strategy selection in CoordinatorAgent
2. Dynamic parameter adjustment in ResearcherAgent
3. HRV state propagation via metadata
4. Performance correlation tracking in PerformanceMonitor
5. Strategy evolution weighted by HRV stability

**No architectural changes needed** - existing patterns support HRV integration cleanly.

