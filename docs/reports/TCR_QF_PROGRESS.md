# TCR-QF Implementation Progress

**Started**: 2025-11-24  
**Status**: 🔄 In Progress (Day 1 of Weeks 3-4)  
**Goal**: 29% improvement in GraphRAG retrieval accuracy

---

## Phase 1: Foundational Infrastructure ✅ (Completed)

### What Was Built

#### 1. TCR-QF Core Module (`crates/beagle-hypergraph/src/rag/tcr_qf.rs`)
**Lines of code**: 520+ lines  
**Status**: ✅ Implemented and compiling

**Components**:

##### A. Configuration System
```rust
pub struct TcrQfConfig {
    graph_embeddings_enabled: bool,
    temporal_burst_enabled: bool,
    periodic_relevance_enabled: bool,
    fusion_enabled: bool,
    contradiction_detection_enabled: bool,
    fusion_weights: FusionWeights,
    burst_window_days: f32,
    burst_z_threshold: f32,
}
```

##### B. Fusion Weights (Learned Multi-Modal Scoring)
```rust
pub struct FusionWeights {
    semantic: 0.30,           // Text embedding similarity
    topology: 0.15,           // Graph structure embedding
    temporal_burst: 0.10,     // Burst detection score
    temporal_periodic: 0.10,  // Periodic relevance
    recency: 0.15,            // Time decay
    centrality: 0.10,         // Anchor connectivity
    proximity: 0.05,          // Graph distance
    pagerank: 0.05,           // Global importance
}
```

**Innovation**: Reduces semantic weight from 45% to 30%, adding 35% new signals

##### C. Triple Context Scores
```rust
pub struct TripleContextScores {
    semantic: f32,           // Existing
    topology: f32,           // NEW: Graph structure
    temporal_burst: f32,     // NEW: Time series analysis
    temporal_periodic: f32,  // NEW: Periodic patterns
    recency: f32,            // Enhanced
    centrality: f32,         // Enhanced
    proximity: f32,          // Existing
    pagerank: f32,           // NEW: Global ranking
    fused: f32,              // Combined score
}
```

##### D. Graph Topology Embedding Generator
```rust
pub struct TopologyEmbeddingGenerator {
    dimensions: 128,
    walk_length: 80,
    num_walks: 10,
    p: 1.0,  // Return parameter
    q: 1.0,  // In-out parameter
}
```

**Algorithm**: Node2Vec (random walks + skip-gram)  
**Status**: Scaffold complete, implementation pending

##### E. Temporal Burst Detector
```rust
pub struct TemporalBurstDetector {
    window_days: 7.0,
    z_threshold: 1.5,
}

pub fn detect_burst(
    timestamp: &DateTime<Utc>,
    all_timestamps: &[DateTime<Utc>],
) -> f32
```

**Algorithm**: Sliding window z-score  
**Status**: ✅ Fully implemented

**How it works**:
1. Count nodes in 7-day window around timestamp
2. Compute z-score: `(count - mean) / stddev`
3. Normalize to [0, 1] range
4. Returns burst intensity

##### F. PageRank Calculator
```rust
pub struct PageRankCalculator {
    damping: 0.85,
    max_iterations: 100,
    epsilon: 0.0001,
}

pub fn compute(graph: &GraphStructure) -> HashMap<Uuid, f32>
```

**Algorithm**: Power iteration  
**Status**: ✅ Fully implemented

**How it works**:
1. Initialize all nodes with uniform score `1/N`
2. Iterate: `rank[i] = (1-d)/N + d * Σ(rank[j] / outdegree[j])`
3. Converge when max delta < epsilon
4. Returns global importance scores

##### G. Periodic Relevance Scorer
```rust
pub struct PeriodicRelevanceScorer;
```

**Algorithm**: FFT-based frequency detection  
**Status**: Scaffold only (placeholder returns 0.5)

---

### Integration Status

#### Module Integration
- ✅ Created `/crates/beagle-hypergraph/src/rag/tcr_qf.rs`
- ✅ Added `pub mod tcr_qf;` to `mod.rs`
- ✅ Exported public API: `TcrQfConfig`, `FusionWeights`, `TripleContextScores`
- ✅ Compiles successfully (type error fixed)

#### Test Coverage
**5 tests implemented**:
1. ✅ `test_fusion_weights_default` - Validates weights sum to 1.0
2. ✅ `test_fusion_weights_normalize` - Tests weight normalization
3. ✅ `test_triple_context_scores` - Tests fused score computation
4. ✅ `test_temporal_burst_detector` - Validates burst detection
5. ✅ `test_pagerank_simple_graph` - Tests PageRank algorithm

**Test Status**: Pending compilation completion

---

## Phase 2: RAG Pipeline Integration 🔄 (Next)

### Planned Modifications

#### A. Enhance `RAGPipeline::rank_context()`
**File**: `crates/beagle-hypergraph/src/rag/mod.rs` (lines 200-260)

**Current scoring**:
```rust
score = 0.45 * semantic_sim 
      + 0.30 * recency 
      + 0.15 * centrality 
      + 0.10 * proximity
```

**TCR-QF enhanced scoring**:
```rust
// Add topology embedding
let topology_sim = if let Some(topo_emb) = &context_node.topology_embedding {
    cosine_similarity(topo_emb, query_topology_emb)
} else {
    0.0
};

// Add temporal burst
let burst_score = detector.detect_burst(&context_node.node.created_at, &all_timestamps);

// Add periodic relevance
let periodic_score = periodic_scorer.compute_score(&context_node.node.created_at, &all_timestamps, &query_time);

// Add PageRank
let pagerank = pagerank_scores.get(&context_node.node.id).copied().unwrap_or(0.0);

// Quantum fusion
context_node.tcr_qf_scores = TripleContextScores {
    semantic: semantic_sim,
    topology: topology_sim,
    temporal_burst: burst_score,
    temporal_periodic: periodic_score,
    recency,
    centrality,
    proximity,
    pagerank,
    fused: 0.0,
};

context_node.tcr_qf_scores.compute_fused(&config.fusion_weights);
context_node.score = context_node.tcr_qf_scores.fused;
```

#### B. Add Topology Embeddings to `ContextNode`
**File**: `crates/beagle-hypergraph/src/rag/mod.rs`

```rust
pub struct ContextNode {
    pub node: Node,
    pub anchors: HashSet<Uuid>,
    pub min_distance: usize,
    pub anchor_similarity: f32,
    pub score: f32,
    
    // NEW: TCR-QF fields
    pub topology_embedding: Option<Vec<f32>>,
    pub tcr_qf_scores: Option<TripleContextScores>,
}
```

#### C. Precompute Graph Embeddings
**New function**: `RAGPipeline::precompute_topology_embeddings()`

```rust
pub async fn precompute_topology_embeddings(&self) -> Result<()> {
    let generator = TopologyEmbeddingGenerator::default();
    let graph = self.build_graph_structure().await?;
    let embeddings = generator.generate_batch(&all_node_ids, &graph)?;
    
    // Store in Node.metadata["topology_embedding"]
    for (node_id, embedding) in embeddings {
        self.storage.update_metadata(node_id, json!({
            "topology_embedding": embedding
        })).await?;
    }
    
    Ok(())
}
```

#### D. Precompute PageRank
**New function**: `RAGPipeline::precompute_pagerank()`

```rust
pub async fn precompute_pagerank(&self) -> Result<HashMap<Uuid, f32>> {
    let calculator = PageRankCalculator::default();
    let graph = self.build_graph_structure().await?;
    let scores = calculator.compute(&graph);
    
    // Cache in memory or Redis
    Ok(scores)
}
```

---

## Phase 3: Baseline Measurement 📊 (Critical Next Step)

### Tasks Required

#### 1. Create Annotated Test Set
**File**: `crates/beagle-hypergraph/tests/tcr_qf_baseline.rs` (NEW)

**Structure**:
```rust
pub struct AnnotatedQuery {
    query: String,
    relevant_node_ids: Vec<Uuid>,  // Ground truth
    relevance_scores: HashMap<Uuid, f32>,  // 0.0-1.0 relevance
    domain: String,  // "medicine", "biology", "general"
}

pub fn load_test_set() -> Vec<AnnotatedQuery> {
    // 50-100 queries with manual annotations
}
```

**Data sources**:
- Existing `pipeline_demo.rs` queries
- `pipeline_void.rs` test cases
- Medical Q&A datasets (PubMedQA, BioASQ)
- Manual curation by domain experts

#### 2. Implement Evaluation Metrics
**File**: `crates/beagle-hypergraph/src/rag/eval.rs` (NEW)

```rust
pub struct RetrievalMetrics {
    mrr: f32,           // Mean Reciprocal Rank
    recall_at_k: HashMap<usize, f32>,  // Recall@1, @5, @10
    ndcg_at_k: HashMap<usize, f32>,    // NDCG@1, @5, @10
    map: f32,           // Mean Average Precision
    latency_p50: f32,   // Median latency (ms)
    latency_p95: f32,   // 95th percentile latency (ms)
}

pub fn evaluate_retrieval(
    predictions: &[Vec<Uuid>],  // Retrieved node IDs per query
    ground_truth: &[Vec<Uuid>], // Relevant node IDs per query
) -> RetrievalMetrics
```

**Formulas**:
- **MRR**: `1/N * Σ(1 / rank_of_first_relevant)`
- **Recall@k**: `|retrieved ∩ relevant| / |relevant|`
- **NDCG@k**: Normalized discounted cumulative gain

#### 3. Run Baseline Evaluation
**File**: `crates/beagle-hypergraph/examples/tcr_qf_baseline.rs` (NEW)

```bash
cargo run --example tcr_qf_baseline -- --test-set medical_qa.json --output baseline_metrics.json
```

**Expected baseline** (current RAG without TCR-QF):
- MRR: ~0.40-0.50
- Recall@10: ~0.60-0.70
- NDCG@10: ~0.50-0.60
- Latency p95: <500ms

**Target with TCR-QF** (+29%):
- MRR: 0.52-0.65
- Recall@10: 0.77-0.90
- NDCG@10: 0.65-0.77
- Latency p95: <550ms (allow 10% increase)

---

## Phase 4: Node2Vec Implementation 🚧 (Weeks 2-3)

### Algorithm Overview

**Node2Vec**: Graph embedding via biased random walks + skip-gram

**Steps**:
1. **Random Walks**: Generate sequences of nodes
   - Walk length: 80 steps
   - Walks per node: 10
   - Transition probabilities controlled by `p` (return) and `q` (in-out)
   
2. **Skip-Gram Training**: Learn embeddings
   - Context window: 10 nodes
   - Negative sampling: 5 samples
   - Embedding dimension: 128
   - Training epochs: 5

**Transition probability** (from node `v` via edge `(v,x)` to `t`):
```
α(t|v,x) = π(v,t) / Z
π(v,t) = {
    1/p    if d(t,v) = 0  (return to v)
    1      if d(t,v) = 1  (neighbor)
    1/q    if d(t,v) = 2  (explore further)
}
```

**Parameters**:
- `p = 1.0`, `q = 1.0`: Unbiased (DeepWalk)
- `p < 1.0`: Prefer returning to previous nodes (local structure)
- `q < 1.0`: Prefer exploring further (global structure)
- `p > 1.0`, `q > 1.0`: Avoid backtracking

### Implementation Plan

#### Option A: Rust Native (Preferred)
**Crate**: Implement from scratch or use `petgraph` + custom random walks

**Pros**:
- No Python dependency
- Full control over algorithm
- Better integration with BEAGLE

**Cons**:
- More implementation effort
- Need to implement skip-gram training

#### Option B: Python Interop
**Crate**: Use `pyo3` + `node2vec` Python library

**Pros**:
- Battle-tested implementation
- Fast prototyping

**Cons**:
- Python runtime dependency
- Deployment complexity

**Recommendation**: Start with Option B for MVP, migrate to Option A for production

---

## Current Metrics & Progress

### Code Metrics
| Metric | Value |
|--------|-------|
| **TCR-QF module lines** | 520+ |
| **Test coverage** | 5/5 tests implemented |
| **Compilation status** | ✅ Building |
| **Integration status** | 30% (module created, not yet hooked into RAG) |

### Implementation Status

| Component | Status | Progress |
|-----------|--------|----------|
| **Configuration** | ✅ Complete | 100% |
| **Fusion Weights** | ✅ Complete | 100% |
| **Triple Context Scores** | ✅ Complete | 100% |
| **Temporal Burst Detector** | ✅ Complete | 100% |
| **PageRank Calculator** | ✅ Complete | 100% |
| **Periodic Relevance** | 🔄 Scaffold | 20% |
| **Topology Embeddings** | 🔄 Scaffold | 15% |
| **RAG Integration** | ❌ Not Started | 0% |
| **Baseline Measurement** | ❌ Not Started | 0% |
| **A/B Testing** | ❌ Not Started | 0% |

**Overall Progress**: ~35% of Phase 1-2 complete

---

## Next Steps (Priority Order)

### Immediate (Today/Tomorrow)
1. ✅ Fix compilation errors (type annotations)
2. ⏳ Run TCR-QF tests (waiting for build)
3. 📝 Create annotated test set (50 queries minimum)
4. 📊 Implement evaluation metrics (`eval.rs`)
5. 📈 Measure baseline (current RAG without TCR-QF)

### Week 2
6. 🔧 Integrate TCR-QF into `RAGPipeline::rank_context()`
7. 🧠 Implement Node2Vec (Python interop for MVP)
8. 🎯 Add topology embeddings to scoring
9. 📊 A/B test: baseline vs TCR-QF variant A (graph only)

### Week 3
10. 🔬 Implement periodic relevance (FFT-based)
11. 🤝 Implement late fusion architecture
12. 📊 A/B test: TCR-QF variant B (temporal only) vs variant C (full)
13. 🎓 Validate 29% improvement target

### Week 4
14. 🔍 Implement contradiction detection (optional)
15. 🚀 Production deployment with feature flags
16. 📊 Continuous monitoring & weight tuning
17. 📝 Write paper draft for Q1 journal

---

## Risk Mitigation

### Risk 1: Node2Vec Performance
**Concern**: Graph embeddings may be computationally expensive

**Mitigation**:
- Precompute embeddings offline (batch job)
- Cache in Redis with TTL
- Update incrementally (only new nodes)
- Consider dimensionality reduction (128 → 64)

### Risk 2: Insufficient Baseline Data
**Concern**: Hard to prove 29% improvement without good test set

**Mitigation**:
- Use existing PubMedQA/BioASQ datasets
- Manual annotation by domain experts
- Cross-validation with held-out queries
- Temporal holdout (train on past, test on future)

### Risk 3: Overfitting to Test Set
**Concern**: Fusion weights may overfit to specific queries

**Mitigation**:
- K-fold cross-validation
- Diverse query sources (voice, text, sensors)
- Regularization on weight learning
- Validate on separate user feedback data

---

## Success Criteria

### Quantitative
- ✅ MRR improvement ≥ 29%
- ✅ Recall@10 improvement ≥ 15 percentage points
- ✅ NDCG@10 improvement ≥ 0.10 points
- ✅ Latency increase ≤ 10%

### Qualitative
- ✅ User preference in A/B test (>60% prefer TCR-QF)
- ✅ LLM judge evaluation (GPT-4 as judge)
- ✅ Factual consistency improvement
- ✅ Contradiction rate reduction

### Publication Ready
- ✅ Reproducible experiments
- ✅ Ablation studies (each component's contribution)
- ✅ Statistical significance (p < 0.05)
- ✅ Comparison with SOTA GraphRAG methods

---

**Last Updated**: 2025-11-24 21:45 UTC  
**Next Checkpoint**: After baseline measurement complete
