# TieredRouter v2 - Grok 4 Heavy com Critérios Explícitos

## Status: ✅ 100% Implementado

### Visão Geral

Evolução do TieredRouter para suportar Grok 4 Heavy como "vacina anti-viés" baseado em critérios explícitos:

- **Grok 3**: ~94% dos casos (ilimitado, custo ≈ 0)
- **Grok 4 Heavy**: ~6% dos casos (temas controversos, métodos críticos, proofs)

### RequestMeta Estendido

```rust
pub struct RequestMeta {
    pub offline_required: bool,
    pub requires_math: bool,
    pub requires_vision: bool,
    pub approximate_tokens: usize,
    pub requires_high_quality: bool,
    
    // Novos campos para Grok 4 Heavy
    pub high_bias_risk: bool,             // temas controversos, consciência, psicofarmacologia
    pub requires_phd_level_reasoning: bool, // Methods, Proofs, KEC, PBPK
    pub critical_section: bool,           // Methods, Results, Safety
}
```

### ProviderTier

```rust
pub enum ProviderTier {
    Grok3,           // Default, ~94% dos casos
    Grok4Heavy,      // Vacina anti-viés, métodos críticos
    CloudMath,       // Futuro (DeepSeek etc.)
    LocalFallback,   // Gemma/DeepSeek local
}
```

### Lógica de Roteamento

```rust
pub fn choose(&self, meta: &RequestMeta) -> (Arc<dyn LlmClient>, ProviderTier) {
    // 1) Offline sempre força local
    if meta.offline_required { ... }
    
    // 2) Heavy – só se habilitado e disponível
    if self.cfg.enable_heavy {
        if meta.high_bias_risk 
            || meta.requires_phd_level_reasoning 
            || meta.critical_section 
        {
            return (heavy, ProviderTier::Grok4Heavy);
        }
    }
    
    // 3) Math specialist (futuro)
    if meta.requires_math { ... }
    
    // 4) Default: Grok 3
    (grok3, ProviderTier::Grok3)
}
```

### Integração na Triad

#### ATHENA
- `requires_phd_level_reasoning: true` (avalia ciência)
- Normalmente usa Grok 3, mas pode usar Heavy se contexto exigir

#### HERMES
- `requires_phd_level_reasoning: false` (reescrita não precisa Heavy)
- Sempre usa Grok 3

#### ARGOS
- `high_bias_risk: true` (crítica sobre claims científicos)
- `requires_phd_level_reasoning: true`
- `critical_section: true` (revisão crítica)
- **Usa Grok 4 Heavy**

#### Juiz Final
- `high_bias_risk: true` (decisão final sobre texto científico)
- `requires_phd_level_reasoning: true`
- `critical_section: true` (versão final)
- **Usa Grok 4 Heavy**

### LlmCallsStats

```rust
pub struct LlmCallsStats {
    pub grok3_calls: usize,
    pub grok3_tokens_est: usize,
    pub heavy_calls: usize,
    pub heavy_tokens_est: usize,
}
```

Atualizado automaticamente na Triad para cada chamada LLM.

### Configuração

```bash
# Habilita/desabilita Grok 4 Heavy
BEAGLE_ENABLE_HEAVY=true  # default: true
```

### Logging

Cada chamada loga:
- Provider escolhido (Grok3/Grok4Heavy)
- Razão da escolha (bias_risk, phd_reasoning, critical_section)
- Estatísticas agregadas no `TriadReport`

### Exemplo de Uso

```rust
let meta = RequestMeta::new(
    false, // requires_math
    true,  // requires_high_quality
    false, // offline_required
    1000,  // approximate_tokens
    true,  // high_bias_risk
    true,  // requires_phd_level_reasoning
    true,  // critical_section
);

let (client, tier) = router.choose(&meta);
// tier será ProviderTier::Grok4Heavy
```

### Continuous Learning

Estrutura `FeedbackEvent` preparada para:
- Capturar run_id, question, draft_path
- Triad presente/ausente
- HRV level
- Aceito/editado/rejeitado manualmente
- Salvar em `events.jsonl` para LoRA futuro

### Roadmap

✅ **TieredRouter v2**: Implementado  
✅ **Grok 4 Heavy**: Integrado  
✅ **Triad**: Todos os agentes configurados  
✅ **LlmCallsStats**: Logging funcional  
✅ **FeedbackEvent**: Estrutura pronta  

### Referências

- [BEAGLE v2.3 Complete](./BEAGLE_V2.3_COMPLETE.md)
- [BEAGLE Triad Complete](./BEAGLE_TRIAD_COMPLETE.md)

---

**Status Final**: ✅ TieredRouter v2 completo e funcional

