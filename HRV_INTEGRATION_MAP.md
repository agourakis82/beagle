# HRV-Aware Strategy Selection - Integration Map

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         HRV Input Layer                              │
│  (HRV metrics from wearable/biometric source)                       │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    HRV State Tracker (NEW)                           │
│  • Current HRV zone (Low/Medium/High/VeryHigh)                      │
│  • Confidence level (0.0-1.0)                                       │
│  • Trend (improving/stable/degrading)                               │
│  • Last update timestamp                                            │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
    ┌────────┐  ┌────────┐  ┌────────────────┐
    │Config  │  │Metadata│  │Health Checks   │
    │Mgr     │  │Inject  │  │(Agent states)  │
    └────────┘  └────────┘  └────────────────┘
        │          │              │
        └──────────┼──────────────┘
                   │
    ┌──────────────▼──────────────┐
    │   COORDINATOR AGENT         │
    │  (Strategy Selection Layer)  │
    │                              │
    │  • Agent selection logic     │
    │  • Capability routing        │
    │  • Metadata injection        │
    │  • Quality threshold mgmt    │
    └──────────────┬───────────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
    ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│Retrieval     │ │Validation    │ │Quality       │
│Agent         │ │Agent         │ │Agent         │
│              │ │              │ │              │
│ContextRetv. │ │ FactCheck    │ │ Assessment   │
│ with HRV     │ │ with HRV     │ │ with HRV     │
│ confidence   │ │ override     │ │ thresholds   │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                        ▼
        ┌────────────────────────────────────┐
        │   RESEARCHER AGENT                 │
        │  (Dynamic Parameter Adjustment)    │
        │                                    │
        │  • QUALITY_THRESHOLD (dynamic)     │
        │  • MAX_REFINEMENTS (dynamic)       │
        │  • Paper search strategy           │
        │  • Temperature/tokens (LLM)        │
        │  • Reflexion loop control          │
        └────────────┬───────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────┐
        │   LLM Call Stack             │
        │ (Anthropic Client)           │
        │                              │
        │ • System prompt              │
        │ • Temperature                │
        │ • Max tokens                 │
        │ • Task type                  │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   Performance Feedback       │
        │ (PerformanceMonitor)         │
        │                              │
        │ • Query latency              │
        │ • Quality score              │
        │ • HRV zone at execution      │
        │ • Strategy used              │
        │ • Success/failure            │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   Learning Loop              │
        │ (ArchitectureEvolver)        │
        │                              │
        │ • HRV-performance correlations
        │ • Strategy efficacy per zone │
        │ • Parameter optimization     │
        │ • Evolution per HRV state    │
        └──────────────────────────────┘
```

---

## Integration Points - Detailed Hooks

### 1. COORDINATOR AGENT (Priority: HIGHEST)

**Current Location**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/coordinator.rs`

**Current Flow**:
```
Domain detection → Session → Context retrieval → LLM call 
  → Parallel agents → Aggregation
```

**Integration Points**:

#### Point A: Agent Selection (Line ~305)
```rust
// CURRENT
fn get_agent(&self, capability: AgentCapability) -> Option<Arc<dyn Agent>> {
    self.agents.iter().find(|agent| agent.capability() == capability)...
}

// PROPOSED HRV-AWARE
fn get_agent_for_hrv(&self, 
    capability: AgentCapability,
    hrv_state: &HRVState
) -> Option<Arc<dyn Agent>> {
    // Select agent based on HRV zone
    // e.g., High HRV → aggressive retrieval
    //       Low HRV → conservative retrieval
}
```

#### Point B: Metadata Injection (Line ~84-89)
```rust
// CURRENT
agent.execute(
    AgentInput::new(query.to_string())
        .with_metadata(json!({ "session_id": session_id.to_string() }))
)

// PROPOSED HRV-AWARE
agent.execute(
    AgentInput::new(query.to_string())
        .with_metadata(json!({
            "session_id": session_id.to_string(),
            "hrv_state": {
                "zone": hrv_state.zone.to_string(),
                "confidence": hrv_state.confidence,
                "trend": format!("{:?}", hrv_state.trend)
            },
            "quality_threshold": adaptive_quality_threshold(&hrv_state)
        }))
)
```

#### Point C: Quality Aggregation (Line ~241-248)
```rust
// CURRENT
let mut quality_score = quality...
if !is_supported { quality_score = (quality_score * 0.75).clamp(0.0, 1.0); }

// PROPOSED HRV-AWARE
let mut quality_score = quality...
let hr_adjustment = match hrv_state.zone {
    HRVZone::VeryLow => 0.6,   // More lenient
    HRVZone::Low => 0.75,
    HRVZone::Medium => 0.9,    // Standard
    HRVZone::High => 1.0,
    HRVZone::VeryHigh => 1.1,  // Stricter
};
if !is_supported { quality_score = (quality_score * hr_adjustment).clamp(0.0, 1.0); }
```

#### Point D: Research Result Tracking (Line ~281-302)
```rust
// PROPOSED HRV-AWARE - Add to ResearchResult
metrics.hrv_zone_when_executed = hrv_state.zone.to_string();
metrics.strategy_adaptation = strategy_name;
metrics.hrv_confidence = hrv_state.confidence;
```

---

### 2. RESEARCHER AGENT (Priority: HIGH)

**Current Location**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/researcher.rs`

**Current Hardcoded Values**:
```rust
const QUALITY_THRESHOLD: f32 = 0.7;  // Line 16
const MAX_REFINEMENTS: usize = 3;    // Line 19
```

**Integration Points**:

#### Point A: Dynamic Threshold (Line ~443-470)
```rust
// CURRENT
loop {
    if score >= QUALITY_THRESHOLD || refinement_iterations >= MAX_REFINEMENTS {
        break;
    }
    refinement_iterations += 1;
}

// PROPOSED HRV-AWARE
let (quality_threshold, max_refinements) = adaptive_thresholds(&hrv_state);
loop {
    if score >= quality_threshold || refinement_iterations >= max_refinements {
        break;
    }
    refinement_iterations += 1;
}

fn adaptive_thresholds(hrv: &HRVState) -> (f32, usize) {
    match hrv.zone {
        HRVZone::VeryLow => (0.5, 1),   // Accept faster
        HRVZone::Low => (0.6, 2),
        HRVZone::Medium => (0.7, 3),    // Standard
        HRVZone::High => (0.8, 4),
        HRVZone::VeryHigh => (0.85, 5), // Stricter
    }
}
```

#### Point B: LLM Call Adaptation (Line ~419-430)
```rust
// CURRENT
completion = self.anthropic.complete(CompletionRequest {
    model: ModelType::ClaudeHaiku45,
    messages: vec![Message::user(query)],
    max_tokens: 1200,
    temperature: 0.8,
    system: Some(system_prompt),
})

// PROPOSED HRV-AWARE
let (max_tokens, temperature) = adaptive_llm_params(&hrv_state);
completion = self.anthropic.complete(CompletionRequest {
    model: ModelType::ClaudeHaiku45,
    messages: vec![Message::user(query)],
    max_tokens,
    temperature,
    system: Some(system_prompt),
})

fn adaptive_llm_params(hrv: &HRVState) -> (u32, f32) {
    match hrv.zone {
        HRVZone::VeryLow => (800, 0.5),    // Shorter, deterministic
        HRVZone::Low => (1000, 0.6),
        HRVZone::Medium => (1200, 0.8),    // Standard
        HRVZone::High => (1400, 0.9),
        HRVZone::VeryHigh => (1500, 1.0),  // Longer, exploratory
    }
}
```

#### Point C: Paper Search Strategy (Line ~287-308)
```rust
// PROPOSED HRV-AWARE
let max_papers = match hrv_state.zone {
    HRVZone::VeryLow => 3,    // Minimal research overhead
    HRVZone::Low => 5,
    HRVZone::Medium => 10,    // Standard
    HRVZone::High => 15,
    HRVZone::VeryHigh => 20,  // Deep research
};
let papers = self.search_and_store_papers(query, max_papers).await...;
```

#### Point D: Critique Temperature (Line ~61-89)
```rust
// CURRENT
complete(CompletionRequest {
    temperature: 0.3,  // Low for consistency
    ...
})

// PROPOSED HRV-AWARE
let critique_temp = match hrv.zone {
    HRVZone::VeryLow => 0.1,  // Very strict critique
    HRVZone::Low => 0.2,
    HRVZone::Medium => 0.3,   // Standard
    HRVZone::High => 0.4,
    HRVZone::VeryHigh => 0.5, // Exploratory critique
};
```

---

### 3. SPECIALIZED AGENTS (Priority: MEDIUM-HIGH)

**Retrieval Agent** (`specialized_agents.rs` Line ~39-75)
```rust
// CURRENT
confidence: if context_chunks.is_empty() { 0.3 } else { 0.9 },

// PROPOSED HRV-AWARE
let retrieval_aggressiveness = match hrv.zone {
    HRVZone::VeryLow => (0.5, 3),   // (min_confidence, max_chunks)
    HRVZone::Low => (0.6, 4),
    HRVZone::Medium => (0.7, 6),    // Standard
    HRVZone::High => (0.8, 8),
    HRVZone::VeryHigh => (0.9, 12),
};
confidence: if context_chunks.is_empty() { 
    retrieval_aggressiveness.0 * 0.5 
} else { 
    retrieval_aggressiveness.0 
}
```

**Validation Agent** (`specialized_agents.rs` Line ~103-157)
```rust
// CURRENT - Just YES/NO validation
is_supported: normalized.contains("YES")

// PROPOSED HRV-AWARE - Confidence threshold
let validation_confidence_threshold = match hrv.zone {
    HRVZone::VeryLow => 0.95,  // Require very sure
    HRVZone::Low => 0.85,
    HRVZone::Medium => 0.75,   // Standard
    HRVZone::High => 0.65,
    HRVZone::VeryHigh => 0.5,  // Accept more edge cases
};
```

**Quality Agent** (`specialized_agents.rs` Line ~185-237)
```rust
// PROPOSED HRV-AWARE - Adjust quality floor
let quality_floor = match hrv.zone {
    HRVZone::VeryLow => 0.4,   // Accept lower quality
    HRVZone::Low => 0.5,
    HRVZone::Medium => 0.6,    // Standard
    HRVZone::High => 0.7,
    HRVZone::VeryHigh => 0.8,  // Expect higher
};
let score = llm_response...parse::<f32>()...
    .max(quality_floor);  // NEW: floor by HRV
```

---

### 4. ADVERSARIAL STRATEGY EVOLUTION (Priority: MEDIUM)

**Location**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/adversarial/`

#### Integration Point A: Tournament Fitness (arena.rs)
```rust
// PROPOSED HRV-AWARE
pub fn evaluate_fitness(
    match_result: &MatchResult,
    hrv_stability: f64,  // NEW: HRV feedback
) -> f64 {
    let base_fitness = match_result.elo_rating_delta;
    let hrv_bonus = if hrv_stability > 0.7 { 1.2 } else { 0.8 };
    base_fitness * hrv_bonus
}
```

#### Integration Point B: Strategy Mutation (strategy.rs)
```rust
// PROPOSED HRV-AWARE
pub fn mutate_for_hrv(&self, hrv_zone: &HRVZone) -> Self {
    let mut new_params = self.parameters.clone();
    
    // Different mutation ranges based on HRV zone
    let mutation_range = match hrv_zone {
        HRVZone::VeryLow => 0.05,   // Small changes
        HRVZone::Low => 0.1,
        HRVZone::Medium => 0.2,     // Standard
        HRVZone::High => 0.3,
        HRVZone::VeryHigh => 0.4,   // Larger exploration
    };
    
    for value in new_params.values_mut() {
        let delta = (rand::random::<f64>() - 0.5) * mutation_range;
        *value = (*value + delta).clamp(0.0, 1.0);
    }
    
    Self { /* ... */ parameters: new_params }
}
```

---

### 5. PERFORMANCE MONITORING (Priority: MEDIUM)

**Location**: `/mnt/e/workspace/beagle-remote/crates/beagle-agents/src/metacognitive/monitor.rs`

#### Extended QueryPerformance Structure
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
    // NEW: HRV correlation fields
    pub hrv_zone_when_executed: Option<String>,
    pub hrv_confidence_when_executed: Option<f64>,
    pub strategy_used: Option<String>,
    pub agent_pool_size: Option<usize>,
}
```

#### New Analysis Methods
```rust
impl PerformanceMonitor {
    // NEW: Correlation analysis
    pub fn hrv_quality_correlation(&self, zone: &str, last_n: usize) -> f64 {
        let recent = self.get_recent(last_n);
        recent.iter()
            .filter(|p| p.hrv_zone_when_executed.as_ref() == Some(&zone.to_string()))
            .map(|p| p.quality_score)
            .sum::<f64>() / recent.len() as f64
    }
    
    // NEW: Strategy effectiveness
    pub fn strategy_success_rate(&self, strategy: &str) -> f64 {
        let relevant: Vec<_> = self.history.iter()
            .filter(|p| p.strategy_used.as_ref() == Some(&strategy.to_string()))
            .collect();
        
        if relevant.is_empty() { return 0.5; }
        relevant.iter().filter(|p| p.success).count() as f64 / relevant.len() as f64
    }
}
```

---

## Data Flow - HRV to Strategy Decision

```
Step 1: HRV Measurement
├─ Biometric source (wearable, pulse monitor)
├─ Compute HRV metrics (RMSSD, HF/LF ratio, etc.)
└─ Determine zone (VeryLow/Low/Medium/High/VeryHigh)
    + confidence (0.0-1.0)

Step 2: State Update
├─ HRVStateTracker.update(zone, confidence, trend)
└─ Timestamp update, history tracking

Step 3: Config Selection
├─ Look up HRVConfig[zone] → get parameter overrides
├─ Fetch: quality_threshold, max_refinements, temp, tokens, etc.
└─ Return effective configuration

Step 4: Agent Invocation
├─ Coordinator selects agents based on HRV
├─ Injects HRV context in metadata
├─ Routes to appropriate agent specialization
└─ Executes with HRV-aware parameters

Step 5: Execution Tracking
├─ ResearchMetrics captures HRV state at execution
├─ PerformanceMonitor records outcome
└─ Stores: zone, strategy, quality, success, latency

Step 6: Learning Loop
├─ PerformanceMonitor.analyze_hrv_correlations()
├─ Identify which strategies work best per zone
├─ ArchitectureEvolver updates strategy parameters
└─ Feeds back into HRVConfig for next execution
```

---

## New Module Structure (hrv_aware/)

```
crates/beagle-agents/src/hrv_aware/
├─ mod.rs                    # Module exports
├─ state.rs                  # HRVStateTracker, HRVState, HRVZone
├─ config.rs                 # HRVConfig, parameter mappings
├─ selector.rs               # HRVStrategySelector trait
├─ correlation.rs            # HRV-performance analysis
└─ integration.rs            # Helper functions for CoordinatorAgent
```

### state.rs
```rust
#[derive(Debug, Clone, Copy)]
pub enum HRVZone {
    VeryLow,    // Stress/fatigue: RMSSD < 20ms
    Low,        // Mild stress: RMSSD 20-30ms
    Medium,     // Normal: RMSSD 30-50ms
    High,       // Good recovery: RMSSD 50-100ms
    VeryHigh,   // Excellent recovery: RMSSD > 100ms
}

#[derive(Debug, Clone)]
pub struct HRVState {
    pub zone: HRVZone,
    pub confidence: f64,  // 0.0-1.0
    pub trend: HRVTrend,
    pub last_update: DateTime<Utc>,
    pub rmssd_ms: Option<f64>,  // Raw metric
    pub lf_hf_ratio: Option<f64>,
}

#[derive(Debug, Clone, Copy)]
pub enum HRVTrend {
    Improving,
    Stable,
    Degrading,
}

pub struct HRVStateTracker {
    current_state: Arc<Mutex<HRVState>>,
    history: Vec<HRVState>,
}
```

### config.rs
```rust
pub struct HRVConfig {
    pub zone_thresholds: HashMap<HRVZone, ParameterSet>,
}

pub struct ParameterSet {
    pub quality_threshold: f32,
    pub max_refinements: usize,
    pub llm_max_tokens: u32,
    pub llm_temperature: f32,
    pub paper_search_max: usize,
    pub retrieval_confidence_floor: f32,
    pub validation_confidence_threshold: f32,
    pub agent_parallelism: usize,
}

impl Default for HRVConfig {
    fn default() -> Self {
        // Pre-configured sensible defaults for each zone
    }
}
```

---

## Testing Strategy

### Unit Tests
- HRVState transitions and zone detection
- Parameter selection from HRVConfig
- Metadata injection correctness
- Agent health status based on HRV

### Integration Tests
- Full flow with HRV state injected
- Verify PerformanceMonitor captures HRV context
- Check ResearchMetrics includes HRV fields
- Validate ArchitectureEvolver adjusts strategies

### Regression Tests
- Ensure non-HRV code paths unaffected
- Performance benchmarks by HRV zone
- Verify backward compatibility with existing API

---

## Rollout Plan

1. **Week 1**: Core infrastructure (state, config modules)
2. **Week 2**: CoordinatorAgent integration
3. **Week 3**: ResearcherAgent parameter adaptation
4. **Week 4**: Specialized agents HRV-aware thresholds
5. **Week 5**: Performance monitoring & correlation analysis
6. **Week 6**: Strategy evolution with HRV fitness
7. **Week 7**: Testing, benchmarking, documentation
8. **Week 8**: Production rollout & monitoring

