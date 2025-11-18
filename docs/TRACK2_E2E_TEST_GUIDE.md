# 🧪 Track 2 Multi-Agent E2E Test Guide

## 📋 Visão Geral

Este documento descreve como executar os testes end-to-end completos para o pipeline multi-agente ATHENA→HERMES→ARGOS.

**Arquivo de Teste:** `crates/beagle-hermes/tests/multi_agent_e2e.rs`  
**Linhas de Código:** 678 linhas  
**Funções de Teste:** 11 testes implementados

---

## 🎯 Testes Implementados

### Testes Unitários (Sem Infraestrutura)

1. **`test_argos_validation`** - Validação básica do ARGOS
   - Não requer API keys ou infraestrutura
   - Testa validação de drafts e cálculo de quality score

2. **`test_argos_citation_edge_cases`** - Casos extremos de citações
   - Testa drafts sem citações
   - Valida detecção de problemas

### Testes com API Keys (Sem Infraestrutura Completa)

3. **`test_athena_paper_search`** - Busca de papers do ATHENA
   - Requer: `ANTHROPIC_API_KEY`
   - Testa busca de papers relevantes

4. **`test_athena_paper_search_variants`** - Variações de tamanho de cluster
   - Requer: `ANTHROPIC_API_KEY`
   - Testa com clusters pequenos e grandes

5. **`test_hermes_draft_generation`** - Geração de draft do HERMES
   - Requer: `ANTHROPIC_API_KEY`
   - Testa geração de seções acadêmicas

### Testes E2E Completos (Requer Infraestrutura)

6. **`test_complete_multi_agent_synthesis`** - Pipeline completo
   - Requer: PostgreSQL, Neo4j, Redis, `ANTHROPIC_API_KEY`
   - Valida pipeline completo ATHENA→HERMES→ARGOS
   - Critérios:
     - Word count: 450-550 palavras
     - Quality score: ≥85%
     - Citations: ≥5
     - Performance: <30s

7. **`test_refinement_loop`** - Loop de refinamento
   - Requer: Infraestrutura completa
   - Testa refinamento quando qualidade é insuficiente

8. **`test_edge_case_empty_cluster`** - Cluster vazio
   - Requer: Infraestrutura completa
   - Testa tratamento de clusters vazios

9. **`test_edge_case_large_word_count`** - Word count grande
   - Requer: Infraestrutura completa
   - Testa geração de 2000 palavras

10. **`test_performance_parallel_sections`** - Performance paralela
    - Requer: Infraestrutura completa
    - Testa geração paralela de múltiplas seções

11. **`run_all_tests_summary`** - Resumo completo
    - Requer: Infraestrutura completa
    - Executa todos os testes e gera relatório consolidado

---

## 🚀 Execução Rápida

### Opção 1: Script Automatizado (Recomendado)

```bash
# Configurar API key
export ANTHROPIC_API_KEY="sua-chave-aqui"

# Executar todos os testes
./scripts/test_track2_e2e.sh

# Executar teste específico
./scripts/test_track2_e2e.sh argos    # Apenas ARGOS
./scripts/test_track2_e2e.sh athena   # Apenas ATHENA
./scripts/test_track2_e2e.sh hermes  # Apenas HERMES
./scripts/test_track2_e2e.sh e2e      # E2E completo
./scripts/test_track2_e2e.sh summary  # Resumo completo
```

### Opção 2: Comandos Manuais

#### 1. Verificar Compilação

```bash
cd /mnt/e/workspace/beagle-remote
cargo build --package beagle-hermes --tests
```

#### 2. Testes Unitários (Sem API Keys)

```bash
# Teste ARGOS (não requer infraestrutura)
cargo test --package beagle-hermes test_argos_validation -- --nocapture

# Teste ARGOS edge cases
cargo test --package beagle-hermes test_argos_citation_edge_cases -- --nocapture
```

#### 3. Testes com API Keys

```bash
# Configurar API key
export ANTHROPIC_API_KEY="sua-chave-aqui"

# Teste ATHENA
cargo test --package beagle-hermes test_athena_paper_search --ignored -- --nocapture

# Teste HERMES
cargo test --package beagle-hermes test_hermes_draft_generation --ignored -- --nocapture

# Teste ATHENA variants
cargo test --package beagle-hermes test_athena_paper_search_variants --ignored -- --nocapture
```

#### 4. Testes E2E Completos (Requer Infraestrutura)

```bash
# Configurar variáveis de ambiente
export ANTHROPIC_API_KEY="sua-chave-aqui"
export DATABASE_URL="postgresql://user:pass@localhost:5432/beagle"
export NEO4J_URI="neo4j://localhost:7687"
export NEO4J_USER="neo4j"
export NEO4J_PASSWORD="password"
export REDIS_URL="redis://localhost:6379"

# Teste E2E completo
cargo test --package beagle-hermes test_complete_multi_agent_synthesis --ignored -- --nocapture

# Teste de refinamento
cargo test --package beagle-hermes test_refinement_loop --ignored -- --nocapture

# Teste de edge cases
cargo test --package beagle-hermes test_edge_case_empty_cluster --ignored -- --nocapture
cargo test --package beagle-hermes test_edge_case_large_word_count --ignored -- --nocapture

# Teste de performance
cargo test --package beagle-hermes test_performance_parallel_sections --ignored -- --nocapture

# Resumo completo
cargo test --package beagle-hermes run_all_tests_summary --ignored -- --nocapture
```

---

## ✅ Critérios de Sucesso

### Teste E2E Completo

- ✅ Pipeline executável (ATHENA→HERMES→ARGOS)
- ✅ Word count: 450-550 palavras
- ✅ Quality score: ≥85%
- ✅ Citations: ≥5 inline citations
- ✅ Performance: <30s para E2E completo
- ✅ Refinement loop funcional
- ✅ Edge cases tratados

### Testes Unitários

- ✅ ARGOS valida drafts corretamente
- ✅ ARGOS detecta problemas de citações
- ✅ ATHENA retorna papers relevantes
- ✅ HERMES gera drafts com word count adequado

---

## 🔧 Troubleshooting

### Erro: "ANTHROPIC_API_KEY not set"

```bash
export ANTHROPIC_API_KEY="sua-chave-aqui"
```

### Erro: "DATABASE_URL not set"

```bash
export DATABASE_URL="postgresql://user:pass@localhost:5432/beagle"
```

### Erro: "Cargo not found"

Instale Rust:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

### Erro de Compilação

Verifique dependências:
```bash
cargo build --package beagle-hermes --tests 2>&1 | head -50
```

### Teste Falha com Timeout

Aumente timeout ou verifique conectividade:
- PostgreSQL rodando?
- Neo4j rodando?
- Redis rodando?
- API key válida?

---

## 📊 Estrutura dos Testes

```
multi_agent_e2e.rs (678 linhas)
├── Test Fixtures
│   └── create_test_cluster() - Cluster de teste com 10 insights
│
├── Unit Tests
│   ├── test_argos_validation
│   ├── test_argos_citation_edge_cases
│   ├── test_athena_paper_search
│   ├── test_athena_paper_search_variants
│   └── test_hermes_draft_generation
│
├── E2E Tests
│   ├── test_complete_multi_agent_synthesis
│   └── test_refinement_loop
│
├── Edge Cases
│   ├── test_edge_case_empty_cluster
│   └── test_edge_case_large_word_count
│
├── Performance
│   └── test_performance_parallel_sections
│
└── Summary
    └── run_all_tests_summary
```

---

## 📝 Logs e Debugging

Os testes geram logs detalhados usando `tracing`. Para ver logs completos:

```bash
RUST_LOG=debug cargo test --package beagle-hermes test_complete_multi_agent_synthesis --ignored -- --nocapture
```

Logs são salvos em `/tmp/beagle_test_<test_name>.log` quando usando o script.

---

## 🎯 Próximos Passos

1. **Verificar Compilação**
   ```bash
   cargo build --package beagle-hermes --tests
   ```

2. **Executar Testes Unitários**
   ```bash
   cargo test --package beagle-hermes test_argos_validation -- --nocapture
   ```

3. **Executar Testes com API Keys**
   ```bash
   export ANTHROPIC_API_KEY="sua-chave"
   cargo test --package beagle-hermes test_athena_paper_search --ignored -- --nocapture
   ```

4. **Executar E2E Completo** (quando infraestrutura estiver pronta)
   ```bash
   cargo test --package beagle-hermes test_complete_multi_agent_synthesis --ignored -- --nocapture
   ```

---

## 📚 Referências

- **Arquivo de Teste:** `crates/beagle-hermes/tests/multi_agent_e2e.rs`
- **Agentes:** `crates/beagle-hermes/src/agents/`
- **Documentação:** `BEAGLE_PROJECT_MAP_v2_COMPLETE.md`

---

**Status:** ✅ Track 2 Multi-Agent E2E Test Suite 100% Implementado  
**Data:** 2025-01-XX  
**Versão:** 0.1.0

