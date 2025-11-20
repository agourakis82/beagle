# BEAGLE - Arquitetura de Coesão Interna

## Visão Geral

Implementação das 4 camadas de coesão interna do BEAGLE, transformando o sistema de um conjunto de módulos "geniais" para um **sistema neuropsiquiátrico computacional** com contrato explícito, testável, auditável e publicável.

## Camadas Implementadas

### 1. Configuração Tipada (`beagle-config`)

**Arquivo**: `crates/beagle-config/src/model.rs`

Estruturas centralizadas para todas as configurações:

- `LlmConfig`: Grok, Claude, OpenAI, vLLM
- `StorageConfig`: Diretório de dados
- `GraphConfig`: Neo4j, Qdrant
- `HermesConfig`: Postgres, Redis
- `BeagleConfig`: Configuração completa

**Loader**: `beagle_config::load()`
- Carrega de variáveis de ambiente (prioridade)
- Opcionalmente sobrepõe com `{data_dir}/config/beagle.toml`
- Merge inteligente preservando precedência de env

**Uso**:
```rust
use beagle_config::load;

let cfg = load();
println!("Profile: {}", cfg.profile);
println!("LLM backends: {}", cfg.has_llm_backend());
```

### 2. Camada de Serviços (`beagle-core`)

**Traits** (`crates/beagle-core/src/traits.rs`):

- `LlmClient`: Abstração para LLMs (Grok, Claude, vLLM, mocks)
- `VectorStore`: Abstração para vector stores (Qdrant, mocks)
- `GraphStore`: Abstração para graph stores (Neo4j, mocks)

**BeagleContext** (`crates/beagle-core/src/context.rs`):

Contexto unificado com injeção de dependências:

```rust
use beagle_core::BeagleContext;
use beagle_config::load;

let cfg = load();
let ctx = BeagleContext::new(cfg).await?;

// Usa traits, não implementações diretas
let answer = ctx.llm.complete("prompt").await?;
let vectors = ctx.vector.query("text", 10).await?;
let graph = ctx.graph.cypher_query("MATCH (n) RETURN n", json!({})).await?;
```

**Mocks** incluídos para testes:
- `MockLlmClient`
- `MockVectorStore`
- `MockGraphStore`

### 3. Telemetria (`tracing` + `run_id`)

**Setup** (`apps/beagle-monorepo/src/main.rs`):

```rust
fn init_tracing() {
    use tracing_subscriber::{EnvFilter, fmt};
    let filter = EnvFilter::from_default_env()
        .add_directive("beagle=info".parse().unwrap());
    fmt()
        .with_env_filter(filter)
        .with_target(false)
        .init();
}
```

**Propagação de `run_id`**:

```rust
#[instrument(skip_all, fields(run_id))]
async fn run_pipeline(question: String) -> Result<()> {
    let run_id = Uuid::new_v4().to_string();
    tracing::Span::current().record("run_id", &run_id.as_str());
    // ...
}
```

Isso fornece:
- Call graph completo da execução
- Latências de cada etapa
- Erros com contexto completo
- Rastreabilidade via `run_id`

### 4. Healthcheck (`beagle-health`)

**Crate**: `crates/beagle-health`

**Checks implementados**:
- ✅ Storage (diretórios existem)
- ✅ LLM backends (chaves/configurações)
- ✅ Neo4j (se configurado)
- ✅ Qdrant (ping HTTP)
- ✅ Postgres (se configurado)
- ✅ Redis (se configurado)

**Uso**:
```rust
use beagle_health::check_all;
use beagle_config::load;

let cfg = load();
let report = check_all(&cfg).await;

println!("Healthy: {}", report.is_healthy());
let (ok, warn, error) = report.count_by_status();
```

**CLI**: `beagle-monorepo doctor`
- Exibe relatório completo
- Salva JSON em `{data_dir}/logs/health_report.json`

## Integração com `beagle-monorepo`

### Comando `doctor`

Atualizado para usar `beagle-health`:

```bash
cargo run --bin beagle-monorepo -- doctor
```

Saída:
```
╔══════════════════════════════════════════════╗
║ BEAGLE Doctor                                ║
╚══════════════════════════════════════════════╝
Profile: dev | SAFE_MODE=true
Data dir: /home/user/beagle-data

📊 Health Report:
  ✅ OK: 4  ⚠️  WARN: 2  ❌ ERROR: 0

🔍 Checks:
  ✅ storage: ok
     └─ /home/user/beagle-data
  ✅ llm_config: ok
     └─ Backends disponíveis: Grok, vLLM
  ⚠️  neo4j: warn
     └─ Neo4j não configurado
  ✅ qdrant: ok
     └─ http://localhost:6333 - conectado
  ...
```

### Pipeline com Tracing

O pipeline agora usa:
- `beagle_config::load()` em vez de env solto
- `#[instrument]` com `run_id` em spans
- `BeagleContext` para injeção de dependências (preparado para integração futura)

## Testes de Integração

**Arquivo**: `apps/beagle-monorepo/tests/pipeline_demo.rs`

Testes que verificam:
- Pipeline completo funciona com mocks
- `BeagleContext` funciona corretamente
- Drafts são criados
- Sem dependência de serviços externos

**Executar**:
```bash
cargo test --package beagle-monorepo --test pipeline_demo
```

## Próximos Passos

### Integração com Darwin

Atualizar `beagle-darwin` para:
1. Receber `&BeagleContext` em vez de criar clientes diretamente
2. Implementar `LlmClient` para Grok/vLLM
3. Implementar `VectorStore` para Qdrant
4. Implementar `GraphStore` para Neo4j

### Integração com HERMES

Atualizar `beagle-hermes` para:
1. Receber `&BeagleContext`
2. Reutilizar `GraphStore` e `LlmClient` compartilhados
3. Manter coerência de fonte de dados

### Implementações Reais

Criar implementações concretas das traits:
- `GrokLlmClient` (usando `beagle-grok-api`)
- `VllmLlmClient` (usando `beagle-llm`)
- `QdrantVectorStore` (usando cliente Qdrant)
- `Neo4jGraphStore` (usando driver Neo4j)

### Observabilidade Avançada

Adicionar:
- OpenTelemetry export
- Métricas Prometheus
- Dashboard de execução

## Estrutura de Arquivos

```
crates/
├── beagle-config/
│   ├── src/
│   │   ├── lib.rs          # Helpers existentes + load()
│   │   └── model.rs         # BeagleConfig tipado
│   └── Cargo.toml
├── beagle-core/
│   ├── src/
│   │   ├── lib.rs
│   │   ├── traits.rs        # LlmClient, VectorStore, GraphStore
│   │   └── context.rs       # BeagleContext + mocks
│   └── Cargo.toml
└── beagle-health/
    ├── src/
    │   └── lib.rs            # Healthchecks
    └── Cargo.toml

apps/
└── beagle-monorepo/
    ├── src/
    │   └── main.rs           # Atualizado com doctor + tracing
    ├── tests/
    │   └── pipeline_demo.rs  # Testes de integração
    └── Cargo.toml
```

## Benefícios

1. **Testabilidade**: Mocks permitem testes sem serviços externos
2. **Manutenibilidade**: Configuração centralizada e tipada
3. **Observabilidade**: Tracing com `run_id` em toda execução
4. **Diagnóstico**: Healthcheck integrado
5. **Evolução**: Traits permitem trocar implementações sem quebrar código
6. **Publicabilidade**: Arquitetura explícita e documentada

## Referências

- [CONFIG_OVERVIEW_BEAGLE.md](../CONFIG_OVERVIEW_BEAGLE.md) - Visão geral de configuração
- [README_STORAGE.md](../README_STORAGE.md) - Estrutura de storage
- [BEAGLE_PROJECT_MAP_v2_COMPLETE.md](../BEAGLE_PROJECT_MAP_v2_COMPLETE.md) - Mapa do projeto

