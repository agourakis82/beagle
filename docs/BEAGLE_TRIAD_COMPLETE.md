# BEAGLE Triad - Honest AI - Implementação Completa

## Status: ✅ 100% Implementado e Funcional

### Arquitetura da Triad

Sistema adversarial de revisão com 3 agentes + juiz final:

1. **ATHENA** - Agente literatura
   - Leitura crítica
   - Pontos fortes/fracos
   - Sugestões de literatura adicional
   - Score de qualidade científica

2. **HERMES** - Revisor/reescrita
   - Reescreve mantendo estilo autoral
   - Incorpora sugestões de ATHENA
   - Melhora clareza e coerência
   - Score de melhoria

3. **ARGOS** - Crítico adversarial
   - Revisor exigente (nível Q1)
   - Problemas graves de coerência
   - Claims sem suporte
   - Compara original vs HERMES
   - Score de rigor científico

4. **Juiz Final** - Arbitragem
   - Combina insights de todos
   - Corrige problemas de ARGOS
   - Mantém voz autoral
   - Produz versão final

### Tipos Centrais

```rust
pub struct TriadInput {
    pub run_id: String,
    pub draft_path: PathBuf,
    pub context_summary: Option<String>, // GraphRAG context
}

pub struct TriadOpinion {
    pub agent: String,      // "ATHENA" | "HERMES" | "ARGOS"
    pub summary: String,
    pub suggestions_md: String, // markdown
    pub score: f32,         // 0.0–1.0
}

pub struct TriadReport {
    pub run_id: String,
    pub original_draft: String,
    pub final_draft: String,
    pub opinions: Vec<TriadOpinion>,
    pub created_at: DateTime<Utc>,
}
```

### Fluxo Completo

1. **Pipeline v0.1** gera draft:
   ```bash
   cargo run --bin pipeline --package beagle-monorepo -- "pergunta científica..."
   ```
   → Gera `draft.md` + `run_report.json` com `run_id`

2. **Triad Review** processa draft:
   ```bash
   cargo run --bin triad-review --package beagle-triad -- <run_id>
   ```
   → Gera `draft_reviewed.md` + `triad_report.json`

### Saída

**Diretório**: `BEAGLE_DATA_DIR/triad/<run_id>/`

**Artefatos**:
- `draft_reviewed.md` - Versão final revisada
- `triad_report.json` - Relatório completo com opiniões

**Estrutura do `triad_report.json`**:
```json
{
  "run_id": "...",
  "original_draft": "...",
  "final_draft": "...",
  "opinions": [
    {
      "agent": "ATHENA",
      "summary": "...",
      "suggestions_md": "...",
      "score": 0.8
    },
    {
      "agent": "HERMES",
      "summary": "...",
      "suggestions_md": "...",
      "score": 0.85
    },
    {
      "agent": "ARGOS",
      "summary": "...",
      "suggestions_md": "...",
      "score": 0.9
    }
  ],
  "created_at": "2025-11-20T..."
}
```

### Prompts Detalhados

#### ATHENA
- Analisa pontos fortes/fracos
- Sugere literatura adicional
- Usa contexto GraphRAG se disponível
- Resposta em Markdown estruturado

#### HERMES
- Recebe feedback de ATHENA
- Reescreve mantendo autoria
- Não inventa dados
- Resposta: apenas texto reescrito

#### ARGOS
- Compara original vs HERMES
- Aponta problemas graves
- Nível revisor Q1
- Resposta em Markdown estruturado

#### Juiz Final
- Combina todos os insights
- Corrige problemas de ARGOS
- Mantém voz autoral
- Resposta: apenas texto final

### Integração com Router

Todos os agentes usam:
- `ctx.router.choose(&meta)` - Seleção automática
- `requires_high_quality: true` - Usa Grok 3 (ou Grok 4 Heavy se disponível)
- Juiz Final pode usar Grok 4 Heavy automaticamente

### Uso Completo

```bash
# 1. Gerar draft
cargo run --bin pipeline --package beagle-monorepo -- \
  "Entropy curvature as substrate for cellular consciousness..."

# 2. Revisar com Triad
cargo run --bin triad-review --package beagle-triad -- <run_id>
```

### Exemplo de Saída

```
=== BEAGLE TRIAD REVIEW CONCLUÍDO ===
Run ID: abc123...
Relatório: ~/beagle-data/triad/abc123.../triad_report.json
Draft final: ~/beagle-data/triad/abc123.../draft_reviewed.md

Opiniões:
  ATHENA: Score 0.80 - Leitura crítica e mapeamento de literatura sugerida
  HERMES: Score 0.85 - Reescrita coerente e estilisticamente melhorada
  ARGOS: Score 0.90 - Crítica adversarial e apontamento de falhas lógicas
```

### Filosofia

✅ **Adversarial**: ARGOS tenta "destruir" o draft  
✅ **Construtivo**: HERMES melhora baseado em ATHENA  
✅ **Arbitrado**: Juiz Final combina o melhor  
✅ **Honest AI**: Não inventa dados, mantém autoria

### Roadmap Alinhado

✅ **Week 13-14**: Honest AI Triad → Implementado  
✅ **ATHENA-HERMES-ARGOS**: Todos funcionais  
✅ **Integração Pipeline**: Trabalha sobre drafts do v0.1

## Referências

- [BEAGLE v2.3 Complete](./BEAGLE_V2.3_COMPLETE.md)
- [Pipeline v0.1](./INTEGRATION_COMPLETE.md)

---

**Status Final**: ✅ beagle-triad 100% implementado e funcional

