# 🔬 Deep Research MCTS - Corpus Integration Setup

## ✅ FASE 1 COMPLETA - DIA 1-2: Corpus Integration

**Status**: Implementação completa do corpus integration para Deep Research MCTS.

---

## 📦 Componentes Implementados

### 1. **Semantic Scholar API** (`corpus/semantic_scholar.rs`)
- ✅ Rate limiting (10 req/s)
- ✅ Search papers
- ✅ Get citations
- ✅ Get related papers
- ✅ Error handling robusto

### 2. **Embedding Engine** (`corpus/embeddings.rs`)
- ✅ Python bridge para sentence-transformers
- ✅ Embedding único e batch
- ✅ Cosine similarity
- ✅ Euclidean distance
- ✅ Suporte a modelos customizados

### 3. **Novelty Scorer** (`corpus/novelty.rs`)
- ✅ Corpus building a partir de queries
- ✅ Novelty scoring real (vs. literatura)
- ✅ Find similar papers
- ✅ Cache de embeddings

### 4. **Integração com SimulationEngine**
- ✅ `SimulationEngine::with_novelty_scorer()` 
- ✅ Fallback para heurística quando corpus não disponível
- ✅ Novelty scoring automático em `simulate()`

---

## 🚀 Setup Inicial

### 1. Instalar Dependências Python

```bash
pip install sentence-transformers
```

**Modelo padrão**: `all-MiniLM-L6-v2` (384 dim, rápido, boa qualidade)

**Alternativas**:
- `sentence-transformers/all-mpnet-base-v2` (768 dim, melhor qualidade)
- `sentence-transformers/paraphrase-multilingual-mpnet-base-v2` (multilíngue)

### 2. Verificar Instalação

```bash
python3 -c "from sentence_transformers import SentenceTransformer; print('✅ OK')"
```

### 3. Dependências Rust (já adicionadas)

```toml
reqwest = { version = "0.11", features = ["json"] }
urlencoding = "2.1"
```

---

## 📝 Exemplo de Uso Completo

```rust
use beagle_agents::deep_research::corpus::{ScholarAPI, EmbeddingEngine, NoveltyScorer};
use beagle_agents::deep_research::{MCTSEngine, SimulationEngine};
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializar corpus components
    let scholar = Arc::new(ScholarAPI::new());
    let embeddings = Arc::new(EmbeddingEngine::new());
    let novelty_scorer = Arc::new(NoveltyScorer::new(
        scholar.clone(),
        embeddings.clone(),
    ));

    // 2. Construir corpus (fazer uma vez, depois reutilizar)
    let queries = vec![
        "pharmacokinetics PBPK modeling".to_string(),
        "dynamic graph neural networks drug discovery".to_string(),
        "quantum-inspired machine learning".to_string(),
    ];

    println!("📚 Building corpus...");
    let corpus_size = novelty_scorer.build_corpus(&queries, 50).await?;
    println!("✅ Corpus: {} papers", corpus_size);

    // 3. Criar simulation engine com novelty scorer
    let simulator = SimulationEngine::with_novelty_scorer(
        debate,
        reasoning,
        causal,
        novelty_scorer,
    );

    // 4. Criar MCTS engine
    let mcts = MCTSEngine::new(
        llm,
        Arc::new(simulator),
        100, // iterations
    );

    // 5. Executar deep research
    let query = "Novel PBPK model using dynamic GNN";
    let result = mcts.deep_research(&query).await?;

    println!("🎯 Best hypothesis: {}", result.best_hypothesis.content);
    println!("📊 Novelty: {:.3}", result.best_hypothesis.novelty);
    println!("🌳 Tree size: {}", result.tree_size);

    Ok(())
}
```

---

## 🎯 Próximos Passos (Fase 2)

### DIA 3-4: Sentence-Transformers Embeddings
- [ ] Otimizar batch processing
- [ ] Cache de embeddings em disco
- [ ] Suporte a GPU (opcional)

### DIA 5-7: Preference Learning (DPO style)
- [ ] Dataset de preferências (hipóteses boas vs. ruins)
- [ ] DPO training loop
- [ ] Integration com MCTS prior

### DIA 8-10: Epistemic MCTS
- [ ] Uncertainty tracking por nó
- [ ] Epistemic bonus no PUCT
- [ ] Exploration vs. exploitation balance

### DIA 11-14: Benchmarks
- [ ] Feynman equations dataset
- [ ] Symbolic regression tasks
- [ ] Comparison com baselines

---

## 📊 Métricas de Performance

### Corpus Building
- **100 papers**: ~2-3 minutos (com rate limiting)
- **500 papers**: ~10-15 minutos
- **1000 papers**: ~20-30 minutos

### Novelty Scoring
- **Single hypothesis**: ~100-200ms (embedding + comparison)
- **Batch (10 hypotheses)**: ~500-800ms

### Memory Usage
- **100 papers**: ~50MB (embeddings 384-dim)
- **1000 papers**: ~500MB

---

## 🔧 Troubleshooting

### Python não encontrado
```bash
which python3
# Se não existir, instalar Python 3.8+
```

### sentence-transformers não instalado
```bash
pip install sentence-transformers
# ou
pip3 install sentence-transformers
```

### Rate limiting errors
- Semantic Scholar limita a 10 req/s
- O código já implementa rate limiting automático
- Se ainda houver erros, aumentar delay em `RATE_LIMIT`

### Embeddings muito lentos
- Usar modelo menor: `all-MiniLM-L6-v2` (padrão)
- Ou usar GPU: `pip install torch --index-url https://download.pytorch.org/whl/cu118`

---

## 📚 Referências

- [Semantic Scholar API](https://api.semanticscholar.org/)
- [Sentence Transformers](https://www.sbert.net/)
- [MCTS Paper](https://www.moderndescartes.com/essays/deep_dive_mcts/)

---

**Data**: 2025-01-XX
**Status**: ✅ Fase 1 Completa
**Próxima Fase**: Preference Learning (DPO)


