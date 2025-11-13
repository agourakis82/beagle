# Corpus Integration - Deep Research MCTS

## Visão Geral

Este módulo implementa integração com corpus científico real para detecção de novidade (novelty detection) em hipóteses geradas pelo MCTS. Utiliza:

1. **Semantic Scholar API** - Busca de papers científicos
2. **Sentence Transformers** - Geração de embeddings semânticos
3. **Novelty Scorer** - Comparação de hipóteses contra literatura existente

## Arquitetura

```
corpus/
├── mod.rs              # Módulo principal (exports)
├── semantic_scholar.rs  # API client para Semantic Scholar
├── embeddings.rs        # Engine de embeddings (Python bridge)
└── novelty.rs          # Novelty scorer (comparação com corpus)
```

## Uso Básico

### 1. Construir Corpus

```rust
use beagle_agents::deep_research::corpus::{ScholarAPI, EmbeddingEngine, NoveltyScorer};
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Inicializar componentes
    let scholar = Arc::new(ScholarAPI::new());
    let embeddings = Arc::new(EmbeddingEngine::new());
    let scorer = Arc::new(NoveltyScorer::new(scholar.clone(), embeddings.clone()));

    // Construir corpus a partir de queries
    let queries = vec![
        "pharmacokinetics PBPK modeling".to_string(),
        "dynamic graph neural networks".to_string(),
        "drug-drug interactions".to_string(),
    ];

    let corpus_size = scorer.build_corpus(&queries, 50).await?;
    println!("Corpus built: {} papers", corpus_size);

    Ok(())
}
```

### 2. Score de Novidade

```rust
// Score de novidade de uma hipótese
let hypothesis = "Novel PBPK model using dynamic GNN with quantum-inspired uncertainty";
let novelty = scorer.score_novelty(&hypothesis).await?;

println!("Novelty score: {:.3}", novelty);
// 0.0 = altamente similar à literatura existente
// 1.0 = completamente novo
```

### 3. Encontrar Papers Similares

```rust
// Encontrar papers mais similares
let similar = scorer.find_similar_papers(&hypothesis, 5).await?;

for (paper, similarity) in similar {
    println!("{:.3}: {}", similarity, paper.title);
}
```

### 4. Integração com SimulationEngine

```rust
use beagle_agents::deep_research::{SimulationEngine, NoveltyScorer};

// Criar simulation engine com novelty scorer
let simulator = SimulationEngine::with_novelty_scorer(
    debate,
    reasoning,
    causal,
    scorer, // NoveltyScorer integrado
);

// O simulate() agora usa corpus real para novelty
let result = simulator.simulate(&hypothesis).await?;
```

## Dependências Python

O `EmbeddingEngine` requer Python 3 com `sentence-transformers`:

```bash
pip install sentence-transformers
```

Modelo padrão: `all-MiniLM-L6-v2` (384 dimensões, rápido, boa qualidade)

Para modelos maiores:
```rust
let embeddings = EmbeddingEngine::with_model(
    "sentence-transformers/all-mpnet-base-v2".to_string()
);
```

## Rate Limiting

O `ScholarAPI` implementa rate limiting automático:
- **Limite**: 10 requisições/segundo
- **Timeout**: 30 segundos por requisição
- **Retry**: Não implementado (retorna erro)

## Performance

- **Embedding único**: ~100-200ms (depende do modelo)
- **Batch embedding**: ~50-100ms por texto (mais eficiente)
- **Corpus building**: ~2-5 minutos para 100 papers (com rate limiting)

## Próximos Passos (Fase 2)

1. **Preference Learning (DPO style)** - Aprender preferências de hipóteses
2. **Epistemic MCTS** - Tracking de incerteza epistêmica
3. **Benchmarks** - Validação com Feynman equations e symbolic regression


