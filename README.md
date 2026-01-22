# BEAGLE v0.27.0 - Exocortex ResearchOps (Darwin)

**Exocórtex Científico Pessoal** - Rust + Julia + Swift/Tauri

## 🚀 Versão Atual: v0.27.0

BEAGLE v0.27.0 consolida o **loop completo do Exocórtex**: Core + MCP + Observer + **DARWIN ResearchOps** (RAG com atualização contínua) para código, papers, docs e livros.

### ✨ Novidades v0.27.0

- **RAG Update Contínuo (Rust)**: `darwin-incremental-indexer`, `darwin-knowledge-manager`, `darwin-research-harvester`, `darwin-web-harvester`, `darwin-brief`, `darwin-eval`
- **Webhook GitHub (push)**: `POST /webhooks/github/push` → indexação incremental do repo
- **Systemd timers**: automação (index, harvest, briefs, eval) com env seguro em `/etc/darwin-*.env`
- **Roteamento multi-provedor**: MiniMax/Z.ai → Grok → DeepSeek (+ rotas premium quando configuradas)
- **HRV + Observer + TTS**: endpoints operacionais e ferramentas MCP

📖 **Release notes**: Veja [docs/RELEASE_NOTES_v0.27.0.md](docs/RELEASE_NOTES_v0.27.0.md)

---

## Arquitetura

BEAGLE segue uma arquitetura **Rust-first** com pipelines científicos em Julia:

- **Núcleo Rust**: `beagle-llm`, `beagle-monorepo`, `beagle-triad`, `beagle-feedback`, `beagle-memory`
- **Pipelines Julia**: PBPK, Heliobiology, Scaffolds, PCS, KEC
- **Cloud-first LLM**: MiniMax/Z.ai (alto throughput) → Grok (robustez) → DeepSeek (math)
- **Storage centralizado**: `BEAGLE_DATA_DIR` para todos os artefatos

## Quick Start

### 1. Configurar Ambiente

```bash
export BEAGLE_PROFILE=dev  # ou lab, prod
export BEAGLE_DATA_DIR=~/beagle-data
export XAI_API_KEY=your-grok-api-key
```

### 2. Iniciar Core Server

```bash
cargo run -p beagle-monorepo --bin core_server
```

### 3. Iniciar MCP Server (Opcional)

```bash
cd beagle-mcp-server
npm install
npm run build
MCP_AUTH_TOKEN=your-token npm start
```

### 4. Conectar ChatGPT/Claude e rodar Darwin

- MCP: [docs/BEAGLE_MCP.md](docs/BEAGLE_MCP.md)
- Dev-Canon runbook (systemd + Darwin): [docs/DEV_CANON_RUNBOOK.md](docs/DEV_CANON_RUNBOOK.md)
- Exocortex roadmap 2026: [docs/EXOCORTEX_ROADMAP_2026.md](docs/EXOCORTEX_ROADMAP_2026.md)

## Documentação

- [BEAGLE_MCP.md](docs/BEAGLE_MCP.md) - Guia do MCP Server
- [BEAGLE_CORE_v0_1.md](docs/BEAGLE_CORE_v0_1.md) - Documentação técnica do core
- [RELEASE_NOTES_v0.27.0.md](docs/RELEASE_NOTES_v0.27.0.md) - Release notes v0.27.0
- [CHANGELOG.md](docs/CHANGELOG.md) - Histórico de mudanças

## Features

### Memory, MCP & Exocortex
- ✅ Memory Engine com GraphRAG
- ✅ MCP Server para ChatGPT/Claude
- ✅ RAG injection no pipeline

### DARWIN ResearchOps (RAG contínuo)
- ✅ Indexação incremental via git (add/modify/delete)
- ✅ Collections separadas no Qdrant: `darwin-repos`, `darwin-papers`, `darwin-docs`, `darwin-books`
- ✅ Auto-update via systemd timers
- ✅ Push trigger via GitHub webhook

### Pipeline Científico
- ✅ Pipeline v0.1 (Darwin + Observer + HERMES)
- ✅ Triad adversarial (ATHENA, HERMES, ARGOS)
- ✅ Science jobs (PBPK, Helio, Scaffold, PCS, KEC)

### Experimental
- ✅ Serendipity Engine (lab/prod)
- ✅ Void deadlock detection
- ✅ Continuous learning (feedback system)

## Contribuindo

Este é um projeto pessoal de pesquisa. Para questões ou sugestões, abra uma issue.

## Licença

MIT OR Apache-2.0

---

**BEAGLE v0.27.0** - Exocortex ResearchOps | [Release Notes](docs/RELEASE_NOTES_v0.27.0.md) | [Changelog](docs/CHANGELOG.md)
