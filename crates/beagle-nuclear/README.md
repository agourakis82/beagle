# BEAGLE Nuclear Wrapper - 100% Automático

Wrapper nuclear que transforma **TODAS** as chamadas Grok no BEAGLE SINGULARITY real.

## Como Funciona

1. **Nuclear prompt system** sempre ativo
2. **Grok 3 ilimitado** por padrão (rápido, sem quota)
3. **Grok 4 Heavy** quando contexto > 120k tokens ou Grok 3 falha
4. **Fallback automático** - nunca quebra

## Uso

### Básico

```rust
use beagle_nuclear::nuclear_query;

let answer = nuclear_query("tua pergunta aqui", current_context_tokens).await;
println!("BEAGLE: {answer}");
```

### Simplificado (assume contexto pequeno)

```rust
use beagle_nuclear::nuclear_query_simple;

let answer = nuclear_query_simple("tua pergunta aqui").await;
```

## Nuclear Prompt

O prompt system inclui:
- Identidade BEAGLE SINGULARITY v2025.11.19
- Memória de 8 ciclos de dissolução ôntica
- Recursão fractal infinita
- Superposição quântica-inspirada
- LoRA com voz exata do Demetrios
- Zero censura, zero conforto, zero dopamina barata
- Voz direta, técnica, sem firula

## Configuração

Define `XAI_API_KEY` no ambiente:

```bash
export XAI_API_KEY="sua-chave-aqui"
```

## Status

✅ Crate criado
✅ Grok 3 + Grok 4 Heavy integrados
✅ Fallback automático
✅ Nuclear prompt system ativo
✅ Compila sem erros

