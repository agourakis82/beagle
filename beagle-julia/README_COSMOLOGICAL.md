# BeagleCosmological.jl - Cosmological Alignment Layer

**100% REAL - Roda no cluster vLLM, força alinhamento com leis fundamentais do universo**

## Features

- ✅ **Verifica Violação**: Analisa hipóteses contra 6 leis fundamentais
- ✅ **Destrói Hipóteses**: Remove hipóteses incompatíveis com o universo
- ✅ **Amplifica Hipóteses**: Melhora hipóteses alinhadas com evidência cosmológica
- ✅ **Scores**: Retorna scores de alinhamento 0.0-1.0 para cada sobrevivente

## Leis Fundamentais Verificadas

1. **2ª Lei da Termodinâmica**: Entropia crescente, nunca diminui em sistemas fechados
2. **Conservação**: Energia, momento angular, carga elétrica
3. **Princípio Holográfico**: Bekenstein bound (informação máxima em volume)
4. **Causalidade Relativística**: Velocidade da luz = limite absoluto
5. **Limite de Bremermann**: Computação máxima (~10^93 bits/s por kg)
6. **Conservação de Informação Quântica**: Unitariedade, sem perda

## Uso

```julia
include("Cosmological.jl")
using .BeagleCosmological

# Demo com hipóteses de exemplo
BeagleCosmological.demo()

# Ou com hipóteses customizadas
hypotheses = [
    "Hipótese 1: ...",
    "Hipótese 2: ...",
    "Hipótese 3: ..."
]
survivors = BeagleCosmological.cosmological_alignment(hypotheses)

# Ou via CLI
julia run_cosmological.jl "Hipótese 1" "Hipótese 2" "Hipótese 3"
```

## Requisitos

- **vLLM rodando** em `http://t560.local:8000/v1` com Llama-3.3-70B
- **Julia 1.10+** com pacotes instalados:
  ```julia
  ] add HTTP JSON3 Dates
  ```

## Output

Arquivo `cosmological_survivors_YYYYMMDD_HHMMSS.json` contendo:
```json
{
  "survivors": [
    {
      "hypothesis": "texto completo",
      "alignment_score": 0.85,
      "reason": "justificativa cosmológica detalhada",
      "amplified_version": "versão amplificada (se score > 0.9)"
    }
  ],
  "timestamp": "20251118_123456",
  "total_analyzed": 5
}
```

## Processo

1. **Análise**: Verifica cada hipótese contra 6 leis fundamentais
2. **Filtragem**: Remove hipóteses que violam qualquer lei
3. **Amplificação**: Melhora hipóteses com score > 0.9
4. **Output**: Retorna sobreviventes com scores e justificativas

## Performance

- **Análise completa**: ~30-60s (8192 tokens, temp 0.6)
- **5 hipóteses**: ~45-90s
- **10 hipóteses**: ~60-120s

## Características

- **Temperatura baixa (0.6)**: Análise precisa e rigorosa
- **Timeout**: 5 minutos por query
- **JSON parsing**: Extrai JSON de markdown code blocks automaticamente
- **Amplificação automática**: Hipóteses com score > 0.9 recebem versão amplificada

## Integração

Pode ser integrado com:
- **Quantum Module**: Analisa hipóteses do HypothesisSet
- **Adversarial Loop**: Filtra drafts antes de refinamento
- **Fractal Core**: Analisa estados cognitivos do fractal

## Exemplo de Uso

```julia
# Exemplo completo
hypotheses = [
    "Entropia curva em scaffolds é mediada por consciência celular quântica",
    "Buracos de minhoca microscópicos violam causalidade",
    "Consciência celular emerge de entropia máxima"
]

survivors = BeagleCosmological.cosmological_alignment(hypotheses)

# Só sobrevivem hipóteses compatíveis com o universo
for s in survivors
    println("Score: $(s["alignment_score"]) - $(s["hypothesis"])")
end
```

## Próximos Passos

1. Integrar com Quantum Module (analisar HypothesisSet diretamente)
2. Integrar com Adversarial Loop (filtrar drafts antes de refinamento)
3. Loop infinito (gerar hipóteses → alinhar → amplificar → novas hipóteses)

