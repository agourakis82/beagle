# BeagleAdversarial.jl - Adversarial Self-Play Completo

**100% REAL - Roda no cluster vLLM + embeddings BGE + LoRA Lux.jl**

## Features

- ✅ **HERMES**: Gera drafts científicos em estilo Q1 via vLLM real
- ✅ **ARGOS**: Crítica devastadora com score 0-100 via vLLM real  
- ✅ **LoRA Training**: Treinamento real com Lux.jl (CPU/GPU/M3 Max)
- ✅ **Embeddings**: Usa BGE-large via HTTP real (`http://t560.local:8001/v1`)
- ✅ **Loop Iterativo**: Refina até quality >= 98.5% ou max iterações

## Instalação

```julia
# No REPL Julia
] activate .
] add Lux Optimisers Zygote JLD2
```

## Uso

```julia
using .BeagleAdversarial

# Roda completo (com LoRA training)
context = "Entropia curva em scaffolds biológicos é mediada por consciência celular via geometria não-comutativa"
final = BeagleAdversarial.run(context)

# Ou customizado
final = BeagleAdversarial.adversarial_self_play(
    context;
    max_iters=6,
    target_quality=98.5,
    enable_lora_training=true,
    lora_output_dir="lora_adapter"
)
```

## Requisitos

- **vLLM rodando** em `http://t560.local:8000/v1` com Llama-3.3-70B
- **Embedding endpoint** em `http://t560.local:8001/v1` com BGE-large
- **Julia 1.10+** com pacotes instalados

## LoRA Training

O adapter LoRA é treinado incrementalmente a cada melhora de score:
- Usa embeddings reais (BGE-large) via HTTP
- Treina com Lux.jl (compatível CPU/GPU/M3 Max)
- Salva em formato JLD2 para reutilização
- Rank baixo (r=8) para eficiência

## Output

- Draft final salvo em `paper_final_YYYYMMDD_HHMMSS.md`
- LoRA adapters salvos em `lora_adapter_YYYYMMDD_HHMMSS.jld2`

## Performance

- **1 iteração**: ~30-60s (depende do vLLM)
- **6 iterações completas**: ~5-10 minutos
- **LoRA training incremental**: ~10-30s por melhora de score

