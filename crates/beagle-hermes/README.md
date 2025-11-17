# HERMES Background Paper Synthesis Engine (BPSE) v2.0

Sistema autônomo de síntese de papers científicos com captura contínua de pensamentos e geração progressiva de manuscritos.

## Arquitetura

```
Voice/Text → Thought Capture → Knowledge Graph → Synthesis → Manuscript
```

### Componentes Principais

1. **Thought Capture**: Captura e processamento de insights (voz/texto)
2. **Knowledge Graph**: Armazenamento e relacionamento de conceitos (Neo4j)
3. **Synthesis Engine**: Geração autônoma de seções de papers
4. **Multi-Agent System**: Orquestração paralela de agentes especializados
5. **Manuscript Management**: Gerenciamento de estado de papers

## Agentes

### ATHENA
- **Função**: Revisão de literatura e coleta de contexto
- **Capacidades**:
  - Busca semântica via RAG pipeline (beagle-hypergraph)
  - Fallback para busca baseada em LLM
  - Extração de key findings de papers

### HERMES
- **Função**: Geração de drafts e escrita
- **Capacidades**:
  - Geração de seções com preservação de voz (LoRA)
  - Extração automática de citações
  - Integração com Claude Sonnet 4.5

### ARGOS
- **Função**: Validação e controle de qualidade
- **Capacidades**:
  - Validação de citações
  - Análise de flow lógico
  - Detecção de issues (transições, claims não suportados, referências)

### Multi-Agent Orchestrator
- **Função**: Coordenação paralela de agentes
- **Paralelização**:
  - Múltiplos clusters processados simultaneamente
  - Múltiplas seções geradas em paralelo
  - Validações independentes executadas concorrentemente

## Uso

### Captura de Pensamento

```rust
use beagle_hermes::{HermesEngine, ThoughtInput, ThoughtContext};

let hermes = HermesEngine::new(config).await?;

let input = ThoughtInput::Text {
    content: "Insight sobre scaffold entropy...".to_string(),
    context: ThoughtContext::Hypothesis,
};

let insight_id = hermes.capture_thought(input).await?;
```

### Síntese Multi-Agente

```rust
use beagle_hermes::agents::MultiAgentOrchestrator;

let orchestrator = MultiAgentOrchestrator::new(voice_profile).await?;

let result = orchestrator
    .synthesize_section(&cluster, "Introduction".to_string(), 500)
    .await?;
```

## Configuração

Variáveis de ambiente necessárias:

- `ANTHROPIC_API_KEY`: API key para Claude
- `DATABASE_URL`: URI do PostgreSQL
- `NEO4J_URI`: URI do Neo4j
- `NEO4J_USER`: Usuário do Neo4j
- `NEO4J_PASSWORD`: Senha do Neo4j
- `REDIS_URL`: URI do Redis (opcional)

## Status

✅ **Track 1 MVP**: Completo
- Thought capture pipeline
- Knowledge graph integration
- Basic synthesis engine
- Manuscript management

✅ **Track 2 Advanced**: Completo
- MLX LoRA optimization (Python)
- Multi-agent orchestration com paralelização
- Validações robustas (ARGOS)

## Próximos Passos

- [ ] Integração completa com beagle-hypergraph RAGPipeline
- [ ] Implementação de voice similarity real
- [ ] Swift app MVP (iOS/macOS)
- [ ] Vision Pro spatial editing
