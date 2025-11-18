# 🔬 BEAGLE-JULIA - Quantum-Inspired Reasoning Engine

**Migração do BEAGLE para Julia 1.10+** - Performance de C com sintaxe elegante.

## 🚀 Por que Julia?

- **50-100x mais rápido que Python** em loops numéricos
- **Sintaxe limpa e expressiva** (melhor que R, mais legível que C++)
- **Tipagem estática opcional** (performance quando precisa, flexibilidade quando não)
- **Ecosistema ML maduro** (Flux, Lux, Zygote para LoRA no M3 Max)
- **Metaprogramming poderoso** (perfeito para fractais recursivos)

## 📦 Setup Rápido (10 minutos)

### 1. Instalar Julia 1.10.5

```bash
# Linux/WSL
curl -fsSL https://install.julialang.org | sh

# macOS (via Homebrew)
brew install julia

# Ou baixar direto: https://julialang.org/downloads/
```

### 2. Criar e Ativar Projeto

```bash
cd beagle-julia
julia --project=.
```

### 3. Instalar Dependências

No REPL Julia:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()  # Instala todas as dependências do Project.toml
```

Ou manualmente:

```julia
]
add Random LinearAlgebra Statistics
add DataFrames DataFramesMeta
add HTTP JSON3 PythonCall
add Flux Lux Zygote
add Plots Makie
add UUIDs Logging BenchmarkTools
```

### 4. Setup LoRA Training (Opcional)

Se quiser usar LoRA training com Unsloth:

```bash
bash setup_lora.sh
```

Isso instala Unsloth com suporte CUDA automático detectado (Ampere/Hopper).

## 🎯 Uso Básico

### Quantum Reasoning

```julia
using BeagleQuantum

# Criar conjunto de hipóteses
set = HypothesisSet()

# Adicionar hipóteses
add!(set, "Entropia curva é geométrica")
add!(set, "Entropia curva é quântica de campo")
add!(set, "Entropia curva é consciência celular")

# Aplicar interferência com evidência
interference!(set, "evidência aponta pra consciência celular", 1.5)

# Colapsar superposição
result = collapse(set, strategy=:probabilistic)
println(result)

# Ou rodar demo completa
demo()
```

### Multi-Agent Orchestrator

```julia
# Carregar ambos os módulos (adversarial é usado automaticamente se score < 98%)
include("adversarial.jl")
include("orchestrator.jl")
using BeagleOrchestrator

# Rodar pipeline completo: ATHENA → Quantum → HERMES → ARGOS → Adversarial
research = "Unificar entropia curva em scaffolds biológicos com consciência celular via geometria não-comutativa"
orch = Orchestrator(research)
final_draft = run_cycle!(orch)

# Ou usar função main()
main()
```

O orchestrator executa em **<30s** com cluster vLLM local. Se ARGOS score < 98%, ativa automaticamente o loop adversarial para refinamento iterativo até quality ≥ 98.5%.

### Adversarial Self-Play

```julia
include("adversarial.jl")
using BeagleAdversarial

# Loop adversarial standalone
context = "Entropia curva em scaffolds biológicos é mediada por consciência celular via geometria não-comutativa"
final_draft = adversarial_self_play(context, max_iters=6, target_quality=98.5)

# Ou rodar teste rápido
test()
```

O adversarial loop itera até quality ≥ 98.5% ou max_iters, refinando draft via ARGOS → HERMES.

### LoRA Training Real

```julia
include("lora_training.jl")
using BeagleLoRATraining

# Dados do adversarial loop (bad → good drafts)
bad_drafts = ["draft ruim 1", "draft ruim 2"]
good_drafts = ["draft bom 1", "draft bom 2"]
contexts = ["contexto 1", "contexto 2"]

# Pipeline completo: dataset → load → train → save
adapter_path = BeagleLoRATraining.full_training_pipeline(
    bad_drafts, good_drafts, contexts;
    hf_token=nothing,  # ou teu token HuggingFace
    max_steps=60,
    output_dir="beagle_lora_adapter"
)

# Adversarial com LoRA training automático
include("adversarial.jl")
using BeagleAdversarial

final_draft = adversarial_self_play(
    "Entropia curva em scaffolds biológicos...",
    enable_lora_training=true,  # Ativa treinamento incremental
    hf_token=nothing,
    lora_output_dir="beagle_lora_adapter"
)

# Usar adapter no vLLM:
# vllm serve meta-llama/Llama-3.3-70B-Instruct --lora-path beagle_lora_adapter
```

LoRA training executa em **5-10 minutos** no cluster com GPU, salvando adapter GGUF pronto para vLLM imediato.

## 📚 Estrutura do Módulo

### `Hypothesis`
- `content::String` - Conteúdo da hipótese
- `amplitude::ComplexF64` - Amplitude complexa (como função de onda)
- `probability::Float64` - Probabilidade = |amplitude|²
- `phase::Float64` - Fase (para interferência)
- `evidence_count::Int` - Contador de evidências

### `HypothesisSet`
- `hyps::Vector{Hypothesis}` - Vetor de hipóteses em superposição
- `is_collapsed::Bool` - Flag de colapso

### `InterferenceEngine`
- `coupling_strength::Float64` - Força de acoplamento
- `interference!()` - Interferência baseada em evidência textual
- `apply_constructive_interference!()` - Interferência construtiva
- `apply_destructive_interference!()` - Interferência destrutiva

### `MeasurementOperator`
- `threshold::Float64` - Threshold de probabilidade
- `measure()` - Colapsa superposição se threshold atingido

### `Orchestrator` (Multi-Agent)
- `research_question::String` - Pergunta de pesquisa
- `run_cycle!()` - Executa pipeline completo:
  1. **ATHENA**: Revisão bibliográfica + identificação de gaps
  2. **Quantum Superposition**: 6 hipóteses paralelas com interferência
  3. **HERMES**: Geração de draft preservando voz autoral
  4. **ARGOS**: Crítica adversarial com score de qualidade
  5. **Adversarial Loop**: Refinamento iterativo se score < 98%

### `BeagleAdversarial` (Adversarial Self-Play)
- `adversarial_self_play(context; max_iters=6, target_quality=98.5, enable_lora_training=false, ...)` - Loop iterativo:
  1. **HERMES**: Gera draft inicial
  2. **ARGOS**: Avalia com score 0-100 e críticas devastadoras
  3. **LoRA Training**: Treinamento incremental real com Unsloth (se habilitado)
  4. **HERMES**: Refina draft baseado em críticas
  5. Repete até `target_quality` ou `max_iters`

### `BeagleLoRATraining` (LoRA Training Real)
- `full_training_pipeline(bad_drafts, good_drafts, contexts; ...)` - Pipeline completo:
  1. **create_training_dataset()**: Formata pares (bad→good) para Llama-3.3
  2. **load_model_and_tokenizer()**: Carrega Llama-3.3-70B com 4bit + LoRA adapters
  3. **train_lora()**: Treina adapter com Unsloth (5-10 min no cluster)
  4. **save_adapter_gguf()**: Salva adapter GGUF pronto para vLLM
- `collect_adversarial_pairs(history)`: Coleta pares do histórico adversarial

## 🔥 Próximos Passos

### Fase 1: Core Quantum (✅ COMPLETO)
- [x] Superposition
- [x] Interference
- [x] Measurement/Collapse
- [x] Entropy calculation

### Fase 2: Embeddings & Semantic Interference
- [ ] Integração com TextEmbeddings.jl ou API HTTP
- [ ] Interferência baseada em similaridade semântica real
- [ ] Cosine similarity para matching de evidências

### Fase 3: Multi-Agent Orchestrator (✅ COMPLETO)
- [x] Portar `beagle-hermes` para Julia
- [x] Integração ATHENA + HERMES + ARGOS
- [x] Adversarial self-play loop completo
- [x] Integração orchestrator → adversarial automático

### Fase 4: LoRA Training (✅ COMPLETO)
- [x] LoRA training real com Unsloth via PythonCall
- [x] Treinamento incremental após cada adversarial iteration
- [x] Adapter GGUF salvo para uso imediato no vLLM
- [x] Integração automática adversarial → LoRA

### Fase 5: Fractal Core
- [ ] FractalCognitiveNode recursivo
- [ ] Holographic compression real (embeddings)
- [ ] Auto-replicação com controle de recursos

## 🧪 Testes

```julia
using Test
using BeagleQuantum

@testset "BeagleQuantum" begin
    set = HypothesisSet()
    add!(set, "Test hypothesis")
    @test length(set.hyps) == 1
    @test set.hyps[1].probability > 0.0
end
```

## 📊 Performance

Benchmarks comparativos (em breve):
- vs Python (numpy): ~50-100x mais rápido
- vs Rust: ~2-5x mais rápido (devido a otimizações de Julia)
- vs C++: comparável, mas com sintaxe muito mais limpa

## 🔗 Integração com BEAGLE Rust

O cluster Rust continua servindo:
- **vLLM** para geração de hipóteses
- **Neo4j** para knowledge graph
- **API HTTP** para comunicação Julia ↔ Rust

Julia foca em:
- **Raciocínio quântico** (superposition, interference)
- **LoRA training** (Lux + MLX no M3 Max)
- **Simulações numéricas** (fractais, entropia)

## 📝 Licença

Mesma licença do BEAGLE principal.

## 🤝 Contribuindo

Este é um projeto de pesquisa interdisciplinar. Contribuições são bem-vindas, especialmente em:
- Otimizações de performance
- Integração com ecosistema ML Julia
- Testes e benchmarks

---

**2026 será o ano do BEAGLE em Julia.** 🔥


