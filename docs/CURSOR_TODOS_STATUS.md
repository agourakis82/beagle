# Status dos TODOs - BEAGLE v0.1 Core

## Estado Atual (antes de iniciar os TODOs)

### ✅ Já Implementado

1. **beagle-llm**:
   - `TieredRouter` com Grok 3 Tier 1
   - `GrokClient` (Grok 3 + Grok 4 Heavy dinâmico)
   - `RequestMeta` com detecção de viés
   - `LlmOutput` com telemetria (tokens_in_est, tokens_out_est)
   - `LlmRoutingConfig` com limites Heavy
   - `ProviderTier` enum

2. **beagle-core**:
   - `BeagleContext` com `TieredRouter`
   - `LlmStatsRegistry` para stats por run_id
   - `LlmCallsStats` struct
   - Traits: `LlmClient`, `VectorStore`, `GraphStore`

3. **beagle-feedback**:
   - `FeedbackEvent` com tipos (PipelineRun, TriadCompleted, HumanFeedback)
   - `append_event`, `load_all_events`
   - CLIs: `tag-run`, `analyze-feedback`, `export-lora-dataset`

4. **beagle-triad**:
   - Estrutura básica (ATHENA, HERMES, ARGOS, juiz)
   - `TriadReport` com `LlmCallsStats`
   - CLI `triad_review`

5. **beagle-monorepo**:
   - Pipeline v0.1 (`run_beagle_pipeline`)
   - Core HTTP (`/api/llm/complete`)
   - Integração com feedback

### ⚠️ Parcialmente Implementado / Precisa Ajuste

1. **LlmClient trait**:
   - ✅ `complete()` retorna `LlmOutput`
   - ⚠️ Alguns clients ainda retornam `String` (precisa migração)
   - ⚠️ `complete_text()` legado existe mas não está em todos os lugares

2. **TieredRouter**:
   - ✅ `choose()` retorna `(client, tier)`
   - ✅ `choose_with_limits()` implementado
   - ⚠️ Nem todos os pontos de chamada usam `choose_with_limits` ainda

3. **BeagleContext**:
   - ✅ `llm_stats: LlmStatsRegistry` adicionado
   - ⚠️ Pipeline e Triad ainda não atualizam stats completamente

4. **BeagleConfig**:
   - ✅ Estrutura básica existe
   - ⚠️ Método `profile()` enum não implementado
   - ⚠️ Alguns caminhos ainda usam `~/beagle-data` literal

### ❌ Não Implementado

1. **MockLlmClient** completo
2. **Testes unitários** com mocks
3. **Endpoint `/health`** no core HTTP
4. **CLI `list_runs`**
5. **Documentação completa** do fluxo
6. **Integração IDE Tauri** (se existir)

---

## Progresso dos TODOs

### TODO 01 — BeagleConfig + Profiles
- Status: ⚠️ Parcial
- O que falta:
  - Método `profile()` retornando enum
  - Garantir que todos os caminhos usem `cfg.storage.data_dir`

### TODO 02 — LlmRoutingConfig
- Status: ✅ Completo
- `LlmRoutingConfig` existe com `from_profile()`

### TODO 03 — LlmOutput com telemetria
- Status: ✅ Completo
- `LlmOutput` existe, `LlmClient::complete()` retorna `LlmOutput`

### TODO 04 — LlmCallsStats + BeagleContext
- Status: ✅ Completo
- `LlmStatsRegistry` em `beagle-core`, `BeagleContext` tem `llm_stats`

### TODO 05 — TieredRouter com limites
- Status: ✅ Completo
- `choose_with_limits()` implementado

### TODO 06 — Pipeline com stats
- Status: ⚠️ Parcial
- O que falta:
  - Atualizar stats após cada chamada LLM
  - Salvar stats no `run_report.json`

### TODO 07 — Triad com stats
- Status: ⚠️ Parcial
- O que falta:
  - Usar `choose_with_limits` em todos os agentes
  - Atualizar stats após cada chamada

### TODO 08 — Consolidar RequestMeta/ProviderTier
- Status: ✅ Completo
- `RequestMeta` em `tier.rs`, `ProviderTier` em `router_tiered.rs`

### TODO 09 — Core HTTP com TieredRouter
- Status: ⚠️ Parcial
- O que falta:
  - Usar `choose_with_limits` no handler
  - Criar `RequestMeta` com heurísticas

### TODO 10 — BeagleLLM.jl
- Status: ✅ Completo
- Wrapper existe, precisa smoke-test

### TODO 11 — beagle-stress-test
- Status: ✅ Completo
- Crate existe com binário `stress_test`

### TODO 12 — MockLlmClient + testes
- Status: ⚠️ Parcial
- O que falta:
  - `MockLlmClient` completo (existe parcialmente)
  - Testes unitários

### TODO 13 — BEAGLE_DATA_DIR
- Status: ⚠️ Parcial
- O que falta:
  - Sweep completo removendo `~/beagle-data` literal

### TODO 14 — beagle-feedback completo
- Status: ✅ Completo
- Todos os tipos de evento implementados

### TODO 15 — CLI tag_run
- Status: ✅ Completo
- Binário `tag-run` existe

### TODO 16 — CLI analyze_feedback
- Status: ✅ Completo
- Binário `analyze-feedback` existe

### TODO 17 — CLI export_lora_dataset
- Status: ✅ Completo
- Binário `export-lora-dataset` existe

### TODO 18 — Endpoint /health
- Status: ❌ Não implementado

### TODO 19 — Documentação README
- Status: ⚠️ Parcial
- O que falta:
  - README completo do fluxo

### TODO 20 — IDE Tauri
- Status: ❌ Não implementado (opcional)

### TODO 21 — Perfis na CLI
- Status: ⚠️ Parcial
- O que falta:
  - Logar profile/safe_mode/enable_heavy no início

### TODO 22 — Testes limites Heavy
- Status: ❌ Não implementado

### TODO 23 — Pipeline --with-triad
- Status: ❌ Não implementado

### TODO 24 — HRV → hrv_level
- Status: ⚠️ Parcial
- O que falta:
  - Documentar thresholds

### TODO 25 — CLI list_runs
- Status: ❌ Não implementado

### TODO 26 — cargo fmt/clippy
- Status: ⚠️ Parcial
- O que falta:
  - Rodar e corrigir warnings

### TODO 27 — Tratamento de erros
- Status: ⚠️ Parcial
- O que falta:
  - Fallback Grok3 → LocalFallback

### TODO 28 — Logs estruturados
- Status: ⚠️ Parcial
- O que falta:
  - `tracing::info_span!` em todos os pontos críticos

### TODO 29 — Dashboard textual
- Status: ❌ Não implementado (opcional)

### TODO 30 — Documentação técnica final
- Status: ⚠️ Parcial
- O que falta:
  - `BEAGLE_v0_1_CORE.md` completo

---

## Próximos Passos Recomendados

1. **Corrigir erros de compilação** atuais (dependências circulares, tipos)
2. **Completar TODO 01** (BeagleConfig + Profiles)
3. **Completar TODO 06** (Pipeline com stats)
4. **Completar TODO 07** (Triad com stats)
5. **Completar TODO 12** (MockLlmClient + testes)

---

## Notas Técnicas

- **Dependências circulares**: `beagle-llm` não deve depender de `beagle-core`. `LlmCallsStats` deve estar em `beagle-llm` ou crate separado.
- **Compatibilidade retroativa**: Manter `complete_text()` enquanto migra código para `complete()`.
- **Storage**: Sempre usar `cfg.storage.data_dir` via `BeagleConfig`.

