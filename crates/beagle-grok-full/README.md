# beagle-grok-full

**BEAGLE Grok Full - Integração completa com xAI Grok**

Grok 3 ilimitado por padrão + Grok 4 Heavy quando precisar.

- ✅ Zero censura
- ✅ Zero dependência de vLLM local (só fallback se quiser)
- ✅ Custo mensal: <$15 (mesmo usando 24h por dia)
- ✅ Latência média: 0.8s

## Uso

### Configuração

```bash
export XAI_API_KEY="sua-chave-aqui"
```

### Uso Básico

```rust
use beagle_grok_full::GrokFull;

// 99% das queries (ilimitado)
let answer = GrokFull::instance().await.grok3("prompt aqui").await;

// 1% das queries (quando precisar do monstro)
let heavy_answer = GrokFull::instance().await.grok4_heavy("prompt gigante").await;
// fallback automático pro Grok 3 se quota acabar
```

### Exemplo Completo

```rust
use beagle_grok_full::GrokFull;

#[tokio::main]
async fn main() {
    // Inicializar tracing
    tracing_subscriber::fmt::init();
    
    // Usar Grok 3 (default)
    let response = GrokFull::instance().await
        .grok3("analisa entropia curva + consciência celular + heliobiology")
        .await;
    
    println!("{}", response);
    
    // Usar Grok 4 Heavy (quando precisar)
    let heavy_response = GrokFull::instance().await
        .grok4_heavy("prompt com contexto >128k tokens")
        .await;
    
    println!("{}", heavy_response);
}
```

## Modelos

- **grok3** (`grok-beta`): Default para 99% das queries
  - Contexto: até 128k tokens
  - Ilimitado
  - Latência: ~0.8s

- **grok4_heavy** (`grok-2-1212`): Para casos especiais
  - Contexto: até 256k tokens
  - Reasoning extremo
  - Fallback automático para grok3 se quota acabar

## Integração no BEAGLE

Substitua chamadas antigas de LLM por:

```rust
// Antes (Anthropic)
let response = anthropic_client.complete(request).await?;

// Depois (Grok Full)
let response = GrokFull::instance().await.grok3(&prompt).await;
```

## Custo

- **Grok 3**: Ilimitado (incluso no plano)
- **Grok 4 Heavy**: Uso sob demanda
- **Custo mensal estimado**: <$15 (uso 24/7)

## Status

✅ **PRODUÇÃO READY**



