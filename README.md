# BEAGLE v0.3.0 - Memory & MCP Layer

**Exocórtex Científico Pessoal** - Rust + Julia + Swift/Tauri

## 🚀 Versão Atual: v0.3.0

BEAGLE v0.3.0 implementa a camada de **Memory & MCP (Model Context Protocol)**, transformando o BEAGLE em um verdadeiro **exocórtex MCP** acessível via ChatGPT e Claude.

### ✨ Novidades v0.3.0

- **Memory Engine**: Memória persistente para todas as conversas (ChatGPT, Claude, Grok, local)
- **MCP Server**: Servidor MCP completo para integração com ChatGPT e Claude
- **Serendipity Integration**: Geração de acidentes férteis interdisciplinares
- **Void Deadlock Detection**: Detecção e resolução de loops cognitivos
- **Security**: Auth e rate limiting no MCP server

📖 **Documentação completa**: Veja [docs/BEAGLE_v0_3_RELEASE_NOTES.md](docs/BEAGLE_v0_3_RELEASE_NOTES.md)

---

## Arquitetura

BEAGLE segue uma arquitetura **Rust-first** com pipelines científicos em Julia:

- **Núcleo Rust**: `beagle-llm`, `beagle-monorepo`, `beagle-triad`, `beagle-feedback`, `beagle-memory`
- **Pipelines Julia**: PBPK, Heliobiology, Scaffolds, PCS, KEC
- **Cloud-first LLM**: Grok 3 Tier 1 (ilimitado), Grok 4 Heavy (casos críticos)
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

### 4. Conectar ChatGPT/Claude

Siga as instruções em [docs/BEAGLE_MCP.md](docs/BEAGLE_MCP.md).

## Documentação

- [BEAGLE_MCP.md](docs/BEAGLE_MCP.md) - Guia do MCP Server
- [BEAGLE_CORE_v0_1.md](docs/BEAGLE_CORE_v0_1.md) - Documentação técnica do core
- [BEAGLE_v0_3_RELEASE_NOTES.md](docs/BEAGLE_v0_3_RELEASE_NOTES.md) - Release notes v0.3.0
- [CHANGELOG.md](docs/CHANGELOG.md) - Histórico de mudanças

## Features

### Memory & MCP
- ✅ Memory Engine com GraphRAG
- ✅ MCP Server para ChatGPT/Claude
- ✅ RAG injection no pipeline

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

### Workbench AGPL Showcase

The Warp-derived Beagle Workbench lives under `apps/warp-workbench` and is
licensed separately as AGPL-3.0-only. That boundary is intentional: terminal UI
experiments can be open and auditable while private Beagle memories, truthsets,
cluster artifacts, credentials, and personal data remain outside GitHub.

---

**BEAGLE v0.3.0** - Memory & MCP Layer | [Release Notes](docs/BEAGLE_v0_3_RELEASE_NOTES.md) | [Changelog](docs/CHANGELOG.md)
