# BEAGLE Core v0.3 - Documentação Técnica

## Visão Geral

O BEAGLE Core v0.3 é o núcleo consolidado do sistema BEAGLE, integrando todos os módulos principais em uma arquitetura unificada e estável.

### Arquitetura

```
Julia/HPC → BEAGLE Core HTTP (Axum) → TieredRouter (Grok 3/4 Heavy)
                                          ↓
                    Pipeline (Darwin + Observer + HERMES + Triad)
                                          ↓
                           Artefatos (drafts, reports, feedback)
```

### Componentes Principais

- **BeagleConfig**: Configuração centralizada (perfis dev/lab/prod, flags de módulos avançados)
- **BeagleContext**: Contexto unificado com todas as dependências injetadas
- **TieredRouter**: Roteamento inteligente de LLMs (Grok 3 como Tier 1, Grok 4 Heavy para casos críticos)
- **Pipeline v0.x**: Fluxo completo de pergunta → draft → Triad → artefatos
- **Core HTTP Server**: API REST estável para front-end (iOS/Vision) e Julia/HPC
- **Feedback System**: Sistema de eventos para Continuous Learning

## Configuração

### Variáveis de Ambiente

```bash
# Perfil de execução
BEAGLE_PROFILE=dev  # dev | lab | prod

# Modo seguro (default: true)
BEAGLE_SAFE_MODE=true

# Diretório de dados
BEAGLE_DATA_DIR=~/beagle-data

# API Keys
XAI_API_KEY=xai-xxx

# Módulos Avançados
BEAGLE_SERENDIPITY=true
BEAGLE_SERENDIPITY_TRIAD=true
BEAGLE_VOID_ENABLED=true
BEAGLE_MEMORY_RETRIEVAL=true

# Heavy LLM Limits
BEAGLE_HEAVY_ENABLE=true
BEAGLE_HEAVY_MAX_CALLS_PER_RUN=10
BEAGLE_HEAVY_MAX_TOKENS_PER_RUN=200000

# Core Server
BEAGLE_CORE_ADDR=0.0.0.0:8080
```

### Perfis

- **dev**: Heavy desabilitado, SAFE_MODE sempre true
- **lab**: Heavy habilitado com limites conservadores
- **prod**: Heavy habilitado com limites mais altos

## Endpoints HTTP

### POST `/api/llm/complete`

Completa um prompt usando o TieredRouter.

**Request:**
```json
{
  "prompt": "Explique clearance em PBPK",
  "requires_math": false,
  "requires_high_quality": true,
  "offline_required": false
}
```

**Response:**
```json
{
  "text": "Resposta do LLM...",
  "provider": "grok-3",
  "tier": "Grok3"
}
```

### POST `/api/pipeline/start`

Inicia um pipeline BEAGLE completo.

**Request:**
```json
{
  "question": "Revisão sistemática sobre scaffolds biológicos",
  "with_triad": true
}
```

**Response:**
```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "created"
}
```

### GET `/api/pipeline/status/:run_id`

Consulta o status de um pipeline.

**Response:**
```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "question": "Revisão sistemática...",
  "status": "running",
  "created_at": "2024-01-01T00:00:00Z"
}
```

**Status possíveis:**
- `pending`: Aguardando processamento
- `running`: Em execução
- `triad_running`: Executando Triad
- `triad_done`: Triad concluído
- `done`: Concluído
- `failed`: Falhou

### GET `/api/run/:run_id/artifacts`

Lista artefatos gerados por um run.

**Response:**
```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "question": "Revisão sistemática...",
  "draft_md": "/path/to/draft.md",
  "draft_pdf": "/path/to/draft.pdf",
  "triad_final_md": "/path/to/triad_final.md",
  "triad_report_json": "/path/to/triad_report.json",
  "llm_stats": {
    "grok3_calls": 5,
    "grok4_calls": 2,
    "grok3_tokens_in": 1000,
    "grok3_tokens_out": 2000,
    "grok4_tokens_in": 500,
    "grok4_tokens_out": 1000
  }
}
```

### GET `/health`

Verifica saúde do servidor.

**Response:**
```json
{
  "status": "ok",
  "service": "beagle-core",
  "profile": "dev",
  "safe_mode": true,
  "data_dir": "~/beagle-data",
  "xai_api_key_present": true
}
```

### POST `/api/observer/physio`

Registra evento fisiológico (HRV, HR, etc.).

**Request:**
```json
{
  "source": "ios_healthkit",
  "hrv_ms": 50.5,
  "heart_rate_bpm": 72.0,
  "session_id": "optional_session_id"
}
```

**Response:**
```json
{
  "status": "ok",
  "hrv_level": "normal"
}
```

### GET `/api/runs/recent?limit=10`

Lista runs recentes.

**Response:**
```json
{
  "runs": [
    {
      "run_id": "...",
      "question": "...",
      "status": "done",
      "created_at": "..."
    }
  ]
}
```

## Uso

### Iniciar Core Server

```bash
cargo run --bin core_server --package beagle-monorepo
```

### Executar Pipeline via CLI

```bash
cargo run --bin pipeline --package beagle-monorepo -- "Pergunta científica..."
```

### Usar BeagleLLM.jl

```julia
using BeagleLLM

# Configurar URL (default: http://localhost:8080)
ENV["BEAGLE_CORE_URL"] = "http://localhost:8080"

# Chamada LLM
answer = BeagleLLM.complete(
    "Explique clearance em PBPK";
    requires_math=true,
    requires_high_quality=true
)

# Iniciar pipeline
result = BeagleLLM.start_pipeline(
    "Revisão sistemática sobre scaffolds";
    with_triad=true
)

run_id = result["run_id"]

# Verificar status
status = BeagleLLM.pipeline_status(run_id)
```

## Estrutura de Diretórios

```
BEAGLE_DATA_DIR/
├── papers/
│   ├── drafts/          # Drafts MD/PDF
│   └── final/           # Papers finais
├── triad/               # Relatórios da Triad
│   └── <run_id>/
│       ├── draft_reviewed.md
│       └── triad_report.json
├── feedback/            # Eventos de feedback
│   └── feedback_events.jsonl
├── logs/
│   ├── beagle-pipeline/ # Run reports
│   └── observer/        # Logs do Observer
└── jobs/
    └── science/         # Jobs científicos (PBPK, etc.)
```

## Módulos Avançados

### Serendipity

Descoberta de conexões interdisciplinares inesperadas. Habilitado via:
- `BEAGLE_SERENDIPITY=true`
- `BEAGLE_SERENDIPITY_TRIAD=true` (aplica na Triad)

### Void

Detecção e resolução de deadlocks. Habilitado via:
- `BEAGLE_VOID_ENABLED=true`

### Memory Retrieval

Injeção de contexto prévio relevante no pipeline. Habilitado via:
- `BEAGLE_MEMORY_RETRIEVAL=true`

## Integração com Front-end (iOS/Vision Pro)

Todos os endpoints retornam JSON consistente e podem ser consumidos diretamente por apps Swift:

```swift
// Exemplo Swift
struct LlmResponse: Codable {
    let text: String
    let provider: String
    let tier: String
}

let response = try await URLSession.shared.data(
    from: URL(string: "http://localhost:8080/api/llm/complete")!,
    httpMethod: "POST",
    body: requestJSON
)
```

## Troubleshooting

### Core Server não inicia

1. Verifique `BEAGLE_DATA_DIR` e permissões
2. Verifique se a porta 8080 está livre
3. Verifique logs: `RUST_LOG=debug cargo run --bin core_server`

### Pipeline falha

1. Verifique `XAI_API_KEY` está configurada
2. Verifique logs em `BEAGLE_DATA_DIR/logs/beagle-pipeline/`
3. Verifique `run_report.json` para detalhes do erro

### Julia não conecta

1. Verifique `BEAGLE_CORE_URL` está correto
2. Verifique core server está rodando: `curl http://localhost:8080/health`
3. Verifique firewall/porta

## Próximos Passos

- Integração com Vision Pro (app iOS)
- Dashboard web para visualização de runs
- Métricas e observabilidade (Prometheus/Grafana)
- Otimizações de performance

---

**BEAGLE Core v0.3** - Núcleo consolidado e funcional 🚀

