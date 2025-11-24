# HRV Integration - Quick Reference (v2.0)

**Status**: Implementation guide for exploratory HRV feature
**Validation Status**: Feature is functional; effectiveness unvalidated
**Timeline**: 8 weeks with clear phases

---

## Key Takeaway First

✅ **Architecture is solid** - HRV can integrate non-breaking
⚠️ **Effectiveness unknown** - Requires user studies to validate
🎯 **Ready for research** - Good foundation for validation studies

---

## 5 Integration Points (Priority Order)

| Priority | Component | File | Impact | Status |
|----------|-----------|------|--------|--------|
| **1** | CoordinatorAgent | `coordinator.rs` | Strategy selection, agent composition | Ready |
| **2** | ResearcherAgent | `researcher.rs` | Dynamic thresholds, LLM parameters | Ready |
| **3** | Specialized Agents | `specialized_agents.rs` | Confidence/threshold adjustment | Ready |
| **4** | Strategy Evolution | `adversarial/strategy.rs` | Fitness functions, mutation ranges | Exploratory |
| **5** | Performance Monitor | `metacognitive/monitor.rs` | HRV-performance correlation tracking | Exploratory |

**Overall Risk**: LOW - All changes designed to be non-breaking

---

## HRV Zone Mapping (Arbitrary Thresholds)

| Zone | RMSSD Range | Suggested Strategy | Notes |
|------|---|---|---|
| **Very Low** | <20ms | Faster, simpler | Thresholds not validated for population |
| **Low** | 20-30ms | Conservative | Individual variation 10-100x |
| **Medium** | 30-50ms | Standard | Use as default if HRV unavailable |
| **High** | 50-100ms | Thorough | May indicate athletic baseline or recovery |
| **Very High** | >100ms | Deep exploration | Rare; may not correlate with cognition |

⚠️ **Critical**: These boundaries are **unvalidated for BEAGLE users**. Proper implementation would require per-user calibration.

---

## Code Changes by Component

### CoordinatorAgent (coordinator.rs:305)
```rust
// ADD: get_agent_for_hrv() method
// ADD: HRV state in metadata injection (line ~84)
// MODIFY: Quality aggregation logic (line ~241)
// TRACK: HRV state in ResearchMetrics (line ~281)
```

**Estimated changes**: 30-50 lines (non-breaking)

### ResearcherAgent (researcher.rs:16-19)
```rust
// MODIFY: QUALITY_THRESHOLD (currently 0.7) → dynamic
// MODIFY: MAX_REFINEMENTS (currently 3) → dynamic
// MODIFY: llm_temperature (line ~427) → dynamic
// MODIFY: max_tokens (line ~425) → dynamic
// MODIFY: paper search max_results → HRV-aware
```

**Estimated changes**: 40-60 lines (non-breaking, defaults preserved)

### Specialized Agents (specialized_agents.rs)
```rust
// RetrievalAgent (line ~71): confidence → HRV-adjusted
// ValidationAgent (line ~143): threshold → HRV-aware
// QualityAgent (line ~225): floor → HRV-aware
```

**Estimated changes**: 15-30 lines per agent

### Strategy Evolution (adversarial/)
```rust
// arena.rs: evaluate_fitness() → include HRV stability
// strategy.rs: mutate() → mutation_range per HRV zone
```

**Estimated changes**: 20-40 lines (optional enhancement)

### Performance Monitor (metacognitive/monitor.rs)
```rust
// ADD: hrv_zone_when_executed to QueryPerformance
// ADD: strategy_used to QueryPerformance
// NEW: hrv_quality_correlation() method
// NEW: strategy_success_rate() method
```

**Estimated changes**: 30-50 lines

---

## New Module Structure

```
beagle-agents/src/hrv_aware/
├─ mod.rs              # Exports: HRVZone, HRVState, HRVConfig
├─ state.rs            # HRV state tracking (~150 lines)
├─ config.rs           # Parameter mappings (~200 lines)
├─ selector.rs         # Strategy selection (~200 lines)
├─ correlation.rs      # Analytics helpers (~150 lines)
├─ integration.rs      # Integration functions (~150 lines)
└─ tests.rs            # Unit tests (~100-150 lines)
```

**Total new code**: ~1000-1100 lines
**Modified existing code**: ~100-150 lines total

---

## Implementation Timeline (8 Weeks)

### Phase 1-2: Foundation (Weeks 1-2)
**Goal**: Core infrastructure
- Create `hrv_aware/` module
- Implement `HRVZone`, `HRVState`, `HRVStateTracker`
- Implement `HRVConfig` with zone mappings
- Unit tests for state transitions
- **Effort**: 80 hours

### Phase 3-4: Agent Integration (Weeks 3-4)
**Goal**: Connect to existing agents
- Integrate with CoordinatorAgent
- Add to ResearcherAgent
- Update specialized agents
- Integration tests
- **Effort**: 60 hours

### Phase 5-6: Learning System (Weeks 5-6)
**Goal**: Monitoring and optimization
- Performance monitoring integration
- HRV-performance correlation analysis
- Strategy evolution hooks
- **Effort**: 70 hours

### Phase 7-8: Testing & Documentation (Weeks 7-8)
**Goal**: Validation and documentation
- Comprehensive test suite
- Performance benchmarking
- Documentation
- **Effort**: 60 hours

**Total**: ~270 hours (6.75 person-weeks, single developer) or 3-4 weeks with 2-person team

---

## Data Structures

### New Enums
```rust
pub enum HRVZone {
    VeryLow,
    Low,
    Medium,
    High,
    VeryHigh,
}

pub enum HRVTrend {
    Improving,
    Stable,
    Degrading,
}
```

### New Structs
```rust
pub struct HRVState {
    pub zone: HRVZone,
    pub confidence: f64,        // 0.0-1.0
    pub trend: HRVTrend,
    pub last_update: DateTime<Utc>,
    pub rmssd_ms: Option<f64>,  // Raw measurement
}

pub struct HRVConfig {
    pub zone_thresholds: HashMap<HRVZone, ParameterSet>,
    pub enable_hrv: bool,        // Feature flag
    pub hrv_weight: f64,         // 0.0-1.0, default 0.1
}

pub struct ParameterSet {
    pub quality_threshold: f32,
    pub max_refinements: usize,
    pub llm_max_tokens: u32,
    pub llm_temperature: f32,
    pub paper_search_max: usize,
    pub retrieval_confidence_floor: f32,
    pub validation_confidence_threshold: f32,
}
```

### Extended Structs (Option<T> for Backward Compatibility)
```rust
// In ResearchMetrics:
pub hrv_zone_when_executed: Option<String>,
pub strategy_adaptation: Option<String>,
pub hrv_confidence: Option<f64>,

// In QueryPerformance:
pub hrv_zone_when_executed: Option<String>,
pub hrv_confidence_when_executed: Option<f64>,
pub strategy_used: Option<String>,
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Create `src/hrv_aware/mod.rs`
- [ ] Implement `state.rs` (HRVZone, HRVState, HRVStateTracker)
- [ ] Implement `config.rs` (HRVConfig, ParameterSet, defaults)
- [ ] Unit tests for state transitions
- [ ] Review with team

### Phase 2: CoordinatorAgent Integration
- [ ] Add HRVStateTracker field to CoordinatorAgent
- [ ] Implement `get_agent_for_hrv()` method
- [ ] Inject HRV in metadata
- [ ] Update quality aggregation logic
- [ ] Integration test
- [ ] Code review

### Phase 3: ResearcherAgent Integration
- [ ] Make parameters dynamic based on HRV
- [ ] Update quality threshold lookup
- [ ] Update max_refinements lookup
- [ ] Update LLM parameters (temperature, tokens)
- [ ] Integration test
- [ ] Code review

### Phase 4: Specialized Agents
- [ ] RetrievalAgent: HRV-aware confidence
- [ ] ValidationAgent: HRV-aware threshold
- [ ] QualityAgent: HRV-aware floor
- [ ] Integration tests
- [ ] Code review

### Phase 5: Performance Monitoring
- [ ] Add HRV fields to QueryPerformance
- [ ] Implement correlation tracking
- [ ] Implement strategy success rate metric
- [ ] Integration test
- [ ] Code review

### Phase 6: Strategy Evolution (Optional)
- [ ] Fitness function adjustments
- [ ] Mutation range per HRV zone
- [ ] Testing

### Phase 7-8: Testing & Docs
- [ ] Regression test suite (all existing tests pass)
- [ ] Performance tests (< 0.5ms overhead)
- [ ] Documentation update
- [ ] README updates
- [ ] Team review

---

## Success Criteria

### Technical
- [ ] All 5 integration points implemented (or marked as out-of-scope)
- [ ] Test coverage > 90% for new code
- [ ] Performance overhead < 0.5ms per request
- [ ] Backward compatibility maintained (all existing tests pass)
- [ ] No breaking API changes

### Operational
- [ ] Feature can be disabled via config flag
- [ ] Graceful fallback when HRV unavailable
- [ ] Production monitoring in place
- [ ] Rollback plan documented and tested

### Research
- [ ] Documentation complete
- [ ] Ready for validation studies
- [ ] Clear methodology for measuring effectiveness
- [ ] Data collection infrastructure ready

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Hardcoded thresholds scattered | Centralize in HRVConfig, single source of truth |
| HRV state unavailable | Graceful fallback to Medium zone defaults |
| Backward compatibility break | All new fields are Option<T>, feature can be disabled |
| Performance regression | Lookups cached, pre-computed configs, measure actual latency |
| Parameter tuning complexity | Start simple (3-5 zones), optimize based on validation results |

---

## Testing Strategy

### Unit Tests
```rust
#[test]
fn test_hrv_zone_from_rmssd() {
    assert_eq!(zone_from_rmssd(15.0), HRVZone::VeryLow);
    assert_eq!(zone_from_rmssd(35.0), HRVZone::Medium);
}

#[test]
fn test_parameters_by_zone() {
    let params = config.get_parameters(HRVZone::Low);
    assert_eq!(params.quality_threshold, 0.60);
}
```

### Integration Tests
```rust
#[tokio::test]
async fn test_coordinator_with_hrv() {
    let coordinator = setup_coordinator_with_hrv();
    let result = coordinator.execute(query, hrv_state).await;
    assert!(result.is_ok());
}
```

### Regression Tests
```
// All existing tests must pass without modification
cargo test --all
```

### Performance Tests
```rust
#[bench]
fn bench_hrv_lookup(b: &mut Bencher) {
    let config = HRVConfig::default();
    b.iter(|| config.get_parameters(HRVZone::High));
    // Target: < 1μs per lookup (0.001ms)
}
```

---

## Common Questions

**Q: Will this break existing code?**
A: No. All changes use `Option<T>` wrappers and feature flags. Existing behavior unchanged if HRV disabled.

**Q: How much latency overhead?**
A: ~0.5ms per request (HRV lookup + metadata enrichment), negligible compared to LLM latency (500-2000ms).

**Q: Can we implement gradually?**
A: Yes. Each phase is independent. CoordinatorAgent first (highest impact), others as time allows.

**Q: What if HRV data isn't available?**
A: Default to Medium zone with standard parameters. Graceful degradation.

**Q: How do we validate this helps?**
A: See `HRV_IMPLEMENTATION_GUIDE_v2.0.md` for validation requirements. Requires user studies comparing with/without HRV routing.

---

## References

- `HRV_IMPLEMENTATION_GUIDE_v2.0.md` - Complete motivation and validation requirements
- `HRV_INTEGRATION_SUMMARY_v2.0.md` - Deep architectural analysis
- `HRV_INTEGRATION_MAP_v2.0.md` - Detailed integration hooks and data flows

---

**Version History**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Original | Quick implementation reference |
| 2.0 | Nov 24, 2025 | Scientific revision: added validation note, clarified status |
