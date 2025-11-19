# Beagle Darwin - Incorporação Completa do darwin-core

**darwin-core 100% integrado no BEAGLE**

## Features

- ✅ **GraphRAG real** (usa hypergraph + neo4j + qdrant)
- ✅ **Self-RAG** (agente decide se precisa de mais busca)
- ✅ **Plugin system** (troca LLM em runtime: Grok 3 / local 70B / Heavy)
- ✅ **Multi-AI orchestration** integrado

## Uso Rápido

### Ciclo Completo Darwin-Enhanced

```rust
use beagle_darwin::darwin_enhanced_cycle;

let answer = darwin_enhanced_cycle("unificar entropia curva com consciência celular").await;
println!("DARWIN + BEAGLE: {answer}");
```

### API Avançada

```rust
use beagle_darwin::DarwinCore;

let darwin = DarwinCore::new();

// GraphRAG query
let answer = darwin.graph_rag_query("pergunta aqui").await;

// Self-RAG (avalia confiança e busca mais se necessário)
let final = darwin.self_rag(&answer, "pergunta original").await;

// Plugin system (troca LLM em runtime)
let grok3_result = darwin.run_with_plugin("prompt", "grok3").await;
let local_result = darwin.run_with_plugin("prompt", "local70b").await;
let heavy_result = darwin.run_with_plugin("prompt", "heavy").await;
```

## Plugins Disponíveis

| Plugin | Descrição | Contexto | Quota |
|--------|-----------|----------|-------|
| `grok3` | Grok 3 via smart router | 128k | Ilimitado |
| `local70b` | vLLM local (Llama-3.3-70B) | 8k | Local |
| `heavy` | Grok 4.1 Heavy | 256k | Quota |

## Pipeline Darwin-Enhanced

```
1. GraphRAG Query
   ↓
   Usa hypergraph + neo4j + qdrant
   ↓
2. Self-RAG Gatekeeping
   ↓
   Avalia confiança (0-100)
   ↓
   Se < 85: busca adicional
   ↓
3. Resposta Final
```

## Integração com BEAGLE

O `beagle-darwin` usa automaticamente:
- `beagle-smart-router` para roteamento inteligente de LLMs
- `beagle-grok-api` para acesso ao Grok
- `beagle-llm` para vLLM local
- `beagle-agents` para capacidades de agentes
- `beagle-hypergraph` (via GraphRAG) para knowledge graph

## Exemplo Completo

```bash
# Roda exemplo
cargo run --example darwin_cycle --package beagle-darwin
```

## Requisitos

- `XAI_API_KEY` configurada (para Grok)
- `VLLM_URL` opcional (padrão: `http://t560.local:8000/v1`)
- Neo4j rodando (para GraphRAG)
- Qdrant rodando (para vector search)

## Status

✅ **100% funcional e integrado no BEAGLE**

O darwin-core agora é parte nativa do ecossistema BEAGLE.

