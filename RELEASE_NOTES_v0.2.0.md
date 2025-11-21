# BEAGLE v0.2.0 - Exocórtex Operacional

**Data de Release:** 2025-01-20  
**Tag:** `v0.2.0`

## 🎯 Visão Geral

BEAGLE v0.2 evolui de um "backend sólido para escrever papers" para um **exocórtex operacional completo**, integrando HPC/Julia, Observer 2.0, IDE Tauri, apps iOS/Watch, módulos simbólicos e instrumentação experimental.

## ✨ Novas Funcionalidades

### Orquestrador HPC/Julia (BLOCO I)
- `BeagleOrchestrator.jl` padroniza chamadas a módulos científicos
- Suporte para jobs: PBPK, Scaffold, Helio, PCS, KEC
- Endpoints HTTP para submissão e acompanhamento de jobs científicos
- Integração com pipeline (campo `science_job_ids` em `run_report.json`)

### Observer 2.0 (BLOCO J)
- Timeline de contexto por `run_id`
- Endpoint `/api/observer/context/:run_id` para recuperar observações
- Integração automática no pipeline

### IDE Tauri (BLOCO K)
- Comandos HTTP integrados:
  - `beagle_pipeline_start` - inicia pipeline
  - `beagle_pipeline_status` - verifica status
  - `beagle_run_artifacts` - obtém artefatos
  - `beagle_recent_runs` - lista runs recentes
  - `beagle_tag_run` - feedback humano

### iOS/Watch (BLOCO L)
- Contrato HTTP documentado (`docs/IOS_WATCH_HTTP_CONTRACT.md`)
- Endpoint `/api/observer/physio` validado para HealthKit

### Módulos Simbólicos (BLOCO M)
- Endpoints HTTP para PCS, Fractal, Worldmodel
- `SymbolicSummary` integrado na Triad (Juiz Final)
- Extração automática de conceitos-chave e estrutura lógica

### Instrumentação Experimental (BLOCO N)
- Campos `experiment_id` e `experiment_condition` em `FeedbackEvent`
- CLI `tag-experiment` para A/B testing

### Dashboard e Análise (BLOCO O)
- CLI `analyze-llm-usage` - estatísticas de uso de LLMs
- CLI `analyze-hrv-effects` - análise de efeitos do HRV

## 📝 Novos Endpoints HTTP

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/api/jobs/science/start` | POST | Inicia job científico |
| `/api/jobs/science/status/:job_id` | GET | Status de job científico |
| `/api/jobs/science/:job_id/artifacts` | GET | Artefatos de job científico |
| `/api/observer/context/:run_id` | GET | Timeline de contexto |
| `/api/pcs/reason` | POST | Raciocínio simbólico PCS |
| `/api/fractal/grow` | POST | Crescimento fractal |
| `/api/worldmodel/predict` | POST | Predições do world model |

## 🛠️ Novos CLIs

- `tag-experiment` - Etiqueta run com condição experimental
- `analyze-llm-usage` - Analisa uso de LLMs
- `analyze-hrv-effects` - Analisa efeitos do HRV

## 🔧 Mudanças Técnicas

- `FeedbackEvent` agora inclui `experiment_id` e `experiment_condition`
- `UniversalObserver` estendido com timeline de contexto
- `generate_symbolic_summary()` adicionado à Triad
- Integração Tauri com core HTTP via `reqwest`

## 📚 Documentação

- `docs/IOS_WATCH_HTTP_CONTRACT.md` - Contrato HTTP para iOS/Watch
- `docs/BEAGLE_v0_2_COMPLETE.md` - Documentação completa do v0.2
- `docs/BEAGLE_v0_2_PROGRESS.md` - Progresso dos blocos

## ⚠️ Breaking Changes

Nenhum. Todos os novos campos são opcionais e backward compatible.

## 🚀 Como Usar

### Iniciar Core Server
```bash
cargo run --bin core_server --package beagle-monorepo
```

### Rodar Pipeline
```bash
cargo run --bin pipeline --package beagle-monorepo -- "Pergunta científica..."
```

### Analisar Feedback
```bash
cargo run --bin analyze-llm-usage --package beagle-feedback
cargo run --bin analyze-hrv-effects --package beagle-feedback
```

### Etiquetar Experimento
```bash
cargo run --bin tag-experiment --package beagle-feedback -- <run_id> <experiment_id> <condition>
```

## 🔮 Próximos Passos (v0.3)

1. Implementar chamadas reais ao Julia para PCS/Fractal/Worldmodel
2. Dashboard web para visualização
3. Autenticação nos endpoints
4. Rate limiting
5. Integração completa com módulos Julia existentes

---

**BEAGLE v0.2.0 está pronto para uso operacional diário como exocórtex científico pessoal.**

