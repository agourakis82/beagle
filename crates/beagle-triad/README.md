# BEAGLE Triad

Sistema adversarial de revisão e refinamento de papers científicos usando três agentes especializados.

## O que é a Triad?

A Triad é um sistema adversarial que usa três agentes para revisar e refinar drafts científicos:

1. **ATHENA**: Agente de leitura crítica e mapeamento de literatura
   - Analisa pontos fortes e fragilidades conceituais
   - Sugere referências adicionais relevantes
   - Contexto científico interdisciplinar (psiquiatria, PBPK, biomateriais, etc.)

2. **HERMES**: Agente de síntese textual
   - Reescreve o texto para maior clareza e coerência
   - Preserva voz autoral interdisciplinar
   - Alta densidade conceitual sem simplificação infantil

3. **ARGOS**: Agente crítico adversarial (nível Q1)
   - Revisor rigoroso (Nature Human Behaviour, Kybernetes, Frontiers)
   - Foca em claims sem suporte, confusão metáfora/mecanismo
   - Identifica ausência de desenho empírico razoável

4. **Juiz Final**: Arbitra a versão final combinando o melhor dos três agentes

## Como usar

### Via HTTP (recomendado)

```bash
# Iniciar pipeline com Triad
curl -X POST http://localhost:8080/api/pipeline/start \
  -H "Content-Type: application/json" \
  -d '{"question": "...", "with_triad": true}'

# Verificar status
curl http://localhost:8080/api/pipeline/status/<run_id>

# Obter artefatos (inclui draft_reviewed.md e triad_report.json)
curl http://localhost:8080/api/run/<run_id>/artifacts
```

### Programaticamente

```rust
use beagle_triad::{run_triad, TriadInput};
use beagle_core::BeagleContext;

let input = TriadInput {
    run_id: "run-001".to_string(),
    draft_path: PathBuf::from("draft.md"),
    context_summary: Some("Context summary".to_string()),
};

let report = run_triad(&input, &ctx).await?;
// report.final_draft contém o draft refinado
// report.opinions contém as opiniões dos 3 agentes
```

## Saídas

A Triad gera:

- **`BEAGLE_DATA_DIR/triad/<run_id>/draft_reviewed.md`**: Draft final refinado
- **`BEAGLE_DATA_DIR/triad/<run_id>/triad_report.json`**: Relatório completo com:
  - `run_id`: ID do run
  - `original_draft`: Draft original
  - `final_draft`: Draft refinado
  - `opinions`: Array com opiniões de ATHENA, HERMES e ARGOS
  - `llm_stats`: Estatísticas de chamadas LLM (Grok 3 vs Heavy)

## Roteamento LLM

A Triad usa o `TieredRouter` para escolher o LLM apropriado:

- **ATHENA**: Usa Grok 4 Heavy se disponível e abaixo dos limites (leitura crítica requer alta qualidade)
- **HERMES**: Usa Grok 3 (reescrita não requer Heavy)
- **ARGOS**: Usa Grok 4 Heavy (crítica adversarial é crítica)
- **Juiz Final**: Usa Grok 4 Heavy (arbitragem final é crítica)

Veja `docs/BEAGLE_CORE_v0_1.md` para mais detalhes sobre roteamento LLM.

