# BEAGLE Core v0.1 — Documentação Técnica

## Visão Geral

O BEAGLE (v2.1/v2.3) é um exocórtex científico pessoal implementado em Rust + Julia, seguindo uma arquitetura **Rust-first** com pipelines científicos em Julia. A filosofia central é **Cloud-first**: LLMs (Grok 3/Grok 4 Heavy) rodam na nuvem, enquanto GPUs locais (RTX 8000, L4, etc.) ficam 100% livres para PBPK/MD/FEA/DL.

### Princípios Arquiteturais

- **Rust-first**: Núcleo em crates modulares (`beagle-llm`, `beagle-monorepo`, `beagle-triad`, `beagle-feedback`, etc.)
- **Cloud-first LLM**: Grok 3 como Tier 1 padrão (ilimitado), Grok 4 Heavy apenas para casos críticos
- **Julia para pipelines científicos**: PBPK, KEC, conversando com o núcleo via HTTP
- **Storage centralizado**: Tudo passa por `BEAGLE_DATA_DIR` e config central
- **Perfis de execução**: `BEAGLE_PROFILE = dev | lab | prod` e `BEAGLE_SAFE_MODE`

---

## Arquitetura Geral

```
┌─────────────────┐
│   Julia (PBPK)  │
│   BeagleLLM.jl  │
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────────────────────┐
│  core_server (Axum)             │
│  /api/llm/complete              │
│  /api/pipeline/start            │
│  /api/pipeline/status/:run_id   │
│  /api/observer/physio           │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  TieredRouter (beagle-llm)      │
│  • Grok 3 (Tier 1, padrão)      │
│  • Grok 4 Heavy (casos críticos)│
│  • CloudMath (opcional)         │
│  • LocalFallback (offline)      │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Pipeline v0.1                  │
│  1. Darwin (GraphRAG)           │
│  2. Observer (HRV/estado físico)│
│  3. HERMES (síntese de paper)   │
│  4. Gera draft.md + draft.pdf   │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Triad (Adversarial)            │
│  • ATHENA (leitura crítica)     │
│  • HERMES (reescrita)           │
│  • ARGOS (crítico Q1)           │
│  • Juiz Final (arbitragem)      │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Feedback System                │
│  • FeedbackEvent (PipelineRun)  │
│  • FeedbackEvent (TriadCompleted)│
│  • FeedbackEvent (HumanFeedback)│
│  • LoRA dataset export          │
└─────────────────────────────────┘
```

---

## Crates Principais e Responsabilidades

### `beagle-llm`
- **TieredRouter**: Roteamento inteligente de LLMs (Grok 3/4 Heavy/Math/Local)
- **LlmClient**: Trait para clientes LLM
- **MockLlmClient**: Mock para testes
- **RequestMeta**: Metadados para roteamento inteligente
- **LlmOutput**: Resposta com telemetria (tokens in/out)

### `beagle-monorepo`
- **Core HTTP server**: Axum server (`core_server` binário)
- **Pipeline v0.1**: `run_beagle_pipeline` (pergunta → draft.md/pdf)
- **JobRegistry**: Gerenciamento de jobs assíncronos (`RunState`, `RunStatus`)
- **CLI**: `pipeline`, `doctor`

### `beagle-triad`
- **Triad adversarial**: ATHENA, HERMES, ARGOS + juiz final
- **TriadReport**: Relatório com opiniões dos 3 agentes + draft final
- **Prompts customizados**: Contexto científico interdisciplinar (psiquiatria, PBPK, biomateriais, etc.)

### `beagle-feedback`
- **FeedbackEvent**: Eventos de aprendizado contínuo
- **CLIs**: `tag_run`, `analyze_feedback`, `export_lora_dataset`
- **Log JSONL**: `feedback_events.jsonl` em `BEAGLE_DATA_DIR/feedback/`

### `beagle-observer`
- **UniversalObserver**: Observação fisiológica (HRV, HealthKit)
- **PhysiologicalState**: Estado fisiológico atual (HRV level, heart rate)
- **Endpoint**: `/api/observer/physio`

### `beagle-config`
- **BeagleConfig**: Configuração centralizada
- **Profile**: `dev | lab | prod`
- **Storage**: `BEAGLE_DATA_DIR` management
- **HRV classification**: `classify_hrv()` → `"low" | "normal" | "high"`

### `beagle-core`
- **BeagleContext**: Contexto unificado com injeção de dependências
- **LlmStatsRegistry**: Estatísticas de chamadas LLM por `run_id`
- **Mock implementations**: `new_with_mock()` para testes

### `beagle-stress-test`
- **stress_pipeline**: Stress test da pipeline (N runs, concorrência configurável)
- **Estatísticas**: p50/p95/p99 de latência

---

## Layout em `BEAGLE_DATA_DIR`

```
BEAGLE_DATA_DIR/
├── papers/
│   └── drafts/
│       └── YYYYMMDD_<run_id>.md
│       └── YYYYMMDD_<run_id>.pdf
├── logs/
│   ├── beagle-pipeline/
│   │   └── YYYYMMDD_<run_id>.json
│   └── observer/
│       └── physio.jsonl
├── triad/
│   └── <run_id>/
│       ├── draft_reviewed.md
│       └── triad_report.json
└── feedback/
    ├── feedback_events.jsonl
    └── lora_dataset.jsonl
```

---

## Perfis (`dev` | `lab` | `prod`) e `BEAGLE_SAFE_MODE`

### Perfis

- **`dev`**: Desenvolvimento local
  - `enable_heavy=false` (por padrão)
  - Logs detalhados
  - Sem publicação automática

- **`lab`**: Ambiente de laboratório/testes
  - `enable_heavy=true` (limites conservadores)
  - Logs estruturados
  - `BEAGLE_SAFE_MODE=true` recomendado

- **`prod`**: Produção pessoal
  - `enable_heavy=true` (limites mais altos)
  - Observability completa
  - `BEAGLE_SAFE_MODE` deve ser configurado explicitamente

### `BEAGLE_SAFE_MODE`

Quando `true`, previne ações irreversíveis (ex.: publicação automática). Recomendado em `dev` e `lab`.

---

## Fluxos Típicos

### CLI

#### 1. Subir `core_server`

```bash
cd apps/beagle-monorepo
cargo run --bin core_server
```

Servidor HTTP em `http://localhost:8080` (ou `BEAGLE_CORE_ADDR`).

#### 2. Pipeline via CLI

```bash
cargo run --bin pipeline -- "Qual o papel da entropia curva em scaffolds biológicos?"
```

Gera:
- `BEAGLE_DATA_DIR/papers/drafts/YYYYMMDD_<run_id>.md`
- `BEAGLE_DATA_DIR/papers/drafts/YYYYMMDD_<run_id>.pdf`
- `BEAGLE_DATA_DIR/logs/beagle-pipeline/YYYYMMDD_<run_id>.json`
- `FeedbackEvent` do tipo `PipelineRun` em `feedback_events.jsonl`

#### 3. Triad review

```bash
# Via HTTP
curl -X POST http://localhost:8080/api/pipeline/start \
  -H "Content-Type: application/json" \
  -d '{"question": "...", "with_triad": true}'

# Ou via binário (se existir)
cargo run --bin triad_review -- --run-id <run_id>
```

Gera:
- `BEAGLE_DATA_DIR/triad/<run_id>/draft_reviewed.md`
- `BEAGLE_DATA_DIR/triad/<run_id>/triad_report.json`
- `FeedbackEvent` do tipo `TriadCompleted`

#### 4. Registrar feedback humano

```bash
cargo run --bin tag-run --package beagle-feedback -- <run_id> 1 9 "ótimo texto para introdução"
```

Cria `FeedbackEvent` do tipo `HumanFeedback` com `accepted=true`, `rating=9`.

#### 5. Analisar feedback

```bash
cargo run --bin analyze-feedback --package beagle-feedback
```

Imprime:
- Nº de eventos por tipo (PipelineRun, TriadCompleted, HumanFeedback)
- Nº de runs distintos
- Accept vs Reject
- Média, p50, p90 de ratings
- Runs com Heavy usage

#### 6. Exportar dataset LoRA

```bash
cargo run --bin export-lora-dataset --package beagle-feedback
```

Gera `BEAGLE_DATA_DIR/feedback/lora_dataset.jsonl` com exemplos:
- `{"run_id": "...", "input": "<Pergunta+DraftInicial>", "output": "<DraftFinalTriad>"}`

Critério de qualidade: `accepted=true` e `rating >= 8`.

#### 7. Stress test

```bash
# Com mocks (recomendado para teste rápido)
BEAGLE_LLM_MOCK=true cargo run --bin stress-pipeline --package beagle-stress-test

# Com Grok real (cuidado com quota!)
BEAGLE_STRESS_RUNS=100 BEAGLE_STRESS_CONCURRENCY=10 \
  cargo run --bin stress-pipeline --package beagle-stress-test
```

### HTTP

#### Endpoints Principais

- **`GET /health`**: Health check
  ```json
  {
    "profile": "lab",
    "safe_mode": true,
    "data_dir": "/path/to/BEAGLE_DATA_DIR",
    "llm_heavy_enabled": true,
    "xai_api_key_present": true
  }
  ```

- **`POST /api/llm/complete`**: Chamada LLM direta
  ```json
  {
    "prompt": "...",
    "requires_math": false,
    "requires_high_quality": true,
    "offline_required": false
  }
  ```

- **`POST /api/pipeline/start`**: Inicia pipeline assíncrono
  ```json
  {
    "question": "...",
    "with_triad": false
  }
  ```
  Retorna: `{"run_id": "...", "status": "created"}`

- **`GET /api/pipeline/status/:run_id`**: Status do job
  ```json
  {
    "run_id": "...",
    "question": "...",
    "status": "running | done | error",
    "created_at": "2024-01-01T12:00:00Z",
    "updated_at": "2024-01-01T12:05:00Z"
  }
  ```

- **`GET /api/run/:run_id/artifacts`**: Artefatos do run
  ```json
  {
    "question": "...",
    "draft_md": "papers/drafts/...",
    "draft_pdf": "papers/drafts/...",
    "triad_final_md": "triad/.../draft_reviewed.md",
    "triad_report_json": "triad/.../triad_report.json",
    "llm_stats": {
      "grok3_calls": 10,
      "grok4_calls": 2,
      "grok3_tokens_in": 5000,
      "grok3_tokens_out": 3000,
      "grok4_tokens_in": 8000,
      "grok4_tokens_out": 5000
    }
  }
  ```

- **`GET /api/runs/recent?limit=10`**: Runs recentes
  ```json
  {
    "runs": [
      {
        "run_id": "...",
        "question": "...",
        "status": "done",
        "created_at": "2024-01-01T12:00:00Z",
        "rating": 9,
        "accepted": true
      }
    ]
  }
  ```

- **`POST /api/observer/physio`**: Registra evento fisiológico
  ```json
  {
    "timestamp": "2024-01-01T12:00:00Z",
    "source": "ios_healthkit",
    "hrv_ms": 65.5,
    "heart_rate_bpm": 72.0,
    "session_id": "session-001"
  }
  ```
  Retorna: `{"status": "ok", "hrv_level": "normal"}`

---

## Variáveis de Ambiente Críticas

- **`BEAGLE_DATA_DIR`**: Diretório base de dados (padrão: `~/beagle-data`)
- **`BEAGLE_PROFILE`**: `dev | lab | prod` (padrão: `dev`)
- **`BEAGLE_SAFE_MODE`**: `true | false` (padrão: `false`)
- **`XAI_API_KEY`**: API key do Grok (necessária para LLM)
- **`BEAGLE_HEAVY_ENABLE`**: Habilitar Grok 4 Heavy (padrão: baseado em profile)
- **`BEAGLE_HEAVY_MAX_CALLS_PER_RUN`**: Limite de chamadas Heavy por run
- **`BEAGLE_HRV_LOW_THRESHOLD`**: Threshold HRV baixo (padrão: 30ms)
- **`BEAGLE_HRV_HIGH_THRESHOLD`**: Threshold HRV alto (padrão: 70ms)
- **`BEAGLE_CORE_ADDR`**: Endereço do core server (padrão: `0.0.0.0:8080`)

---

## Integração Julia

O módulo `BeagleLLM.jl` (em `beagle-julia/`) expõe:

```julia
using BeagleLLM

# Configuração
ENV["BEAGLE_CORE_URL"] = "http://localhost:8080"

# Chamada LLM
response = BeagleLLM.complete(
    "Explique o conceito de entropia curva",
    requires_high_quality=true,
    requires_math=false
)
```

---

## Testes

### Pipeline com mock

```bash
cargo test -p beagle-monorepo --test pipeline_mock
```

### Triad com mock

```bash
cargo test -p beagle-triad --test triad_mock
```

### Stress test com mock

```bash
BEAGLE_LLM_MOCK=true cargo run --bin stress-pipeline --package beagle-stress-test
```

---

## Observações Finais

- **Cloud-first**: Nunca queime GPU local com LLM grande
- **Storage centralizado**: Sempre use `cfg.storage.data_dir`, nunca paths literais
- **Perfis**: Respeite `BEAGLE_PROFILE` e `BEAGLE_SAFE_MODE`
- **Testing**: Use mocks (`BEAGLE_LLM_MOCK=true`) para testes sem consumo de quota
- **Feedback loop**: Todo run gera `FeedbackEvent` para aprendizado contínuo

---

**Versão**: v0.1  
**Data**: 2024  
**Autor**: BEAGLE Team

