# Exemplos de Uso - Grok API Client

## Trocar Anthropic por Grok (1 linha)

### Antes (Anthropic):

```rust
use beagle_llm::AnthropicClient;

let client = AnthropicClient::new("sk-ant-...");
let response = client.complete("Escreve uma introduction sobre entropia curva").await?;
```

### Agora (xAI Grok Heavy):

```rust
use beagle_grok_api::GrokClient;

let client = GrokClient::new("xai-YOUR_API_KEY_HERE");
let response = client.query("Escreve uma introduction sobre entropia curva").await?;
```

**Mesma interface. Mesmo uso. Custo 75-80% menor.**

## Integração nos Módulos Existentes

### No `beagle-cosmo`:

```rust
// src/lib.rs
use beagle_grok_api::GrokClient;

pub struct CosmologicalAlignment {
    llm: GrokClient, // Troca VllmClient por GrokClient
}

impl CosmologicalAlignment {
    pub fn new() -> Self {
        Self { 
            llm: GrokClient::new(&std::env::var("XAI_API_KEY").unwrap())
        }
    }
    
    // Resto do código funciona igual
}
```

### No `beagle-transcend`:

```rust
use beagle_grok_api::GrokClient;

pub struct TranscendenceEngine {
    llm: GrokClient,
}

impl TranscendenceEngine {
    pub fn new() -> Self {
        Self { 
            llm: GrokClient::new(&std::env::var("XAI_API_KEY").unwrap())
        }
    }
    
    // Usa llm.query() igual antes
}
```

### No `beagle-void`:

```rust
use beagle_grok_api::GrokClient;

pub struct VoidNavigator {
    llm: GrokClient, // Troca VllmClient por GrokClient
    dissolution: OnticDissolutionEngine,
}

// Resto igual
```

## Variável de Ambiente

Configure uma vez:

```bash
export XAI_API_KEY='xai-YOUR_API_KEY_HERE'
```

Ou adicione no `.env`:

```
XAI_API_KEY=xai-YOUR_API_KEY_HERE
```

## API Key

Obtenha no [console.x.ai](https://console.x.ai):
- Grok-4-Heavy tem acesso ilimitado até limite do plano
- Custo muito menor que Anthropic
- Zero censura = paradox/void/abyss roda livre

---

**Troca 1 linha. Custo cai 75-80%. Qualidade mantida ou melhor.**

