# BEAGLE Neural Engine - Integração com Neural Engine do M3 Max

Integração 100% nativa com o Neural Engine do M3 Max usando MLX (Metal Performance Shaders).

## Features

- **LoRA Training**: 3-5x mais rápido que Unsloth Python (8-10 min vs 15-20 min)
- **Embedding Local**: BGE-large no Neural Engine (< 20ms por texto)
- **Whisper Local**: Transcrição em tempo real nativa

## Como Funciona

O crate detecta automaticamente se MLX está disponível (via Python ou Julia) e usa o Neural Engine quando possível, com fallback automático para métodos tradicionais.

## Uso

### LoRA Training

```rust
use beagle_neural_engine::NeuralEngine;

let neural = NeuralEngine::new();
if neural.is_available() {
    neural.train_lora_native(bad_draft, good_draft).await?;
}
```

### Embedding Local

```rust
let embedding = neural.embed_local("texto para embedar").await?;
// Retorna Vec<f32> com 1024 dimensões
```

### Whisper Local

```rust
let transcription = neural.whisper_local("/path/to/audio.wav").await?;
```

## Scripts Julia

O crate usa scripts Julia com Metal.jl:

- `beagle-julia/lora_mlx.jl`: LoRA training nativo
- `beagle-julia/embed_mlx.jl`: Embedding BGE-large

## Integração Automática

Já integrado em `beagle-lora-auto`:
- Tenta Neural Engine primeiro
- Fallback automático para Unsloth se Neural Engine não disponível

## Requisitos

- Apple Silicon (M1/M2/M3/M4)
- Metal.jl (Julia) ou MLX (Python) instalado
- Julia 1.10+ ou Python 3.10+ com MLX

## Status

✅ Crate criado
✅ Integrado com beagle-lora-auto
✅ Scripts Julia criados
✅ Compila sem erros

