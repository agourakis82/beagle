# Log de Implementação dos TODOs

## ✅ TODO 01 - BeagleConfig + Profiles
- ✅ Enum `Profile` criado (Dev, Lab, Prod)
- ✅ Método `profile()` implementado
- ✅ Campo `grok_model` adicionado ao `LlmConfig`
- ⚠️ Pendente: Garantir que todos os caminhos usem `cfg.storage.data_dir` (sweep necessário)

## ✅ TODO 02 - LlmRoutingConfig
- ✅ Já implementado em `beagle-llm/src/router_tiered.rs`
- ✅ `from_profile()` implementado
- ✅ Limites por perfil configurados

## ✅ TODO 03 - LlmOutput com telemetria
- ✅ `LlmOutput` struct criado
- ✅ `LlmClient::complete()` retorna `LlmOutput`
- ⚠️ Pendente: Migrar todos os clients para usar `LlmOutput`

## ✅ TODO 04 - LlmCallsStats
- ✅ `LlmCallsStats` struct criado em `beagle-core/src/stats.rs`
- ✅ `LlmStatsRegistry` implementado
- ✅ `BeagleContext` tem `llm_stats` field

## ✅ TODO 05 - TieredRouter com limites
- ✅ `choose_with_limits()` implementado
- ⚠️ Pendente: Usar em todos os pontos de chamada

## ⏳ TODO 06 - Pipeline com stats
- ⏳ Em progresso

## ⏳ TODO 07 - Triad com stats
- ⏳ Em progresso

## ⏳ TODO 08 - Consolidar RequestMeta
- ⏳ Verificar duplicações

## ⏳ TODO 09 - Core HTTP com TieredRouter
- ⏳ Em progresso

## ⏳ TODO 10 - BeagleLLM.jl testável
- ⏳ Em progresso

## ⏳ TODO 11 - beagle-stress-test
- ✅ Crate existe
- ⏳ Verificar se está completo

## ⏳ TODO 12 - MockLlmClient + testes
- ⏳ Em progresso

## ⏳ TODO 13 - BEAGLE_DATA_DIR correto
- ⏳ Sweep necessário

## ✅ TODO 14 - beagle-feedback completo
- ✅ Implementado

## ✅ TODO 15 - CLI tag_run
- ✅ Implementado

## ✅ TODO 16 - CLI analyze_feedback
- ✅ Implementado

## ✅ TODO 17 - CLI export_lora_dataset
- ✅ Implementado

## ⏳ TODO 18 - Endpoint /health
- ⏳ Não implementado

## ⏳ TODO 19 - Documentação README
- ⏳ Parcial

## ⏳ TODO 20 - IDE Tauri
- ⏳ Opcional, não implementado

## ⏳ TODO 21 - Perfis na CLI
- ⏳ Parcial

## ⏳ TODO 22 - Testes limites Heavy
- ⏳ Não implementado

## ⏳ TODO 23 - Pipeline --with-triad
- ⏳ Não implementado

## ⏳ TODO 24 - HRV → hrv_level
- ⏳ Parcial

## ⏳ TODO 25 - CLI list_runs
- ⏳ Não implementado

## ⏳ TODO 26 - cargo fmt/clippy
- ⏳ Parcial

## ⏳ TODO 27 - Tratamento de erros
- ⏳ Parcial

## ⏳ TODO 28 - Logs estruturados
- ⏳ Parcial

## ⏳ TODO 29 - Dashboard textual
- ⏳ Opcional, não implementado

## ⏳ TODO 30 - Documentação técnica final
- ⏳ Parcial

