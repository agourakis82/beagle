# BEAGLE v0.2 — Exocórtex Operacional — Progresso

## Status Geral

**Fase Atual**: BLOCO I concluído — Orquestrador HPC/Julia implementado

**Objetivo**: Transformar o BEAGLE de "backend sólido para papers" para **exocórtex operacional**, integrando HPC/Julia, Observer 2.0, IDE Tauri, apps iOS/Watch, camada simbólica e instrumentação experimental.

---

## ✅ BLOCO I — ORQUESTRADOR HPC/Julia (COMPLETO)

### TODO I1 ✅
- Criado `beagle-julia/BeagleOrchestrator.jl` com:
  - Tipos de jobs: `PBPKJob`, `ScaffoldJob`, `HelioJob`, `PCSJob`, `KECJob`
  - Estrutura `BeagleJobResult` padronizada
  - Função `run_job()` que valida inputs, chama módulo Julia correto e produz relatório JSON serializável

### TODO I2 ✅
- Endpoints HTTP implementados em `apps/beagle-monorepo/src/http.rs`:
  - `POST /api/jobs/science/start`: Submete job científico (body: `{kind: "pbpk", params: {...}}`)
  - `GET /api/jobs/science/status/:job_id`: Retorna status do job
  - `GET /api/jobs/science/:job_id/artifacts`: Retorna paths de outputs
- `ScienceJobRegistry` e `ScienceJobState` criados em `apps/beagle-monorepo/src/jobs.rs`
- Placeholder para chamada Julia (TODO: implementar chamada real via `std::process::Command` ou HTTP interno)

### TODO I3 ✅
- Campo opcional `science_job_ids` adicionado ao `run_report.json`
- Pipeline preparado para anexar jobs científicos a `run_id`

---

## 🔄 PRÓXIMOS BLOCOS

### BLOCO J — Observer 2.0 (PENDENTE)
- TODO J1: Extender UniversalObserver com timeline de contexto
- TODO J2: Expor endpoint `/api/observer/context/:run_id`

### BLOCO K — IDE Tauri (PENDENTE)
- TODO K1: Revisar app Tauri e alinhar com core HTTP
- TODO K2: Integração com feedback humano dentro do IDE

### BLOCO L — Apps iOS/Watch (PENDENTE)
- TODO L1: Definir contrato HTTP minimalista para iOS/Watch
- TODO L2: Backend-ready para HealthKit (já parcialmente implementado)

### BLOCO M — PCS/Fractal/Worldmodel (PENDENTE)
- TODO M1: Mapear módulos PCS/Fractal/Worldmodel e expor APIs internas
- TODO M2: Integrar SymbolicSummary na Triad

### BLOCO N — Instrumentação Experimental (PENDENTE)
- TODO N1: Estrutura para registrar experimentos com condições (A/B)
- TODO N2: CLI para etiquetar `run_id` com condição experimental

### BLOCO O — Dashboard e Análise (PENDENTE)
- TODO O1: CLI `analyze_llm_usage`
- TODO O2: CLI `analyze_hrv_effects`

---

## Notas Técnicas

### Chamada Julia (Placeholder Atual)

Atualmente, os handlers de jobs científicos usam um placeholder que simula execução. A implementação real deve:

1. **Opção 1**: Chamar Julia via `std::process::Command`:
   ```rust
   let output = std::process::Command::new("julia")
       .arg("--project=beagle-julia")
       .arg("beagle-julia/run_job.jl")
       .arg(job_id)
       .arg(kind_str)
       .arg(params_json)
       .output()?;
   ```

2. **Opção 2**: Expor servidor HTTP Julia interno que escuta jobs científicos
3. **Opção 3**: Usar crate Rust-Julia (ex.: `julia-sys`) se disponível

### Integração Pipeline ↔ Jobs Científicos

O campo `science_job_ids` no `run_report.json` é opcional e será preenchido quando jobs científicos forem explicitamente anexados a um `run_id`. Por enquanto, a integração é preparatória.

---

**Data**: 2024  
**Status**: BLOCO I completo, próximos blocos pendentes

