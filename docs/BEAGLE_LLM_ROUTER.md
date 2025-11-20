# BEAGLE LLM Router - Documentação Completa

## Visão Geral

O `BeagleRouter` é o sistema de roteamento inteligente de LLMs do BEAGLE, implementando uma estratégia de **Tier 1 com vacina anti-viés**.

### Estratégia de Roteamento

- **93% das queries** → **Grok 3** (ilimitado, rápido, <1s, custo baixo)
- **Temas de alto risco de viés** → **Grok 4 Heavy** automático (vacina anti-viés)
- **Matemática pesada** → DeepSeek (futuro)
- **Offline** → Gemma local (futuro)

## Arquitetura

```
beagle-llm/
├── router.rs          → BeagleRouter (seleção inteligente)
├── meta.rs            → RequestMeta (detecção de viés)
└── clients/
    └── grok.rs        → GrokClient (Grok 3 + Grok 4 Heavy dinâmico)
```

## Detecção Automática de Viés

O sistema detecta automaticamente keywords de alto risco:

```rust
pub static HIGH_BIAS_KEYWORDS: [&str; 12] = [
    "cellular consciousness",
    "protoconsciousness",
    "entropy curvature",
    "heliobiology",
    "endogenous dmt",
    "fractal scaffolding",
    "quantum biology",
    "big pharma criticism",
    "psychedelic medicine",
    "consciousness substrate",
    "scalar waves",
    "biofield",
];
```

Quando detectado, o router **automaticamente** usa Grok 4 Heavy para garantir respostas mais balanceadas e científicas.

## Uso Básico

### Rust

```rust
use beagle_llm::BeagleRouter;

let router = BeagleRouter;

// Query normal → Grok 3
let answer = router.complete("Explique machine learning").await?;

// Query com risco de viés → Grok 4 Heavy automático
let answer = router.complete(
    "Explique entropia curva como substrato da consciência celular"
).await?;
```

### HTTP Endpoint

O `beagle-core` expõe um endpoint HTTP:

```bash
curl -X POST http://localhost:8080/api/llm/complete \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Explique protoconsciousness"}'
```

Resposta:
```json
{
  "answer": "...",
  "status": "ok"
}
```

### Julia (Futuro)

```julia
using BeagleLLM

answer = BeagleLLM.complete("Explique entropia curva como substrato da consciência celular")
# → automaticamente usa Grok 4 Heavy por detecção de viés
```

## GrokClient - Modelo Dinâmico

O `GrokClient` escolhe o modelo dinamicamente:

- **Grok 3**: default (ilimitado, rápido)
- **Grok 4 Heavy**: quando:
  - `model` contém "heavy" ou "4-heavy"
  - `max_tokens > 16000`
  - Detecção de keywords de alto risco

## RequestMeta

Metadados extraídos do prompt:

```rust
pub struct RequestMeta {
    pub offline_required: bool,
    pub requires_math_proof: bool,
    pub estimated_tokens: usize,
    pub high_bias_risk: bool,  // ← aciona Grok 4 Heavy
}
```

## Custo Estimado

- **Grok 3**: ~$0.001 por query (93% dos casos)
- **Grok 4 Heavy**: ~$0.01 por query (7% dos casos)
- **Custo mensal estimado**: <$25 mesmo usando Heavy diariamente

## Logs e Observabilidade

O router loga automaticamente:

```
Router → grok | heavy: true | math: false | bias_risk: true | tokens: 150
```

## Integração com beagle-core

O `GrokLlmClient` em `beagle-core` usa o router internamente:

```rust
pub struct GrokLlmClient {
    router: beagle_llm::BeagleRouter,
}
```

Isso garante que todas as chamadas LLM no BEAGLE usam o router inteligente.

## Roadmap

- [ ] DeepSeek para matemática pesada
- [ ] Gemma local para modo offline
- [ ] Cache de respostas para queries similares
- [ ] Métricas de uso por modelo
- [ ] A/B testing de modelos

## Referências

- [Grok API Documentation](https://docs.x.ai/)
- [BEAGLE Architecture](./ARCHITECTURE_COHESION.md)
- [BEAGLE Core](./INTEGRATION_COMPLETE.md)

