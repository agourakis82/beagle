# BEAGLE v0.27.0 - Exocortex ResearchOps (Darwin)

**Data de Release**: 2026-01-22  
**Versão**: v0.27.0  
**Status**: ✅ **OPERACIONAL (Core + MCP + Darwin + systemd)**

---

## 🚀 Destaques

### 1) Atualização contínua do RAG (Rust)

Implementado em `crates/beagle-rag-update/` (binaries `darwin-*`):

- **`darwin-incremental-indexer`**: indexação incremental baseada em `git diff` (add/modify/delete) + remoção de chunks deletados
- **`darwin-knowledge-manager`**: indexa **papers/docs/livros** em collections separadas:
  - `darwin-repos` (código)
  - `darwin-papers` (papers científicos)
  - `darwin-docs` (documentação/web)
  - `darwin-books` (livros/referências)
- **`darwin-research-harvester`**: coleta (PubMed/arXiv/OpenAlex/Crossref/EuropePMC) → `darwin-papers`
- **`darwin-web-harvester`**: URLs/RSS/sitemaps/crawl com política (hosts/paths/robots) → `darwin-docs`
- **`darwin-brief`**: briefs por tópico (com suporte a delta/“o que mudou”)
- **`darwin-eval`**: avaliação com golden queries (MRR/recall + drift gates)

Opcional: **Ingestion Ledger** (Postgres) via `DARWIN_LEDGER_DATABASE_URL` para pular documentos inalterados e registrar status.

### 2) Automação (systemd) + operacionalização no Dev-Canon

Unidades e instaladores em `scripts/systemd/`:

- Timers para index/harvest/web/knowledge + workflow nightly
- Wrapper `darwin-run.sh` para resolver `darwin-*` via `PATH`/`DARWIN_BIN_DIR`
- Env files em `/etc/darwin-*.env` com permissões restritas (0600)

Runbook: `docs/DEV_CANON_RUNBOOK.md`

### 3) Integrações (Core + MCP)

- **Webhook GitHub (push)**: `POST /webhooks/github/push` dispara indexação incremental do repo (HMAC via `GITHUB_WEBHOOK_SECRET`)
- **MCP tools**: triggers/status para Darwin + Exocortex + Observer + Voice (`beagle-mcp-server/src/tools/`)

### 4) Roteamento multi-model (cost-aware)

- Políticas:
  - `BEAGLE_ROUTING_POLICY=minimax-grok-deepseek`
  - `BEAGLE_ROUTING_POLICY=zai-grok-deepseek` (Z.ai / GLM-4.7)
- Fallback premium (opcional) quando configurado (Claude/Copilot/Cursor) para seções críticas.

### 5) HRV + TTS (Exocortex embodied)

- HRV compat endpoint: `POST /api/hrv` (mantém compat com clientes legados)
- TTS endpoint: `POST /api/voice/tts` (WAV via `espeak-ng`/`espeak`) com ajuste opcional por HRV
- Fix: Observer não inicia mais runtime dentro de runtime (Tokio panic resolvido)

---

## 🧪 Como rodar (resumo)

Core:
```bash
cargo run -p beagle-monorepo --bin core_server --release
```

MCP:
```bash
cd beagle-mcp-server
cp .env.example .env
npm install
npm run build
npm start
```

Darwin (exemplos):
```bash
cargo run -p beagle-rag-update --bin darwin-incremental-indexer -- --repo-path /root/beagle --sync
cargo run -p beagle-rag-update --bin darwin-research-harvester -- --topics-file scripts/darwin-research-topics.yaml --backend all
cargo run -p beagle-rag-update --bin darwin-web-harvester -- --sources-file scripts/darwin-web-sources.sota.yaml --crawl-depth 1
```

systemd:
```bash
sudo bash scripts/systemd/install-darwin-bins.sh --root /usr/local
sudo bash scripts/systemd/install-darwin-timers.sh --user root --workspace /root/beagle --write-env-examples --enable
```

---

## 🔐 Segurança (importante)

- Nunca commitar chaves/API tokens no repositório.
- Se algum token foi exposto em terminal/chat/logs, **rotacione imediatamente** e atualize apenas `/etc/darwin-*.env` (0600).
