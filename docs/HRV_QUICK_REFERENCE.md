# HRV Integration - Quick Reference Card

## At a Glance

### Crate: beagle-agents
**Location**: `/crates/beagle-agents/`  
**Library**: No config system yet (library crate)  
**Key Dependencies**: tokio, serde_json, beagle-llm, beagle-memory, beagle-personality

---

## 5 Integration Points (Priority Order)

| # | Component | File | Lines | Priority | Impact |
|---|-----------|------|-------|----------|--------|
| 1 | CoordinatorAgent | `coordinator.rs` | 312 | HIGHEST | Strategy selection, agent composition |
| 2 | ResearcherAgent | `researcher.rs` | 574 | HIGH | Dynamic thresholds, LLM parameters |
| 3 | Specialized Agents | `specialized_agents.rs` | 238 | MED-HIGH | Confidence floors, validation thresholds |
| 4 | Strategy Evolution | `adversarial/strategy.rs` | 100+ | MEDIUM | Fitness functions, mutation ranges |
| 5 | Performance Monitor | `metacognitive/monitor.rs` | 380+ | MEDIUM | HRV-performance correlation tracking |

---

## Key Hooks by Component

### CoordinatorAgent (coordinator.rs:305)
```rust
// CHANGE: get_agent() → get_agent_for_hrv(capability, hrv_state)
// CHANGE: Inject HRV in metadata (line 84-89)
// CHANGE: Quality aggregation logic (line 241-248)
// CHANGE: Track HRV in ResearchMetrics (line 281-302)
```

### ResearcherAgent (researcher.rs:16-19)
```rust
// CHANGE: QUALITY_THRESHOLD = 0.7 → dynamic based on HRV
// CHANGE: MAX_REFINEMENTS = 3 → dynamic based on HRV
// CHANGE: LLM temperature (line 427) → adaptive
// CHANGE: max_tokens (line 425) → adaptive
// CHANGE: Paper search (line 290) → HRV-aware max_results
```

### Specialized Agents (specialized_agents.rs)
```rust
// RetrievalAgent (line 71): confidence → HRV-adjusted
// ValidationAgent (line 143): YES/NO → confidence threshold per HRV
// QualityAgent (line 225): score → quality floor per HRV
```

### Strategy Evolution (adversarial/)
```rust
// arena.rs: evaluate_fitness() → include HRV stability
// strategy.rs: mutate() → mutation_range per HRV zone
```

### Performance Monitor (metacognitive/monitor.rs)
```rust
// QueryPerformance: Add hrv_zone_when_executed, strategy_used
// New methods: hrv_quality_correlation(), strategy_success_rate()
```

---

## New Module Structure

```
beagle-agents/src/hrv_aware/
├─ mod.rs              # Exports
├─ state.rs            # HRVZone enum, HRVState struct
├─ config.rs           # HRVConfig, parameter mappings
├─ selector.rs         # Strategy selection trait
├─ correlation.rs      # Analytics helpers
└─ integration.rs      # Adapter functions
```

---

## HRV Zone Mapping

| Zone | RMSSD Range | Physiological State | Quality Threshold | Max Refinements | Tokens | Temp |
|------|-------------|-------------------|-------------------|-----------------|--------|------|
| VeryLow | <20ms | Stress/fatigue | 0.50 | 1 | 800 | 0.5 |
| Low | 20-30ms | Mild stress | 0.60 | 2 | 1000 | 0.6 |
| Medium | 30-50ms | Normal | 0.70 | 3 | 1200 | 0.8 |
| High | 50-100ms | Good recovery | 0.80 | 4 | 1400 | 0.9 |
| VeryHigh | >100ms | Excellent recovery | 0.85 | 5 | 1500 | 1.0 |

---

## Data Structures

### New Enums
```rust
pub enum HRVZone { VeryLow, Low, Medium, High, VeryHigh }
pub enum HRVTrend { Improving, Stable, Degrading }
```

### New Structs
```rust
pub struct HRVState {
    pub zone: HRVZone,
    pub confidence: f64,
    pub trend: HRVTrend,
    pub last_update: DateTime<Utc>,
    pub rmssd_ms: Option<f64>,
    pub lf_hf_ratio: Option<f64>,
}

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
```

### Extended Structs
```rust
// Add to ResearchMetrics:
pub hrv_zone_when_executed: String,
pub strategy_adaptation: String,
pub hrv_confidence: f64,

// Add to QueryPerformance:
pub hrv_zone_when_executed: Option<String>,
pub hrv_confidence_when_executed: Option<f64>,
pub strategy_used: Option<String>,
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure (Week 1)
- [ ] Create `src/hrv_aware/mod.rs`
- [ ] Implement `state.rs` (HRVZone, HRVState, HRVStateTracker)
- [ ] Implement `config.rs` (HRVConfig, ParameterSet, defaults)
- [ ] Create unit tests for state transitions

### Phase 2: CoordinatorAgent Integration (Week 2)
- [ ] Add HRVStateTracker field to CoordinatorAgent
- [ ] Implement `get_agent_for_hrv()` method
- [ ] Extend metadata injection in `research()` method
- [ ] Update quality aggregation logic
- [ ] Extend ResearchMetrics structure
- [ ] Integration tests for metadata flow

### Phase 3: ResearcherAgent Integration (Week 3)
- [ ] Convert constants to dynamic functions
- [ ] Adapt LLM parameters (temperature, tokens)
- [ ] Adjust paper search strategy
- [ ] Modify critique temperature
- [ ] Integration tests for parameter adaptation

### Phase 4: Specialized Agents (Week 4)
- [ ] Update RetrievalAgent confidence calculation
- [ ] Update ValidationAgent threshold logic
- [ ] Update QualityAgent quality floor
- [ ] Agent-level integration tests

### Phase 5: Performance Monitoring (Week 5)
- [ ] Extend QueryPerformance struct
- [ ] Add hrv-aware recording in CoordinatorAgent/ResearcherAgent
- [ ] Implement correlation analysis methods
- [ ] Analysis tests

### Phase 6: Strategy Evolution (Week 6)
- [ ] Update CompetitionArena fitness evaluation
- [ ] Add HRV-aware strategy mutation
- [ ] Test strategy selection per zone

### Phase 7: Testing & Docs (Week 7)
- [ ] Comprehensive unit test suite
- [ ] Integration test suite
- [ ] Regression tests (backward compatibility)
- [ ] Performance benchmarks by zone
- [ ] API documentation

### Phase 8: Production Rollout (Week 8)
- [ ] Code review & approval
- [ ] Staging deployment
- [ ] Monitoring setup
- [ ] Production rollout
- [ ] Post-deployment validation

---

## Key Design Patterns

### 1. Metadata Carrier Pattern
```rust
// HRV state flows via AgentInput metadata
let input = AgentInput::new(query)
    .with_metadata(json!({
        "hrv_state": { "zone": "High", "confidence": 0.85 },
        "quality_threshold": 0.8
    }));
```

### 2. Dynamic Parameter Functions
```rust
// Thresholds computed based on HRV
fn adaptive_thresholds(hrv: &HRVState) -> (f32, usize) {
    match hrv.zone { /* ... */ }
}
```

### 3. Arc<Mutex<T>> for Shared Mutable State
```rust
// HRV state accessible and updatable from multiple threads
pub struct HRVStateTracker {
    current_state: Arc<Mutex<HRVState>>,
    history: Vec<HRVState>,
}
```

### 4. Strategy per Zone
```rust
// Different strategy for each HRV zone
let mutation_range = match hrv_zone {
    HRVZone::VeryLow => 0.05,
    // ...
};
```

---

## Common Code Patterns

### Reading HRV State from Metadata
```rust
let hrv_state = input.metadata
    .get("hrv_state")
    .and_then(|v| serde_json::from_value(v).ok())
    .unwrap_or_default();
```

### Adaptive Quality Threshold
```rust
let quality_threshold: f32 = input.metadata
    .get("quality_threshold")
    .and_then(|v| v.as_f64().map(|x| x as f32))
    .unwrap_or(0.7);
```

### Recording Performance with HRV
```rust
let perf = QueryPerformance {
    hrv_zone_when_executed: metadata.get("hrv_state")
        .and_then(|v| v.get("zone").and_then(|z| z.as_str()))
        .map(|s| s.to_string()),
    strategy_used: Some("adaptive_research".to_string()),
    // ... other fields
};
monitor.record(perf);
```

---

## Testing Quick Start

### Unit Tests
```bash
cd crates/beagle-agents
cargo test hrv_aware::
```

### Integration Tests
```bash
cargo test --test '*integration*' -- --nocapture
```

### Benchmarks
```bash
cargo bench --bench hrv_performance
```

---

## Files to Modify

| File | Lines | Type | Changes |
|------|-------|------|---------|
| coordinator.rs | 305, 84-89, 241-248 | Add | HRV-aware agent selection, metadata, quality |
| researcher.rs | 16, 19, 425, 427 | Change | Dynamic thresholds, LLM params |
| specialized_agents.rs | 71, 143, 225 | Modify | HRV-adjusted confidence/thresholds |
| models.rs | 16-21 | Extend | Add HRV tracking fields |
| metacognitive/monitor.rs | 7-16 | Extend | Add HRV correlation fields/methods |
| adversarial/strategy.rs | 71-85 | Add | HRV-aware mutation |
| adversarial/arena.rs | fitness fn | Modify | HRV stability in fitness |

---

## Backward Compatibility

All changes are **non-breaking**:
- HRV metadata optional (default to Medium zone)
- New fields in metrics have `Option<>` wrapper
- Existing agent implementations unchanged
- CoordinatorAgent usage same, just more adaptive

---

## Performance Implications

- **Memory**: +~1KB per HRVState + history buffer
- **CPU**: ~0.5ms for HRV zone lookup per request
- **Latency**: Minimal (cached config lookups)
- **Benefit**: 15-40% improvement in quality per zone (estimated)

---

## References

- **Architecture**: See HRV_INTEGRATION_MAP.md for detailed architecture
- **Summary**: See HRV_INTEGRATION_SUMMARY.md for comprehensive analysis
- **Code**: All line numbers refer to current state (Nov 24, 2025)

