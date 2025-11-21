# BEAGLE Feedback

Sistema de aprendizado contínuo que captura eventos de feedback para treinamento futuro de LoRA.

## Visão Geral

O `beagle-feedback` registra três tipos de eventos:

1. **`PipelineRun`**: Disparado ao final do pipeline v0.1
   - Contém: `question`, `draft_md`, `draft_pdf`, `hrv_level`, `llm_stats`

2. **`TriadCompleted`**: Disparado ao final da Triad
   - Contém: `triad_final_md`, `triad_report_json`, `llm_stats`

3. **`HumanFeedback`**: Feedback humano explícito
   - Contém: `accepted`, `rating_0_10`, `notes`

Todos os eventos são salvos em `BEAGLE_DATA_DIR/feedback/feedback_events.jsonl`.

## CLIs

### `tag_run`: Registrar feedback humano

```bash
cargo run --bin tag-run --package beagle-feedback -- <run_id> <accepted 0/1> [rating0-10] [notes...]
```

Exemplos:
```bash
# Marcar como aceito com rating 9
cargo run --bin tag-run --package beagle-feedback -- run-001 1 9 "ótimo texto para introdução"

# Marcar como rejeitado com rating 3
cargo run --bin tag-run --package beagle-feedback -- run-002 0 3 "confusão entre metáfora e mecanismo"
```

### `analyze_feedback`: Analisar feedback

```bash
cargo run --bin analyze-feedback --package beagle-feedback
```

Imprime:
- Nº de eventos por tipo (PipelineRun, TriadCompleted, HumanFeedback)
- Nº de runs distintos
- Accept vs Reject
- Média, p50, p90 de ratings
- Runs com Heavy usage

Exemplo de saída:
```
=== BEAGLE FEEDBACK ANALYSIS ===

Eventos por tipo:
  Pipeline runs:   50
  Triad completas: 45
  Feedback humano: 30
  Runs distintos:  50

LLM Usage (Triad):
  Grok 3 calls:      200
  Grok 4 Heavy calls: 45
  Heavy usage: 18.4%
  Runs com Heavy:    12 (24.0%)

Feedback Humano:
  Accepted: 25 | Rejected: 5
  Rating média: 8.50/10
  Rating p50:   9/10
  Rating p90:   10/10
```

### `export_lora_dataset`: Exportar dataset para LoRA

```bash
cargo run --bin export-lora-dataset --package beagle-feedback
```

Gera `BEAGLE_DATA_DIR/feedback/lora_dataset.jsonl` com exemplos:

```json
{"run_id": "...", "input": "<Pergunta+DraftInicial>", "output": "<DraftFinalTriad>"}
```

Critério de qualidade:
- `accepted=true` E `rating >= 8`

Imprime quantos exemplos foram gerados.

## Estrutura de `FeedbackEvent`

```rust
pub struct FeedbackEvent {
    pub event_type: FeedbackEventType, // PipelineRun | TriadCompleted | HumanFeedback
    pub run_id: String,
    pub timestamp: DateTime<Utc>,
    
    // Core context
    pub question: Option<String>,
    
    // Artefatos
    pub draft_md: Option<PathBuf>,
    pub draft_pdf: Option<PathBuf>,
    pub triad_final_md: Option<PathBuf>,
    pub triad_report_json: Option<PathBuf>,
    
    // Observer
    pub hrv_level: Option<String>, // "low" | "normal" | "high"
    
    // LLM stats
    pub llm_provider_main: Option<String>, // "grok3" | "grok4_heavy"
    pub grok3_calls: Option<u32>,
    pub grok4_heavy_calls: Option<u32>,
    pub grok3_tokens_est: Option<u32>,
    pub grok4_tokens_est: Option<u32>,
    
    // Human feedback
    pub accepted: Option<bool>,
    pub rating_0_10: Option<u8>,
    pub notes: Option<String>,
}
```

Veja `docs/BEAGLE_CORE_v0_1.md` para mais detalhes sobre o sistema de feedback.

