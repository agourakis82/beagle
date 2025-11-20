# Continuous Learning v0.1 - Loop Completo

## Status: ✅ 100% Implementado

### Visão Geral

Sistema completo de Continuous Learning que fecha o loop:
- **Pipeline** → gera evento `PipelineRun`
- **Triad** → gera evento `TriadCompleted` com stats LLM
- **Você** → marca com `HumanFeedback` via `tag-run`
- **Análise** → `analyze-feedback` mostra métricas
- **Export** → `export-lora-dataset` gera dataset pronto para LoRA

### Tipos de Evento

```rust
pub enum FeedbackEventType {
    PipelineRun,     // depois de pipeline v0.1
    TriadCompleted,  // depois da Triad
    HumanFeedback,   // seu julgamento explícito
}
```

### Estrutura do FeedbackEvent

```rust
pub struct FeedbackEvent {
    pub event_type: FeedbackEventType,
    pub run_id: String,
    pub timestamp: DateTime<Utc>,
    
    // Core context
    pub question: Option<String>,
    
    // Artefatos
    pub draft_md: Option<PathBuf>,
    pub draft_pdf: Option<PathBuf>,
    pub triad_final_md: Option<PathBuf>,
    pub triad_report_json: Option<PathBuf>,
    
    // Estado fisiológico
    pub hrv_level: Option<String>,
    
    // LLM stats
    pub llm_provider_main: Option<String>,
    pub grok3_calls: Option<u32>,
    pub grok4_heavy_calls: Option<u32>,
    pub grok3_tokens_est: Option<u32>,
    pub grok4_tokens_est: Option<u32>,
    
    // Julgamento humano
    pub accepted: Option<bool>,
    pub rating_0_10: Option<u8>,
    pub notes: Option<String>,
}
```

### Fluxo Completo

1. **Pipeline v0.1** gera draft → loga `PipelineRun`
2. **Triad** processa draft → loga `TriadCompleted` com stats LLM
3. **Você** avalia → usa `tag-run` para `HumanFeedback`
4. **Análise** → `analyze-feedback` mostra métricas
5. **Export** → `export-lora-dataset` gera dataset LoRA

### CLI Tools

#### tag-run
Marca runs como bons/ruins:

```bash
cargo run --bin tag-run --package beagle-feedback -- \
  "20251120_1234abcd" 1 9 "ótimo texto para introdução"
```

#### analyze-feedback
Mostra métricas sintetizadas:

```bash
cargo run --bin analyze-feedback --package beagle-feedback
```

**Output:**
```
=== BEAGLE FEEDBACK ANALYSIS ===

Eventos por tipo:
  Pipeline runs:   10
  Triad completas: 8
  Feedback humano: 5

LLM Usage (Triad):
  Grok 3 calls:      20
  Grok 4 Heavy calls: 4
  Grok 3 tokens est: 50000
  Heavy tokens est:  12000
  Heavy usage: 16.7%

Feedback Humano:
  Accepted: 4 | Rejected: 1
  Rating média: 8.20/10
  Rating p50:   8/10
  Rating p90:   9/10
```

#### export-lora-dataset
Exporta dataset pronto para LoRA:

```bash
cargo run --bin export-lora-dataset --package beagle-feedback
```

**Critério de qualidade:**
- `accepted = true`
- `rating >= 8`
- Deve ter `question`, `draft_md`, `triad_final_md`

**Output:**
```
✅ Dataset LoRA exportado com 4 exemplos em ~/beagle-data/feedback/lora_dataset.jsonl
```

### Formato do Dataset LoRA

```json
{
  "run_id": "20251120_1234abcd",
  "input": "Pergunta:\n...\n\nDraft inicial:\n...\n",
  "output": "Draft final da Triad..."
}
```

### Arquivos Gerados

- `BEAGLE_DATA_DIR/feedback/feedback_events.jsonl` - Todos os eventos
- `BEAGLE_DATA_DIR/feedback/lora_dataset.jsonl` - Dataset de treino (após export)

### Análises Futuras

Com `feedback_events.jsonl` completo, você pode:

1. **Calcular correlações**:
   - HRV vs qualidade percebida
   - Uso de Heavy vs rating
   - Triad vs rating (antes/depois)

2. **Otimizar roteamento**:
   - Quando Heavy realmente melhora
   - Custo-benefício por tipo de pergunta

3. **Treinar LoRA**:
   - Dataset já pronto em formato padrão
   - Input: pergunta + draft inicial
   - Output: draft final da Triad

### Roadmap

✅ **FeedbackEvent com tipos**: Implementado  
✅ **Integração Pipeline**: Funcional  
✅ **Integração Triad**: Funcional  
✅ **CLI tag-run**: Funcional  
✅ **CLI analyze-feedback**: Funcional  
✅ **CLI export-lora-dataset**: Funcional  

### Referências

- [Continuous Learning](./CONTINUOUS_LEARNING.md)
- [TieredRouter v2](./TIERED_ROUTER_V2.md)
- [BEAGLE Triad Complete](./BEAGLE_TRIAD_COMPLETE.md)

---

**Status Final**: ✅ Continuous Learning v0.1 - Loop completo fechado

