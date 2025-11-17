# HERMES BPSE - Tarefas Pendentes

**Data:** 17 de Novembro de 2025  
**Status:** Track 5 completo, Tracks 1-4 parcialmente implementados

---

## ✅ COMPLETO

### Track 5: Production Excellence (100%)
- ✅ Observability Stack (Prometheus, Grafana, Loki)
- ✅ Performance Optimization (Redis, gRPC pooling, DB tuning)
- ✅ Security Hardening (JWT, validation)
- ✅ CI/CD Pipeline (GitHub Actions, Docker)

### Track 1: Infrastructure (80%)
- ✅ PROMPT 1.2: Thought Capture Pipeline
- ✅ PROMPT 1.3: Neo4j Knowledge Graph
- ✅ PROMPT 1.4: Background Scheduler
- ✅ PROMPT 1.5: Manuscript State Machine
- ❌ **PROMPT 1.6: Tauri App MVP** ← **FALTA**

---

## ❌ PENDENTE - Track 1

### PROMPT 1.6: Tauri App MVP
**Status:** Não iniciado

**Requisitos:**
- [ ] Tauri 2.0 + React + TypeScript + TailwindCSS
- [ ] Manuscript dashboard (lista de papers)
- [ ] Draft preview (visualização de seções)
- [ ] Voice note upload (drag & drop)
- [ ] Real-time status updates (WebSocket ou polling)

**Arquivos necessários:**
```
crates/beagle-hermes/tauri/
  ├── src-tauri/
  │   ├── Cargo.toml
  │   ├── src/main.rs
  │   └── tauri.conf.json
  ├── src/
  │   ├── App.tsx
  │   ├── components/
  │   │   ├── ManuscriptList.tsx
  │   │   ├── DraftPreview.tsx
  │   │   └── VoiceUpload.tsx
  │   └── styles/
  └── package.json
```

---

## ⚠️ IMPLEMENTAÇÕES PARCIAIS (TODOs)

### 1. Voice Preservation (LoRA Training)
**Arquivo:** `src/voice/trainer.rs`
- [ ] Implementar carregamento de modelo com `candle-transformers`
- [ ] Implementar inicialização de camadas LoRA
- [ ] Implementar loop de treinamento
- [ ] Implementar salvamento com `safetensors`
- [ ] Implementar validação de voz

**Nota:** `candle-core` e `candle-transformers` estão comentados no `Cargo.toml` devido a conflitos de versão.

### 2. Citation Management
**Arquivos:** `src/citations/generator.rs`, `verifier.rs`, `formatter.rs`
- [ ] Implementar chamada real à Semantic Scholar API
- [ ] Implementar verificação de citações
- [ ] Implementar formatação multi-estilo (Vancouver, APA, ABNT, Nature)

### 3. Editor Avançado
**Arquivos:** `src/editor/academic.rs`, `journal.rs`
- [ ] Implementar checagem de terminologia acadêmica
- [ ] Implementar validação de rigor científico
- [ ] Implementar formatação específica por journal

### 4. Integrações Externas
**Arquivos:** `src/integration/word.rs`, `overleaf.rs`, `google_docs.rs`
- [ ] Implementar plugin MS Word
- [ ] Implementar sync com Overleaf
- [ ] Implementar integração Google Docs API

### 5. Security Middleware
**Arquivo:** `src/security/auth.rs`
- [ ] Completar middleware Axum (extrair AuthService de extensions)
- [ ] Implementar autorização baseada em roles
- [ ] Adicionar rate limiting

### 6. Synthesis Engine
**Arquivo:** `src/synthesis/engine.rs`
- [ ] Implementar cálculo real de confidence
- [ ] Integrar com vLLM para geração de texto
- [ ] Implementar validação de voz em tempo real

### 7. Voice Analyzer
**Arquivo:** `src/voice/analyzer.rs`
- [ ] Implementar extração de padrões de sentença
- [ ] Melhorar análise de estrutura de parágrafos

### 8. Scheduler
**Arquivo:** `src/scheduler/synthesis_scheduler.rs`
- [ ] Implementar lógica de cleanup de drafts antigos

---

## 📋 PRÓXIMAS PRIORIDADES

### Prioridade ALTA 🔴
1. **PROMPT 1.6: Tauri App MVP** - Interface do usuário
2. **LoRA Training** - Funcionalidade core de preservação de voz
3. **Semantic Scholar Integration** - Citações automáticas

### Prioridade MÉDIA 🟡
4. **Editor Avançado** - Academic e Journal checks
5. **Security Middleware** - Completar autenticação
6. **Synthesis Engine** - Integração com vLLM

### Prioridade BAIXA 🟢
7. **Integrações Externas** - Word, Overleaf, Google Docs
8. **Voice Analyzer** - Melhorias incrementais
9. **Cleanup Jobs** - Manutenção

---

## 🎯 ESTIMATIVA DE ESFORÇO

| Tarefa | Esforço | Dependências |
|--------|---------|--------------|
| Tauri App MVP | 2-3 dias | React, TypeScript, TailwindCSS |
| LoRA Training | 3-4 dias | Resolver conflitos candle-transformers |
| Semantic Scholar API | 1-2 dias | API key, rate limiting |
| Editor Avançado | 2-3 dias | Dicionários de terminologia |
| Security Middleware | 1 dia | Axum extensions |
| Integrações Externas | 2-3 dias cada | APIs externas |

**Total estimado:** 12-18 dias de desenvolvimento

---

## 📝 NOTAS

1. **candle-transformers**: Precisa resolver conflitos de versão antes de implementar LoRA training
2. **vLLM Integration**: Já está rodando no servidor, precisa conectar com SynthesisEngine
3. **Tauri 2.0**: Framework estável, documentação completa disponível
4. **Semantic Scholar API**: Requer API key (já configurada: `flE0Xf1Q8F4k5yoxskzQi1h26DvihxoEaEXY42oE`)

---

## ✅ CONCLUSÃO

**Status Geral:** ~70% completo

- **Infrastructure:** 80% (falta Tauri App)
- **Core Features:** 60% (falta LoRA, citações completas)
- **Production:** 100% (completo)
- **Integrations:** 20% (apenas estrutura)

**Próximo passo recomendado:** Implementar PROMPT 1.6 (Tauri App MVP) para ter interface funcional.

