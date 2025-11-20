# 🚀 BEAGLE-JULIA - Quick Start

## Setup em 5 minutos

```bash
# 1. Instalar Julia (se não tiver)
curl -fsSL https://install.julialang.org | sh

# 2. Entrar no diretório
cd beagle-julia

# 3. Rodar setup
bash setup.sh

# 4. Testar
julia --project=. -e 'using BeagleQuantum; demo()'
```

## Uso Básico

```julia
using BeagleQuantum

# Criar conjunto de hipóteses
set = HypothesisSet()

# Adicionar hipóteses
add!(set, "Hipótese 1")
add!(set, "Hipótese 2")
add!(set, "Hipótese 3")

# Aplicar interferência com evidência
interference!(set, "evidência que favorece hipótese 2", 1.5)

# Colapsar superposição
result = collapse(set, strategy=:probabilistic)
println(result)
```

## Exemplos

```bash
# Demo interativa
julia --project=. examples/demo.jl

# Rodar testes
julia --project=. -e 'using Pkg; Pkg.test("BeagleJulia")'

# Benchmarks
julia --project=. benchmarks/benchmark.jl
```

## Estrutura

```
beagle-julia/
├── src/
│   └── BeagleQuantum.jl    # Módulo principal
├── test/
│   └── BeagleQuantumTests.jl
├── examples/
│   └── demo.jl
├── benchmarks/
│   └── benchmark.jl
├── Project.toml
└── README.md
```

## Próximos Passos

1. **Embeddings**: Integrar TextEmbeddings.jl para interferência semântica real
2. **Multi-Agent**: Portar orchestrator do Rust
3. **LoRA**: Implementar training com Lux.jl + MLX
4. **Fractal**: Adicionar core recursivo

---

**Bora meter bronca! 🔥**




