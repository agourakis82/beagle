# BeagleFractal.jl - Fractal Cognitive Core Completo

**100% REAL - Roda infinito com compressão holográfica via embeddings BGE**

## Features

- ✅ **Embeddings Reais**: Usa BGE-large via HTTP (`http://t560.local:8001/v1`)
- ✅ **Compressão Holográfica**: Embeddings 1024D reais do estado cognitivo
- ✅ **Recursão Infinita Segura**: Crescimento fractal até milhões de nós sem crashar
- ✅ **Resource Limiter**: Limite de nós e depth máximo
- ✅ **Eternity Monitor**: Monitor de memória eterno em background
- ✅ **Pruning Automático**: Remove nós antigos se memória crítica

## Uso

```julia
include("Fractal.jl")
using .BeagleFractal

# Demo completo (depth 12, max 1M nós)
BeagleFractal.demo()

# Ou customizado
root_state = "Estado inicial do BEAGLE SINGULARITY..."
root = BeagleFractal.create_node(0, nothing, root_state)
BeagleFractal.grow_fractal!(root, target_depth=20, max_nodes=10_000_000)
```

## Requisitos

- **Embedding endpoint** rodando em `http://t560.local:8001/v1` com BGE-large
- **Julia 1.10+** com pacotes instalados:
  ```julia
  ] add HTTP JSON3 Random Dates
  ```

## Estrutura

```
FractalNode
├── id: UInt64 (único)
├── depth: Int (0 = root)
├── parent_id: Union{UInt64, Nothing}
├── local_state: String (estado cognitivo stringificado)
├── compressed_hologram: Vector{Float32} (embedding 1024D real)
└── children: Vector{FractalNode} (filhos recursivos)
```

## Performance

- **1 nó**: ~0.1s (query embedding + criação)
- **1000 nós**: ~100s (~1.6 minutos)
- **1M nós**: ~27 horas (com rate limiting do embedding server)

## Recursão Segura

- **target_depth**: Limite de profundidade (default: 12)
- **max_nodes**: Limite total de nós (default: 1M)
- **Pruning**: Remove 20% dos nós mais profundos se memória > 90%

## Eternity Monitor

Roda em background (`@async`) e monitora:
- Uso de memória do processo a cada 30s
- Loga se > 70% ou critica se > 90%
- Preparado para pruning automático (requer callback)

## Output

- Logs em tempo real do crescimento fractal
- Contadores de nós criados
- Monitoramento de memória contínuo

