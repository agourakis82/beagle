# HRV-Aware Strategy Selection - Integration Map (v2.0)

**Status**: Detailed integration guide for HRV implementation
**Technical Foundation**: Solid, non-breaking architecture
**Validation Status**: Ready for implementation; effectiveness TBD

---

## System Architecture

```
┌──────────────────────────────────────────────────────────┐
│              HRV Input Layer (iOS HealthKit)              │
│  • RMSSD measurement (ms)                                │
│  • Confidence score (0.0-1.0)                            │
│  • Trend (improving/stable/degrading)                    │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────┐
│           HRV State Tracker (NEW MODULE)                  │
│  • Zone classification (VeryLow/Low/Medium/High/VeryHigh)│
│  • Confidence tracking                                    │
│  • Trend monitoring                                       │
└────────────────────┬─────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
   ┌─────────┐ ┌──────────┐ ┌──────────────┐
   │  Config │ │ Metadata │ │ Health Checks│
   │ Manager │ │ Injection│ │(Agent states)│
   └─────────┘ └──────────┘ └──────────────┘
        │            │            │
        └────────────┼────────────┘
                     │
      ┌──────────────▼──────────────┐
      │  COORDINATOR AGENT          │
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
│ Retrieval    │ │ Validation   │ │ Quality      │
│ Agent        │ │ Agent        │ │ Agent        │
│ (with HRV)   │ │ (with HRV)   │ │ (with HRV)   │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                        ▼
        ┌────────────────────────────────┐
        │   RESEARCHER AGENT             │
        │  (Dynamic Param Adjustment)    │
        │                                │
        │  • QUALITY_THRESHOLD (dynamic) │
        │  • MAX_REFINEMENTS (dynamic)   │
        │  • Temperature/tokens (LLM)    │
        │  • Paper search depth          │
        └────────────┬───────────────────┘
                     │
                     ▼
        ┌──────────────────────────────┐
        │   LLM Call Stack             │
        │ (Anthropic Client)           │
        │                              │
        │ • System prompt              │
        │ • Temperature (HRV-adjusted) │
        │ • Max tokens (HRV-adjusted)  │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   Performance Feedback       │
        │ (PerformanceMonitor)         │
        │                              │
        │ • Query latency              │
        │ • Quality score              │
        │ • HRV zone at execution ✓    │
        │ • Strategy used ✓            │
        │ • Success/failure            │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   Analytics & Learning       │
        │ (HRV-Performance Correlations)
        │                              │
        │ • Zone effectiveness tracker │
        │ • Strategy success by zone   │
        │ • Parameter optimization     │
        │ (future validation study)    │
        └──────────────────────────────┘
```

---

## Integration Point 1: COORDINATOR AGENT (HIGHEST Priority)

**File**: `/crates/beagle-agents/src/coordinator.rs`
**Scope**: Agent selection + metadata injection + quality management
**Risk**: LOW (non-breaking metadata enrichment)

### Current Flow (Lines 84-305)

```
Domain detection → Session → Context retrieval → LLM call
  → Parallel agents → Aggregation → Persistence
```

### Integration Point 1A: Agent Selection (Line ~305)

**Current Code**:
```rust
fn get_agent(&self, capability: AgentCapability) -> Option<Arc<dyn Agent>> {
    self.agents.iter().find(|agent| agent.capability() == capability)
        .map(|agent| Arc::clone(agent))
}
```

**Enhanced with HRV**:
```rust
fn get_agent_for_hrv(
    &self,
    capability: AgentCapability,
    hrv_state: &HRVState
) -> Option<Arc<dyn Agent>> {
    // First: find agents matching capability
    let candidates: Vec<_> = self.agents.iter()
        .filter(|agent| agent.capability() == capability)
        .collect();

    if candidates.is_empty() {
        return None;
    }

    // Then: select based on HRV zone
    // Currently just return first match (baseline)
    // Future: could select variant agents for different HRV zones
    candidates.first().map(|agent| Arc::clone(agent))
}
```

**Non-Breaking Pattern**:
- If HRV state unavailable → use existing `get_agent()` method
- If HRV available → use `get_agent_for_hrv()` for potential optimization
- Existing behavior preserved either way

### Integration Point 1B: Metadata Injection (Lines 84-89)

**Current Code**:
```rust
agent.execute(
    AgentInput::new(query.to_string())
        .with_metadata(json!({
            "session_id": session_id.to_string()
        }))
)
```

**Enhanced with HRV**:
```rust
let hrv_metadata = if let Some(hrv_state) = &self.hrv_state_tracker {
    json!({
        "hrv_zone": hrv_state.zone.to_string(),
        "hrv_confidence": hrv_state.confidence,
        "hrv_trend": hrv_state.trend.to_string(),
        "session_id": session_id.to_string(),
    })
} else {
    json!({
        "session_id": session_id.to_string(),
    })
};

agent.execute(
    AgentInput::new(query.to_string())
        .with_metadata(hrv_metadata)
)
```

**Why This Works**:
- Metadata is already JSON Value type (flexible)
- Backward compatible (agents that ignore HRV fields work unchanged)
- Non-breaking for existing agent implementations

### Integration Point 1C: Quality Aggregation (Lines 241-248)

**Current Code**:
```rust
// Aggregate quality from specialized agents
let mut quality_score = base_score;
for result in results {
    match result.confidence {
        confidence if confidence < 0.3 => {
            quality_score *= 0.8;  // Penalize low confidence
        }
        _ => {}
    }
}
```

**Enhanced with HRV**:
```rust
// HRV-aware quality aggregation
let quality_floor = match hrv_state.zone {
    HRVZone::VeryLow => 0.50,   // Accept lower quality when stressed
    HRVZone::Low => 0.60,
    HRVZone::Medium => 0.70,    // Current baseline
    HRVZone::High => 0.80,
    HRVZone::VeryHigh => 0.85,
};

let mut quality_score = base_score.max(quality_floor);
// Rest of aggregation logic...
```

**Non-Breaking**:
- Only used if HRV state available
- Defaults to Medium zone (current behavior) if HRV disabled
- Can be toggled via feature flag

---

## Integration Point 2: RESEARCHER AGENT (HIGH Priority)

**File**: `/crates/beagle-agents/src/researcher.rs`
**Scope**: Dynamic parameter adaptation
**Risk**: LOW (parameters have reasonable defaults)

### Current Constants (Lines 16-19)

```rust
const QUALITY_THRESHOLD: f32 = 0.7;
const MAX_REFINEMENTS: usize = 3;
const LLM_TEMPERATURE: f32 = 0.8;
const MAX_TOKENS: u32 = 1200;
```

### Enhanced with HRV

```rust
struct ResearchParameters {
    quality_threshold: f32,
    max_refinements: usize,
    llm_temperature: f32,
    max_tokens: u32,
    paper_search_max: usize,
}

fn get_parameters_for_hrv(hrv_zone: &HRVZone) -> ResearchParameters {
    match hrv_zone {
        HRVZone::VeryLow => ResearchParameters {
            quality_threshold: 0.50,  // Accept faster completion
            max_refinements: 1,        // One pass
            llm_temperature: 0.5,      // More focused
            max_tokens: 800,           // Shorter responses
            paper_search_max: 3,       // Quick search
        },
        HRVZone::Low => ResearchParameters {
            quality_threshold: 0.60,
            max_refinements: 2,
            llm_temperature: 0.6,
            max_tokens: 1000,
            paper_search_max: 5,
        },
        HRVZone::Medium => ResearchParameters {
            quality_threshold: 0.70,   // Current defaults
            max_refinements: 3,
            llm_temperature: 0.8,
            max_tokens: 1200,
            paper_search_max: 8,
        },
        HRVZone::High => ResearchParameters {
            quality_threshold: 0.80,   // More thorough
            max_refinements: 4,
            llm_temperature: 0.85,
            max_tokens: 1400,
            paper_search_max: 12,
        },
        HRVZone::VeryHigh => ResearchParameters {
            quality_threshold: 0.85,
            max_refinements: 5,
            llm_temperature: 0.9,
            max_tokens: 1500,
            paper_search_max: 15,
        },
    }
}
```

**Important Note on Zone Mappings**:
These parameter sets are **exploratory**. No validation that:
- These specific thresholds improve outcomes
- These combinations are optimal
- The mappings generalize to other users/tasks

Would require validation studies to confirm effectiveness.

### Usage in ResearcherAgent

```rust
pub async fn research(&self, input: AgentInput) -> Result<AgentOutput> {
    // Get HRV state from metadata if available
    let hrv_zone = input.metadata
        .get("hrv_zone")
        .and_then(|z| z.as_str())
        .and_then(|z| HRVZone::from_str(z).ok())
        .unwrap_or(HRVZone::Medium);  // Default fallback

    // Get parameters for this zone
    let params = get_parameters_for_hrv(&hrv_zone);

    // Use dynamic parameters throughout
    let quality_threshold = params.quality_threshold;
    let max_refinements = params.max_refinements;

    // ... rest of research logic using these values
}
```

---

## Integration Point 3: SPECIALIZED AGENTS (MED-HIGH Priority)

**Files**: `/crates/beagle-agents/src/specialized_agents.rs`
**Scope**: Confidence and threshold adjustment
**Risk**: LOW (optional modifiers)

### RetrievalAgent Modification (Line ~71)

**Current**:
```rust
pub async fn retrieve(&self, input: AgentInput) -> Result<AgentOutput> {
    // ... retrieval logic
    let confidence = if chunks.is_empty() { 0.3 } else { 0.9 };
    Ok(AgentOutput { confidence, ... })
}
```

**With HRV**:
```rust
let hrv_confidence_multiplier = input.metadata
    .get("hrv_zone")
    .and_then(|z| z.as_str())
    .map(|z| match z {
        "VeryLow" => 0.8,   // Reduce confidence when stressed
        "Low" => 0.9,
        "Medium" => 1.0,
        "High" => 1.0,
        "VeryHigh" => 1.05,  // Slight boost when recovered
        _ => 1.0,
    })
    .unwrap_or(1.0);

let confidence = (if chunks.is_empty() { 0.3 } else { 0.9 })
    * hrv_confidence_multiplier;
```

### ValidationAgent Modification (Line ~143)

**Current**:
```rust
// Is answer supported by context? Answer YES or NO
let is_supported = response.contains("YES");
let confidence = if is_supported { 0.9 } else { 0.3 };
```

**With HRV**:
```rust
let validation_threshold = match hrv_zone {
    HRVZone::VeryLow => 0.3,    // Accept low confidence when stressed
    HRVZone::Low => 0.4,
    HRVZone::Medium => 0.5,     // Current baseline
    HRVZone::High => 0.6,
    HRVZone::VeryHigh => 0.7,
};

let confidence = if is_supported { 0.9 } else { 0.3 };
let final_confidence = if confidence >= validation_threshold {
    0.9
} else {
    0.3
};
```

### QualityAgent Modification (Line ~225)

**Current**:
```rust
// Rate quality 0.0-1.0. Answer ONLY with the number.
let quality_score = parse_score(&response)?;
let confidence = if quality_score >= 0.7 { 0.9 } else { 0.3 };
```

**With HRV**:
```rust
let quality_floor = match hrv_zone {
    HRVZone::VeryLow => 0.5,
    HRVZone::Low => 0.6,
    HRVZone::Medium => 0.7,
    HRVZone::High => 0.8,
    HRVZone::VeryHigh => 0.85,
};

let quality_score = parse_score(&response)?;
let meets_floor = quality_score >= quality_floor;
let confidence = if meets_floor { 0.9 } else { 0.3 };
```

---

## Integration Point 4: STRATEGY EVOLUTION (MEDIUM Priority, Optional)

**Files**: `/crates/beagle-agents/src/adversarial/`
**Scope**: Fitness functions and mutation ranges
**Risk**: MEDIUM (requires understanding of evolution logic)
**Status**: Exploratory enhancement

**Proposed Changes**:
1. Include HRV stability in fitness function (strategies that work well across all HRV zones are more robust)
2. Adjust mutation ranges per HRV zone (larger mutations in Very High, smaller in Very Low)

**Non-Critical**: Can be skipped in initial implementation.

---

## Integration Point 5: PERFORMANCE MONITOR (MEDIUM Priority, High Value)

**File**: `/crates/beagle-agents/src/metacognitive/monitor.rs`
**Scope**: Tracking and analytics
**Risk**: LOW (purely additive)

### Add Fields to QueryPerformance

```rust
pub struct QueryPerformance {
    // Existing fields...
    pub query: String,
    pub response_length: usize,
    pub latency_ms: u64,

    // NEW fields (for HRV analysis)
    pub hrv_zone_when_executed: Option<String>,
    pub hrv_confidence_when_executed: Option<f64>,
    pub strategy_used: Option<String>,
    pub success: bool,
}
```

### New Analytics Methods

```rust
pub fn compute_hrv_quality_correlation(&self) -> HashMap<String, f64> {
    // For each HRV zone, compute average quality score
    // Returns: {"VeryLow": 0.65, "Low": 0.70, "Medium": 0.72, ...}
    // Used for validation studies
}

pub fn compute_strategy_success_rate(&self) -> HashMap<String, f64> {
    // For each strategy, compute success rate
    // Returns: {"conservative": 0.80, "thorough": 0.85, ...}
    // Used to identify which strategies work best
}
```

**Purpose**: Foundation for validation studies. Collect data now, analyze later when ready for formal validation.

---

## Data Structure Changes (Backward Compatible)

### New Structs
```rust
pub enum HRVZone {
    VeryLow,
    Low,
    Medium,
    High,
    VeryHigh,
}

pub struct HRVState {
    pub zone: HRVZone,
    pub confidence: f64,
    pub trend: HRVTrend,
    pub last_update: DateTime<Utc>,
    pub rmssd_ms: Option<f64>,
}

pub struct HRVConfig {
    pub enable_hrv: bool,
    pub zone_thresholds: HashMap<HRVZone, ParameterSet>,
    pub hrv_weight: f64,  // 0.0-1.0
}
```

### Extension Pattern (Option<T> for Compatibility)
```rust
// Don't break existing ResearchMetrics
pub struct ResearchMetrics {
    // Existing fields unchanged
    pub domain: String,
    pub query: String,
    pub response: String,

    // NEW HRV-aware fields (optional)
    pub hrv_zone_when_executed: Option<String>,
    pub strategy_adaptation: Option<String>,
    pub hrv_confidence: Option<f64>,
}
```

---

## Implementation Workflow

1. **Read this document** (you are here)
2. **Reference HRV_QUICK_REFERENCE_v2.0.md** for checklist
3. **Reference HRV_INTEGRATION_SUMMARY_v2.0.md** for architecture details
4. **Implement Phase 1-2** (CoordinatorAgent integration)
5. **Code review** with team
6. **Implement Phase 3-4** (ResearcherAgent, specialized agents)
7. **Integration tests** as you go
8. **Phase 5-8** (monitoring, strategy evolution, testing, docs)

---

## Testing the Integration

### Unit Tests
```rust
#[test]
fn test_hrv_zone_classification() {
    assert_eq!(HRVZone::from_rmssd(15.0), HRVZone::VeryLow);
    assert_eq!(HRVZone::from_rmssd(35.0), HRVZone::Medium);
}

#[test]
fn test_parameters_by_zone() {
    let config = HRVConfig::default();
    let params_low = config.get_parameters(HRVZone::Low);
    assert_eq!(params_low.quality_threshold, 0.60);
}
```

### Integration Tests
```rust
#[tokio::test]
async fn test_coordinator_with_hrv() {
    let coord = setup_coordinator();
    let hrv_state = HRVState::new(HRVZone::High, 0.95);

    let result = coord.orchestrate(query, Some(hrv_state)).await;
    assert!(result.is_ok());
}
```

### Regression Tests
```
All existing tests must pass unchanged:
cargo test --all
```

---

## Validation Future Work

**Note**: These are validated AFTER initial implementation:

1. **HRV Zone Mapping Validation**
   - Do our zone boundaries match user cognitive states?
   - Requires: User study with self-reported cognitive state + HRV measurements

2. **Parameter Optimization**
   - Are these specific quality thresholds/token counts optimal?
   - Requires: A/B testing across multiple parameter combinations

3. **Effectiveness Measurement**
   - Does HRV-based adaptation improve outcomes vs. baseline?
   - Requires: Randomized control trial with proper metrics

---

## Status Summary

**Technical Foundation**: ✓ SOLID
**Implementation Ready**: ✓ YES (clear integration points)
**Risk Level**: LOW (non-breaking changes)
**Effectiveness Validated**: ⚠ NO (requires user studies)

**Recommendation**: Implement now, validate effectiveness through studies in Phase 8+

---

**Version History**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Original | Detailed integration hooks and data flows |
| 2.0 | Nov 24, 2025 | Scientific revision: clarified validation status, non-breaking patterns |
