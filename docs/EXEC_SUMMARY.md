# BEAGLE - Resumo Executivo

## Objetivo
Exocórtex cognitivo que elimina fragmentação através de interface unificada e persistente.

## Stack
- **Core**: Rust (Axum, SQLx, Tokio)
- **Desktop**: Tauri 2.0
- **Mobile**: Swift + SwiftUI
- **LLM**: Claude Haiku 4.5 (primário, 80%) + Sonnet 4.5 (15%) + Gemini 1.5 Pro (5%)
- **Databases**: PostgreSQL + pgvector, Neo4j, Qdrant
- **Infraestrutura**: Kubernetes (5 nós), Darwin Core hypergraph backend

## Arquitetura (7 Camadas)
1. **Infrastructure** – Darwin Core, hipergrafo e ferramentas de rede
2. **Tools** – Integradores (PubMed, arXiv, GitHub, Zotero)
3. **Memory** – Memória ativa (working), episódica, semântica, procedimental
4. **Models** – Claude Haiku como primário, roteamento para Sonnet/Gemini
5. **Agents** – Researcher, Critic, Synthesizer, Writer, Coder, Meta
6. **Orchestration** – Meta-agent coordenador
6.5 **Personality Engine** – Adaptação contextual por projeto
7. **UX** – Interface unificada (Tauri desktop, extensão mobile, CLI avançada)

## Phase 0 (Semanas 1-2)
- **Semana 1**: Auditoria Darwin (inventário, endpoints críticos, classificação por camada), setup infra básica (K8s saudável, bancos provisionados, CI/CD mínimo)
- **Semana 2**: Migrar `beagle-hypergraph` para API Axum, expor endpoints `/graph/*`, implementar esqueleto do meta-agent e pipeline de memória, validar sync inicial com `beagle-sync`

## Status Atual
- ✅ Repositórios mapeados (beagle, darwin-core, darwin-workspace)
- ✅ Workspace Rust consolidado (crates: server, hypergraph, llm, sync)
- 🔄 Artefatos legados arquivados em `legacy/`
- ⏳ Auditoria Darwin e setup de bancos/K8s em planejamento

## Próximos Passos
1. Executar auditoria Darwin – gerar `docs/DARWIN_AUDIT.md`
2. Provisionar PostgreSQL + pgvector, Neo4j e Qdrant no cluster
3. Implementar `beagle-server` com endpoints `GET /health`, `POST /agents/route`
4. Integrar `beagle-hypergraph` ao servidor (consulta e mutação)
5. Documentar plano de migração contínua e estratégia de commits
