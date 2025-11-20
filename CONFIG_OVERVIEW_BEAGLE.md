# BEAGLE — Visão Geral de Configuração (Interno)

Mapa único das variáveis e diretórios usados pelo BEAGLE (Darwin, HERMES, IDE, publish). Tudo vive em `~/beagle-data` por padrão e é configurável via `BEAGLE_DATA_DIR` ou `.beagle-data-path`.

## Perfis e modos de segurança
- `BEAGLE_PROFILE`: `dev` (default), `lab`, `prod`. Em `dev` assumimos SAFE_MODE ligado e autopublish desativado.  
- `BEAGLE_SAFE_MODE`: `true`/`false` (default: `true`). Força dry-run em caminhos perigosos.  
- `BEAGLE_PUBLISH_MODE`: `dry` (default), `manual`, `auto`. `auto` só permite envio real se SAFE_MODE=false.

## Diretórios principais (beagle-config)
- `BEAGLE_DATA_DIR` ou `.beagle-data-path`: base; default `~/beagle-data`
- Estrutura usada pelos crates: `models/`, `lora/`, `postgres/`, `qdrant/`, `redis/`, `neo4j/`, `logs/`, `papers/drafts`, `papers/final`, `embeddings/`, `datasets/`
- Helpers: `models_dir()`, `lora_dir()`, `logs_dir()`, `ensure_dirs()`

## Dependências de LLM / RAG
- `XAI_API_KEY`: token Grok (xAI) — usado por DARWIN/Grok plugins
- `BEAGLE_GROK_API_URL`: default `https://api.x.ai/v1`
- `BEAGLE_VLLM_URL`: endpoint vLLM local (default `http://t560.local:8000/v1`)
- `ANTHROPIC_API_KEY`: usado por HERMES/agents

## Bancos e grafos
- Postgres: `DATABASE_URL` (ex.: `postgres://user:pass@localhost:5432/beagle`)
- Neo4j: `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`
- Qdrant: `QDRANT_URL` (ex.: `http://localhost:6333`)
- Redis: `REDIS_URL` (ex.: `redis://127.0.0.1:6379`)

## Publicação e redes
- arXiv: `ARXIV_API_TOKEN` (obrigatório para envio real)
- Twitter/X: `TWITTER_API_TOKEN` (opcional)
- vLLM restart remoto (opcional): `VLLM_HOST` usado por comandos de restart

## Comandos úteis
- `cargo run --bin beagle-monorepo -- --help` (CLI do orquestrador quando habilitado)
- `cargo run --package beagle-publish --bin report` (últimos runs de publish)
- `cargo run --package beagle-publish --example ...` (testes de publish)

## Defaults seguros
- Se um serviço não estiver configurado, os módulos devem operar em modo degradado/dry-run e registrar em `logs/`.
- `ensure_dirs()` cria toda a estrutura em `BEAGLE_DATA_DIR` antes de rodar pipelines.
