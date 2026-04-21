# Backlog híbrido — BEAGLE v0.3 (release notes) + restoration plan

**Fontes:** `docs/BEAGLE_v0_3_RELEASE_NOTES.md` (*Próximos Passos*), `docs/BEAGLE_RESTORATION_PLAN.md` (Fase 1–2), cruzamento com o código em **2026-03-31**.

**Prioridade de produto:** Memory & MCP, experimentação, retrieval/GraphRAG, compute/workspace; editorial como downstream.

---

## Inventário — *Próximos Passos* (v0.3)

| # | Item | Estado actual (código/repo) | Epic alvo |
|---|------|----------------------------|-----------|
| 1 | VoidNavigator + `beagle-ontic` | ✅ `beagle-void` e `beagle-ontic` **habilitados** como features opcionais (`ontic`, `void`). <br>✅ `pipeline_void.rs` integra VoidNavigator real quando feature `void` ativa. <br>✅ Endpoint `/dev/void` expõe API REST para navegação no vazio. <br>✅ 75 testes passando (26 ontic + 49 void). <br>✅ Compilação: `cargo build --features "ontic void"` | **P1 — CONCLUÍDO** ✅ |
| 2 | Qdrant — melhorar busca semântica | `beagle-memory` já tem `qdrant_url`, `MemoryVectorIndex`, upsert/search, filtros payload (`engine.rs`). Gap = **operacional** (coleção, dimensão, health) e **observabilidade** (métricas, degradação clara vs índice local). | **P1 — Hardening** (health check, métricas, testes de integração com Qdrant de teste). |
| 3 | OAuth multi-utilizador (MCP) | `beagle-mcp-server/src/auth.ts`: **apenas** bearer token único (`MCP_AUTH_TOKEN`). Sem OAuth, sem multi-tenant. | **P2 — Epic OAuth** (fluxo + armazenamento de tokens + rotação). |
| 4 | Streaming (respostas longas) | Sem referências a streaming nas tools TS analisadas; pipeline MCP provavelmente **request/response completo**. | **P2 — Epic streaming** (SSE ou chunking; contrato com core). |
| 5 | Webhooks (jobs/pipelines) | Sem `webhook` no código TS do servidor MCP. | **P2 — Epic webhooks** (registo de URL, HMAC, retries). |

---

## Inventário — Restoration plan (Fase 1 entregáveis)

| Entregável (plano) | Caminho no repo | Estado |
|--------------------|-----------------|--------|
| Script audit | `scripts/audit_system.sh` | **Existe** |
| Check serviços externos | `scripts/check_external_services.sh` | **Existe** |
| `generate_reality_report.sh` | `scripts/generate_reality_report.sh` | **Adicionado neste trabalho** |
| `categorize_mocks.sh` | — | **Ainda falta** (opcional; há `audit/reports/MOCK_INVENTORY.md` estático) |
| `COMPILATION_STATUS.md` | `audit/reports/COMPILATION_STATUS.md` | **Existe** |
| `EXTERNAL_DEPENDENCIES.md` | `audit/reports/EXTERNAL_DEPENDENCIES.md` | **Existe** |
| `MOCK_INVENTORY.md` | `audit/reports/MOCK_INVENTORY.md` | **Existe** |
| `FUNCTIONALITY_GAPS.md` | `audit/FUNCTIONALITY_GAPS.md` | **Ainda falta** (pode gerar-se a partir deste doc) |
| `CRITICAL_PATHS.md` | `audit/CRITICAL_PATHS.md` | **Ainda falta** |

Nota: o restoration plan referia `audit/COMPILATION_STATUS.md`; o layout efectivo é **`audit/reports/*.md`**.

---

## Matriz P0 / P1 / P2

- **P0 — Integridade do exocortex (fazer primeiro na prática)**  
  - Manter `cargo check` / testes nos crates **memory + monorepo + mcp** alinhados ao MSRV do projeto (container se o host for antigo).  
  - Correr `./scripts/audit_system.sh` periodicamente ou `./scripts/generate_reality_report.sh` para snapshot.  
  - Não afirmar features MCP (OAuth/stream/webhooks) até existirem testes ou flags.

- **P1 — Próximos passos “hard” v0.3 (código Beagle)**  
  - ✅ Qdrant: health + métricas + testes de integração. **CONCLUÍDO**  
  - ✅ Void: feature flag + reactivação gradual de `beagle-ontic` / void navigator. **CONCLUÍDO**

- **P2 — Rest expansion + MCP nice-to-have**  
  - 🟡 Streaming: `beagle_llm_complete_stream` tool adicionado (simulação via chunking). **PARCIAL** - precisa streaming real do core.
  - ✅ `FUNCTIONALITY_GAPS.md`: Criado em `audit/FUNCTIONALITY_GAPS.md`  
  - ✅ `CRITICAL_PATHS.md`: Criado em `audit/CRITICAL_PATHS.md`  
  - ⏳ OAuth, webhooks: Aguardando próximo sprint.  
  - ⏳ `categorize_mocks.sh`: Opcional, baixa prioridade.

---

## Próximo epic recomendado (um só)

**Epic:** *Qdrant + memory observability slice* — **em progresso / primeira fatia entregue**  
**Porquê:** já há integração larga em `beagle-memory`; melhorar fiabilidade e visibilidade desbloqueia o resto do spine de retrieval sem dependências filosóficas (`ontic`).  
**Critérios de aceitação:**  
1. ~~Endpoint ou log estruturado “Qdrant up/down” em runtime de memória (ou check no startup).~~ — **GET** `/api/memory/qdrant/health` + log `MemoryEngine Qdrant health snapshot at startup` (`beagle_memory` target).  
2. ~~Pelo menos um teste de integração **opcional** (`#[ignore]` ou feature) que fale contra Qdrant local.~~ — `qdrant_health_probe_integration` em `engine.rs` com `BEAGLE_MEMORY_TEST_QDRANT_URL`.  
3. ~~Documentar env vars em `docs/BEAGLE_MCP.md` ou `beagle-memory` README.~~ — secção em `docs/BEAGLE_MCP.md`.

**Seguinte na fila:** métricas Prometheus (contadores por status Qdrant); retries de transporte para **upsert/search** se ainda faltar cobertura. **VoidNavigator** por feature flag (`beagle-ontic`) continua após observabilidade numérica.

---

## Darwin/HPC

Fora do núcleo deste backlog híbrido; estado live continua a ser lido a partir de `beagle/.artifacts/darwin-hpc/*/smoke.json` quando essa for a frente de trabalho.

---

## Sprint P1 já executado (âmbito mínimo)

- Script `scripts/generate_reality_report.sh` para snapshots de realidade.  
- `audit/FUNCTIONALITY_GAPS.md` e `audit/CRITICAL_PATHS.md`: Documentação de gaps e caminhos críticos. ✅  
- Epic **Qdrant + memory observability**: health endpoint, retries, testes. ✅  
- Epic **VoidNavigator + beagle-ontic**: features `ontic`/`void`, integração, 75 testes. ✅  
- **AgentLlmClient trait**: ~15 arquivos convertidos de `Arc<AnthropicClient>`. ✅  
- **MCP Streaming (P2)**: Tool `beagle_llm_complete_stream` com chunking. 🟡  
- Workspace compilando: `cargo check --workspace --features "ontic void"`. ✅
