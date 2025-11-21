# BEAGLE Monorepo

Aplicação principal do BEAGLE que integra o pipeline científico, servidor HTTP e CLI.

## Subir `core_server`

```bash
cd apps/beagle-monorepo
cargo run --bin core_server
```

O servidor HTTP ficará disponível em `http://localhost:8080` (ou `BEAGLE_CORE_ADDR`).

### Variáveis de Ambiente

- `BEAGLE_CORE_ADDR`: Endereço do servidor (padrão: `0.0.0.0:8080`)
- `BEAGLE_DATA_DIR`: Diretório de dados (padrão: `~/beagle-data`)
- `BEAGLE_PROFILE`: Perfil de execução (`dev | lab | prod`)
- `XAI_API_KEY`: API key do Grok (necessária para LLM)

## Pipeline via CLI

```bash
cargo run --bin pipeline -- "Qual o papel da entropia curva em scaffolds biológicos?"
```

Isso gera:
- `BEAGLE_DATA_DIR/papers/drafts/YYYYMMDD_<run_id>.md`
- `BEAGLE_DATA_DIR/papers/drafts/YYYYMMDD_<run_id>.pdf`
- `BEAGLE_DATA_DIR/logs/beagle-pipeline/YYYYMMDD_<run_id>.json`

## Pipeline via HTTP

### Iniciar pipeline assíncrono

```bash
curl -X POST http://localhost:8080/api/pipeline/start \
  -H "Content-Type: application/json" \
  -d '{"question": "Qual o papel da entropia curva em scaffolds biológicos?", "with_triad": false}'
```

Resposta:
```json
{
  "run_id": "...",
  "status": "created"
}
```

### Verificar status

```bash
curl http://localhost:8080/api/pipeline/status/<run_id>
```

### Obter artefatos

```bash
curl http://localhost:8080/api/run/<run_id>/artifacts
```

## Endpoints Principais

- `GET /health`: Health check
- `POST /api/llm/complete`: Chamada LLM direta
- `POST /api/pipeline/start`: Inicia pipeline assíncrono
- `GET /api/pipeline/status/:run_id`: Status do job
- `GET /api/run/:run_id/artifacts`: Artefatos do run
- `GET /api/runs/recent?limit=N`: Runs recentes
- `POST /api/observer/physio`: Registra evento fisiológico

Veja `docs/BEAGLE_CORE_v0_1.md` para documentação completa.

