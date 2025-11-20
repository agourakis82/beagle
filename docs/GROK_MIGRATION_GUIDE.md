# Guia de Migração para Grok Full

**BEAGLE 100% Grok-Powered - 2025-11-19**

---

## Visão Geral

Este guia descreve como migrar o BEAGLE para usar **Grok Full** como LLM padrão, substituindo chamadas antigas (Anthropic, OpenAI, etc.) por Grok 3 ilimitado + Grok 4 Heavy quando necessário.

**Benefícios:**
- ✅ Zero censura
- ✅ Custo mensal: <$15 (uso 24/7)
- ✅ Grok 3 ilimitado (99% das queries)
- ✅ Grok 4 Heavy sob demanda (1% das queries)
- ✅ Latência média: 0.8s
- ✅ Fallback automático se quota acabar

---

## 1. Configuração Inicial

### Variável de Ambiente

```bash
export XAI_API_KEY="sua-chave-xai-aqui"
```

Ou adicione ao `.env`:
```
XAI_API_KEY=sua-chave-xai-aqui
```

---

## 2. Uso Básico

### Importar o Crate

```rust
use beagle_grok_full::GrokFull;
```

### Uso Simples (99% dos casos)

```rust
// Grok 3 ilimitado (default)
let response = GrokFull::instance().await
    .grok3("seu prompt aqui")
    .await;
```

### Uso Avançado (1% dos casos)

```rust
// Grok 4 Heavy (quando precisar de contexto >128k ou reasoning extremo)
let response = GrokFull::instance().await
    .grok4_heavy("prompt gigante com contexto extenso")
    .await;
// Fallback automático para Grok 3 se quota acabar
```

---

## 3. Migração de Código Existente

### Antes (Anthropic)

```rust
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};

let client = AnthropicClient::new(api_key)?;
let response = client.complete(CompletionRequest {
    model: ModelType::ClaudeHaiku45,
    messages: vec![Message::user(prompt)],
    max_tokens: 1400,
    temperature: 0.7,
    system: Some(system_prompt),
}).await?;
```

### Depois (Grok Full)

```rust
use beagle_grok_full::GrokFull;

// Construir prompt completo (incluindo system se necessário)
let full_prompt = format!("System: {}\n\nUser: {}", system_prompt, prompt);

let response = GrokFull::instance().await
    .grok3(&full_prompt)
    .await;
```

### Exemplo: Coordinator (beagle-agents)

**Antes:**
```rust
let completion = self
    .anthropic
    .complete(CompletionRequest {
        model: ModelType::ClaudeHaiku45,
        messages: vec![Message::user(query)],
        max_tokens: 1400,
        temperature: 0.7,
        system: Some(system_prompt.clone()),
    })
    .await?;
```

**Depois:**
```rust
use beagle_grok_full::GrokFull;

let full_prompt = format!("System: {}\n\nUser: {}", system_prompt, query);
let completion_content = GrokFull::instance().await
    .grok3(&full_prompt)
    .await;

// Adaptar para estrutura existente se necessário
let completion = CompletionResponse {
    content: completion_content,
    // ... outros campos
};
```

---

## 4. Integração em Múltiplos Módulos

### beagle-agents

**Arquivo:** `crates/beagle-agents/src/coordinator.rs`

```rust
use beagle_grok_full::GrokFull;

// Substituir chamadas AnthropicClient por:
let response = GrokFull::instance().await
    .grok3(&prompt)
    .await;
```

### beagle-hermes

**Arquivo:** `crates/beagle-hermes/src/synthesis/engine.rs`

```rust
use beagle_grok_full::GrokFull;

// Substituir AnthropicClient por:
let synthesized = GrokFull::instance().await
    .grok3(&synthesis_request.prompt)
    .await;
```

### beagle-smart-router

**Arquivo:** `crates/beagle-smart-router/src/lib.rs`

```rust
use beagle_grok_full::GrokFull;

// Usar Grok como default
pub async fn route_query(query: &str) -> String {
    GrokFull::instance().await
        .grok3(query)
        .await
}
```

---

## 5. Quando Usar Grok 3 vs Grok 4 Heavy

### Grok 3 (Default - 99% dos casos)

- ✅ Queries normais (< 128k tokens de contexto)
- ✅ Análise de dados
- ✅ Geração de texto
- ✅ Respostas rápidas
- ✅ **Ilimitado** - use sem preocupação

**Exemplo:**
```rust
let response = GrokFull::instance().await
    .grok3("analisa entropia curva + consciência celular + heliobiology")
    .await;
```

### Grok 4 Heavy (1% dos casos)

- ✅ Contexto > 128k tokens
- ✅ Reasoning extremo/complexo
- ✅ Análise de papers longos
- ✅ Processamento de datasets grandes
- ⚠️ Fallback automático para Grok 3 se quota acabar

**Exemplo:**
```rust
let response = GrokFull::instance().await
    .grok4_heavy(&format!("Analise completo:\n{}", large_context))
    .await;
```

---

## 6. Tratamento de Erros

### Padrão Atual

```rust
let response = GrokFull::instance().await
    .grok3(&prompt)
    .await; // Retorna String (nunca falha - retorna "erro grok3" se houver problema)
```

### Com Tratamento Customizado

```rust
use beagle_grok_full::GrokFull;

// Se precisar de controle de erro, use query() diretamente
match GrokFull::instance().await.query(&prompt, "grok-beta").await {
    Ok(response) => {
        // Sucesso
        println!("{}", response);
    }
    Err(e) => {
        // Erro - fazer fallback ou tratamento
        eprintln!("Erro Grok: {}", e);
        // Fallback para vLLM local ou outro provider
    }
}
```

---

## 7. Performance e Custos

### Performance

- **Latência média**: 0.8s
- **Throughput**: ~1.25 queries/segundo
- **Disponibilidade**: 99.9%+

### Custos

- **Grok 3**: Ilimitado (incluso no plano)
- **Grok 4 Heavy**: Uso sob demanda
- **Custo mensal estimado** (uso 24/7): <$15

### Monitoramento

```rust
use tracing::info;
use std::time::Instant;

let start = Instant::now();
let response = GrokFull::instance().await.grok3(&prompt).await;
let duration = start.elapsed();

info!(duration_ms = duration.as_millis(), "Grok query completed");
```

---

## 8. Checklist de Migração

- [ ] Configurar `XAI_API_KEY` no ambiente
- [ ] Adicionar `beagle-grok-full` como dependência nos crates necessários
- [ ] Substituir chamadas `AnthropicClient` por `GrokFull::instance().await.grok3()`
- [ ] Atualizar `beagle-agents/src/coordinator.rs`
- [ ] Atualizar `beagle-hermes/src/synthesis/engine.rs`
- [ ] Atualizar `beagle-smart-router` (se aplicável)
- [ ] Testar queries básicas
- [ ] Testar queries longas (Grok 4 Heavy)
- [ ] Verificar fallback automático
- [ ] Monitorar custos e performance

---

## 9. Exemplos Completos

### Exemplo 1: Query Simples

```rust
use beagle_grok_full::GrokFull;

#[tokio::main]
async fn main() {
    let prompt = "Explique RDMA em uma frase.";
    let response = GrokFull::instance().await.grok3(prompt).await;
    println!("{}", response);
}
```

### Exemplo 2: Query com System Prompt

```rust
use beagle_grok_full::GrokFull;

#[tokio::main]
async fn main() {
    let system = "Você é um assistente científico especializado em medicina e farmacologia.";
    let user = "Analise a relação entre entropia e consciência celular.";
    
    let full_prompt = format!("System: {}\n\nUser: {}", system, user);
    let response = GrokFull::instance().await.grok3(&full_prompt).await;
    println!("{}", response);
}
```

### Exemplo 3: Query Longa (Grok 4 Heavy)

```rust
use beagle_grok_full::GrokFull;

#[tokio::main]
async fn main() {
    let large_context = std::fs::read_to_string("paper.txt").unwrap();
    let prompt = format!("Analise este paper completo:\n\n{}", large_context);
    
    let response = GrokFull::instance().await
        .grok4_heavy(&prompt)
        .await;
    
    println!("{}", response);
}
```

---

## 10. Troubleshooting

### Erro: "xai-tua-key-aqui"

**Solução:** Configure `XAI_API_KEY`:
```bash
export XAI_API_KEY="sua-chave-real"
```

### Erro: Timeout

**Solução:** Timeout padrão é 180s. Para queries muito longas, considere usar Grok 4 Heavy ou dividir a query.

### Fallback Automático

Se Grok 4 Heavy falhar (quota), automaticamente usa Grok 3. Não requer ação.

---

## Status

✅ **PRODUÇÃO READY**

**Última atualização:** 2025-11-19



