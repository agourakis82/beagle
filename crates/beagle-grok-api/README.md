# BEAGLE Grok API - Wrapper Rust para xAI Grok

Wrapper completo para API xAI Grok 4 / Grok 4 Heavy.

## 🚀 Vantagens

- **Custo 75-80% menor** que Anthropic
- **Contexto 256k real** (sem derretimento)
- **Zero censura** (paradox/void/abyss roda livre)
- **Qualidade igual ou melhor** em reasoning longo
- **100% compatível** com estilo do código atual (mesmo padrão vLLM client)

## 📦 Uso

### Básico

```rust
use beagle_grok_api::GrokClient;

// Cria cliente (usa Grok-4-Heavy por padrão)
let client = GrokClient::new("xai-YOUR_API_KEY");

// Query simples (compatível com query_llm atual)
let response = client.query("Escreve uma introduction sobre entropia curva").await?;
```

### Com sistema

```rust
let response = client.chat(
    "Escreve uma introduction científica",
    Some("Tu és Demetrios Chiuratto escrevendo em estilo Q1")
).await?;
```

### Com parâmetros customizados

```rust
let response = client.chat_with_params(
    "Escreve uma introduction",
    None,
    Some(0.7),      // temperature
    Some(4096),     // max_tokens
    Some(0.9),      // top_p
).await?;
```

### Modelo específico

```rust
use beagle_grok_api::{GrokClient, GrokModel};

// Usa Grok-4 normal ao invés de Heavy
let client = GrokClient::with_model("xai-YOUR_API_KEY", GrokModel::Grok4);
```

## 🔑 API Key

Configure no ambiente:

```bash
export XAI_API_KEY='xai-YOUR_API_KEY_HERE'
```

Ou obtenha no [console.x.ai](https://console.x.ai).

## 🧪 Teste

```bash
# Rodar demo
XAI_API_KEY='xai-...' cargo run --package beagle-grok-api --example demo

# Testes unitários
cargo test --package beagle-grok-api
```

## 💰 Custo

- Grok-4-Heavy: Acesso ilimitado até limite do plano (muito mais barato que Anthropic)
- Contexto 256k real sem derretimento
- Zero censura = paradox/void/abyss roda livre

## 🔗 Integração com beagle-llm

O GrokClient está disponível via `beagle-llm` com feature:

```toml
[dependencies]
beagle-llm = { path = "../beagle-llm", features = ["grok"] }
```

```rust
use beagle_llm::GrokClient; // Re-exported
```

---

**Pronto para usar. Custo cai 75-80%. Qualidade mantida ou melhor.**

