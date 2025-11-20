# Continuous Learning - Sistema de Feedback

## Status: ✅ 100% Implementado

### Visão Geral

Sistema de instrumentação para Continuous Learning que captura eventos de aprendizado para treinamento futuro de LoRA, sem ainda mexer em modelos, mas preparando tudo para treinamento.

### Estrutura do FeedbackEvent

```rust
pub struct FeedbackEvent {
    pub run_id: String,
    pub timestamp: DateTime<Utc>,
    pub question: String,
    
    // Artefatos
    pub draft_md: Option<PathBuf>,
    pub draft_pdf: Option<PathBuf>,
    pub triad_final_md: Option<PathBuf>,
    pub triad_report_json: Option<PathBuf>,
    
    // Estado fisiológico
    pub hrv_level: Option<String>, // "low" | "normal" | "high"
    
    // Stats de LLM
    pub llm_provider_main: Option<String>, // "grok3", "grok4_heavy"
    pub grok3_calls: Option<u32>,
    pub grok4_heavy_calls: Option<u32>,
    pub grok3_tokens_est: Option<u32>,
    pub grok4_tokens_est: Option<u32>,
    
    // Sinal humano
    pub accepted: Option<bool>,
    pub rating_0_10: Option<u8>,
    pub notes: Option<String>,
}
```

### Fluxo Completo

1. **Pipeline v0.1** gera draft → loga evento base
2. **Triad** processa draft → loga evento com stats LLM
3. **Você** avalia → usa `tag-run` para feedback humano

### Integração no Pipeline

Após gerar `draft.md`, `draft.pdf` e `run_report.json`, o pipeline automaticamente:

```rust
let event = create_pipeline_event(
    run_id,
    question,
    draft_md,
    draft_pdf,
    hrv_level,  // Extraído do estado fisiológico
    Some("grok3".to_string()),
);
append_event(&data_dir, &event)?;
```

### Integração na Triad

Após gerar `draft_reviewed.md` e `triad_report.json`, a Triad automaticamente:

```rust
let event = create_triad_event(
    run_id,
    question,
    triad_final_md,
    triad_report_json,
    llm_stats,  // (grok3_calls, heavy_calls, grok3_tokens, heavy_tokens)
);
append_event(&data_dir, &event)?;
```

### CLI tag-run

Para marcar runs como bons/ruins:

```bash
# Aceitei esse run como bom, nota 9, com nota
cargo run --bin tag-run --package beagle-feedback -- \
  "20251120_1234abcd" 1 9 "ótimo texto para introdução de artigo"

# Run ruim, nota 3, sem nota textual
cargo run --bin tag-run --package beagle-feedback -- \
  "20251120_deadbeef" 0 3
```

### Arquivo de Feedback

Todos os eventos são salvos em:
```
BEAGLE_DATA_DIR/feedback/feedback_events.jsonl
```

Formato JSONL (uma linha JSON por evento), ideal para:
- Análise incremental
- Treinamento de LoRA
- Análise estatística

### Uso Futuro para LoRA

Com `feedback_events.jsonl` completo, você pode:

1. **Extrair exemplos "bons"** (accepted = true, rating ≥ 8)
   → Dataset base para LoRA de estilo/voz

2. **Extrair exemplos "ruins"** (accepted = false, rating ≤ 4)
   → Dataset de "não faça isso", útil para filtros ou re-ranking

3. **Estimar empiricamente**:
   - Em que tipo de pergunta Grok 4 Heavy realmente melhora vs Grok 3
   - Como HRV correlaciona com percepção de qualidade
   - Se Triad melhora rating médio comparado a pipeline simples

### Análise de Dados

Exemplo de queries futuras:

```rust
// Carregar todos os eventos
let events = load_all_events(&data_dir)?;

// Filtrar apenas runs aceitos com rating alto
let good_runs: Vec<_> = events
    .iter()
    .filter(|e| e.accepted == Some(true) && e.rating_0_10 >= Some(8))
    .collect();

// Calcular uso de Heavy vs Grok 3
let heavy_usage: f64 = events
    .iter()
    .filter(|e| e.llm_provider_main == Some("grok4_heavy".to_string()))
    .count() as f64 / events.len() as f64;
```

### Roadmap

✅ **beagle-feedback crate**: Implementado  
✅ **Integração Pipeline**: Funcional  
✅ **Integração Triad**: Funcional  
✅ **CLI tag-run**: Funcional  
⏳ **Script de análise**: Futuro  
⏳ **Formato dataset LoRA**: Futuro  

### Referências

- [TieredRouter v2](./TIERED_ROUTER_V2.md)
- [BEAGLE Triad Complete](./BEAGLE_TRIAD_COMPLETE.md)
- [BEAGLE v2.3 Complete](./BEAGLE_V2.3_COMPLETE.md)

---

**Status Final**: ✅ Sistema de Continuous Learning completo e funcional

